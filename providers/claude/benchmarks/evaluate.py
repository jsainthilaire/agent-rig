#!/usr/bin/env python3
"""Validate benchmark cases and summarize manually graded, actual model runs.

No model calls are made. Run with --check, or --results measured.jsonl.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import math
from pathlib import Path
import runpy
import re
import statistics
import sys

BENCHMARK_ROOT = Path(__file__).resolve().parent
USAGE_RATES = {
    "input_tokens": "input_usd", "output_tokens": "output_usd",
    "cache_creation_5m_input_tokens": "cache_write_5m_usd",
    "cache_creation_1h_input_tokens": "cache_write_1h_usd",
    "cache_read_input_tokens": "cache_read_usd",
}
WORKFLOWS = {"explorer", "feature", "bug", "review", "security", "quick"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value, label, maximum=None):
    require(type(value) in {int, float} and math.isfinite(value) and value >= 0, f"{label} must be a finite nonnegative number")
    require(maximum is None or value <= maximum, f"{label} exceeds {maximum}")
    return value


def string(value, label):
    require(isinstance(value, str) and value.strip(), f"{label} must be nonempty")
    return value


def load_suite(directory=BENCHMARK_ROOT):
    data = json.loads((directory / "cases.json").read_text())
    require(data.get("version") == 1, "Unsupported benchmark schema")
    cases = {}
    roles = set()
    for case in data["cases"]:
        case_id = string(case.get("id"), "case ID")
        require(case_id not in cases, "Duplicate benchmark case")
        roles.add(case["role"])
        string(case.get("prompt"), "case prompt")
        require(case.get("rubric") and case.get("hard_checks"), "Missing case rubric or hard checks")
        for path in case["context"]:
            candidate = (directory / "fixture" / path).resolve()
            require(candidate.is_relative_to((directory / "fixture").resolve()) and candidate.is_file(), "Unsafe or missing fixture path")
        cases[case_id] = case
    require(roles == {"explorer", "implementer", "database", "tester", "debugger", "reviewer", "security"}, "Benchmarks must cover all seven roles")
    return cases


def cost(record, policy):
    usage = record.get("usage", {})
    require(isinstance(usage, dict) and not (usage.keys() - USAGE_RATES.keys()), "Unknown usage fields")
    for key, value in usage.items():
        require(type(value) is int and value >= 0, f"{key} must be a nonnegative integer")
    if "reported_cost_usd" in record:
        return number(record["reported_cost_usd"], "reported cost")
    require(usage and "input_tokens" in usage and "output_tokens" in usage, "Provide measured input/output usage or actual reported cost")
    model = record["model"]
    rates = next((tier for tier in policy["tiers"].values() if tier["model"] == model), None)
    require(rates is not None, "Unknown model pricing: update candidate policy or provide reported_cost_usd")
    return sum(tokens * rates[USAGE_RATES[key]] / 1_000_000 for key, tokens in usage.items())


def grade(record, case, policy):
    scores = record.get("scores", {})
    checks = record.get("hard_checks", {})
    require(isinstance(scores, dict) and scores.keys() == case["rubric"].keys(), "Scores must cover the case rubric exactly")
    require(isinstance(checks, dict) and set(checks) == set(case["hard_checks"]), "Hard checks must cover the case exactly")
    for key, value in scores.items():
        number(value, f"score {key}", 1)
    require(all(type(value) is bool for value in checks.values()), "Hard checks must be booleans")
    score = statistics.mean(scores.values())
    passed = score >= policy["roles"][record["role"]]["threshold"] and all(checks.values())
    if record["role"] in {"reviewer", "security"}:
        passed = passed and record["false_positives"] == 0
    return score, passed


def summarize(records, policy, cases):
    runs = {}
    roles = defaultdict(list)
    outcomes = {}
    for record in records:
        run_id = string(record.get("run_id"), "run ID")
        workflow = record.get("workflow")
        require(workflow in WORKFLOWS, "Invalid workflow")
        elapsed = number(record.get("latency_seconds"), "elapsed time")
        if record.get("type") == "outcome":
            require(run_id not in outcomes and type(record.get("success")) is bool, "Duplicate or invalid outcome")
            outcomes[run_id] = record
            continue
        require(record.get("type") == "agent", "Unknown measurement type")
        role = record.get("role")
        require(role in policy["roles"] or role == "root", "Unknown role")
        task_id = string(record.get("task_id"), "bounded task ID")
        model = string(record.get("model"), "actual model")
        require(re.fullmatch(r"claude-[a-z]+-[0-9]+(?:-[0-9]+)*", model), "Record the actual model ID, not a rolling alias")
        require("effort" in record, "Record actual effort explicitly, or null when unsupported")
        require(record.get("effort") in {None, "low", "medium", "high", "xhigh", "max"}, "Invalid actual effort")
        for key in ("false_positives", "tool_errors"):
            require(type(record.get(key)) is int and record[key] >= 0, f"{key} must be a nonnegative integer")
        run = runs.setdefault(run_id, {"workflow": workflow, "cost_usd": 0, "attempts": 0})
        require(run["workflow"] == workflow, "Run workflow changed between attempts")
        attempt = {"cost_usd": cost(record, policy), "latency_seconds": elapsed,
                   "run_id": run_id, "task_id": task_id, "false_positives": record["false_positives"],
                   "tool_errors": record["tool_errors"], "cost_basis": "reported" if "reported_cost_usd" in record else "estimated", "model": record["model"], "effort": record.get("effort")}
        if role != "root":
            case = cases.get(record.get("case_id"))
            require(case is not None and case["role"] == role, "Case does not match role")
            attempt["score"], attempt["passed"] = grade(record, case, policy)
        roles[role].append(attempt)
        run["cost_usd"] += attempt["cost_usd"]
        run["attempts"] += 1
    require(runs.keys() == outcomes.keys(), "Every measured run needs exactly one final outcome and at least one attempt")
    role_report = {}
    for role, attempts in roles.items():
        total_cost = sum(a["cost_usd"] for a in attempts)
        summary = {"attempts": len(attempts), "total_cost_usd": round(total_cost, 6),
                   "average_attempt_cost_usd": round(total_cost / len(attempts), 6),
                   "average_attempt_latency_seconds": statistics.mean(a["latency_seconds"] for a in attempts),
                   "false_positives": sum(a["false_positives"] for a in attempts),
                   "tool_errors": sum(a["tool_errors"] for a in attempts),
                   "models": sorted({a["model"] for a in attempts}),
                   "efforts": sorted({a["effort"] or "unsupported" for a in attempts}),
                   "reported_cost_attempts": sum(a["cost_basis"] == "reported" for a in attempts),
                   "estimated_cost_attempts": sum(a["cost_basis"] == "estimated" for a in attempts)}
        if role != "root":
            # Count each bounded task once, using its final attempt. Earlier
            # retries and failed tasks still contribute to total cost.
            final_tasks = {(a["run_id"], a["task_id"]): a for a in attempts}
            successful = sum(a["passed"] for a in final_tasks.values())
            summary.update({"quality_threshold": policy["roles"][role]["threshold"],
                            "mean_rubric_score": statistics.mean(a["score"] for a in attempts),
                            "successful_tasks": successful, "tasks": len(final_tasks),
                            "attempt_pass_rate": sum(a["passed"] for a in attempts) / len(attempts),
                            "cost_per_successful_task_usd": round(total_cost / successful, 6) if successful else None})
        role_report[role] = summary
    workflow_report = {}
    for workflow in sorted({run["workflow"] for run in runs.values()}):
        selected = [(run_id, run) for run_id, run in runs.items() if run["workflow"] == workflow]
        for run_id, _ in selected:
            require(outcomes[run_id]["workflow"] == workflow, "Outcome workflow does not match attempts")
        successes = sum(outcomes[run_id]["success"] for run_id, _ in selected)
        total_cost = sum(run["cost_usd"] for _, run in selected)
        workflow_report[workflow] = {"runs": len(selected), "successes": successes,
                                    "total_cost_usd": round(total_cost, 6),
                                    "average_run_cost_usd": round(total_cost / len(selected), 6),
                                    "cost_per_successful_outcome_usd": round(total_cost / successes, 6) if successes else None,
                                    "average_wall_latency_seconds": statistics.mean(outcomes[run_id]["latency_seconds"] for run_id, _ in selected),
                                    "total_agent_attempts": sum(run["attempts"] for _, run in selected)}
    return {"policy_reviewed": policy["reviewed"], "roles": role_report, "workflows": workflow_report}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--results", type=Path)
    parser.add_argument("--models", type=Path, default=BENCHMARK_ROOT.parent / "models")
    args = parser.parse_args()
    try:
        cases = load_suite()
        loader = runpy.run_path(str(BENCHMARK_ROOT.parent / "models/policy.py"))["load"]
        policy = loader(args.models)
        if args.check:
            print(f"Validated {len(cases)} benchmark cases and Claude policy; no model runs performed.")
        if args.results:
            records = [json.loads(line) for line in args.results.read_text().splitlines() if line.strip()]
            require(records, "Results are empty")
            report = summarize(records, policy, cases)
            report["policy_sha256"] = hashlib.sha256((args.models / "policy.tsv").read_bytes()).hexdigest()
            print(json.dumps(report, indent=2, sort_keys=True))
        require(args.check or args.results, "Choose --check or --results")
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"Claude benchmark evaluation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
