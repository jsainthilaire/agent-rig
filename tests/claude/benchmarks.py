#!/usr/bin/env python3
"""Regression checks for independent grading and full-outcome cost accounting."""
import copy
import math
from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[2]
BENCHMARK = runpy.run_path(str(ROOT / "providers/claude/benchmarks/evaluate.py"))
POLICY = runpy.run_path(str(ROOT / "providers/claude/models/policy.py"))["load"](ROOT / "providers/claude/models")
CASES = BENCHMARK["load_suite"]()


def attempt(run_id="one", task_id="explore", score=1):
    return {"type": "agent", "run_id": run_id, "task_id": task_id, "workflow": "feature",
            "role": "explorer", "case_id": "explorer-map", "model": "claude-haiku-4-5-20251001",
            "effort": None, "latency_seconds": 10, "false_positives": 0, "tool_errors": 0,
            "usage": {"input_tokens": 1000, "output_tokens": 200, "cache_creation_5m_input_tokens": 100,
                      "cache_creation_1h_input_tokens": 50, "cache_read_input_tokens": 500},
            "scores": {key: score for key in CASES["explorer-map"]["rubric"]},
            "hard_checks": {key: True for key in CASES["explorer-map"]["hard_checks"]}}


def outcome(run_id="one", success=True, latency=30):
    return {"type": "outcome", "run_id": run_id, "workflow": "feature", "success": success, "latency_seconds": latency}


class Measurements(unittest.TestCase):
    def test_cache_costs_use_model_specific_rates(self):
        self.assertAlmostEqual(BENCHMARK["cost"](attempt(), POLICY), 0.002275)
        fable = {"model": "claude-fable-5-1", "usage": {"input_tokens": 1000, "output_tokens": 1000, "cache_read_input_tokens": 1000}}
        self.assertAlmostEqual(BENCHMARK["cost"](fable, POLICY), 0.06025)

    def test_retries_failed_runs_and_root_work_count_toward_success(self):
        root = {"type": "agent", "run_id": "one", "task_id": "verify", "workflow": "feature",
                "role": "root", "model": "claude-opus-5-5", "effort": "high", "latency_seconds": 5,
                "reported_cost_usd": 1, "false_positives": 0, "tool_errors": 0}
        report = BENCHMARK["summarize"]([attempt(score=0.5), attempt(), root,
                                         attempt(run_id="two", score=0.5), outcome(), outcome("two", False, 20)], POLICY, CASES)
        role = report["roles"]["explorer"]
        self.assertEqual((role["attempts"], role["tasks"], role["successful_tasks"]), (3, 2, 1))
        self.assertAlmostEqual(role["cost_per_successful_task_usd"], 0.006825)
        workflow = report["workflows"]["feature"]
        self.assertAlmostEqual(workflow["cost_per_successful_outcome_usd"], 1.006825)
        self.assertEqual(workflow["average_wall_latency_seconds"], 25)

    def test_final_failed_attempt_cannot_reuse_earlier_success(self):
        report = BENCHMARK["summarize"]([attempt(), attempt(score=0), outcome(success=False)], POLICY, CASES)
        self.assertEqual(report["roles"]["explorer"]["successful_tasks"], 0)
        self.assertIsNone(report["roles"]["explorer"]["cost_per_successful_task_usd"])
        self.assertIsNone(report["workflows"]["feature"]["cost_per_successful_outcome_usd"])

    def test_hard_failure_and_false_positives_override_high_score(self):
        record = attempt()
        record["hard_checks"]["read_only"] = False
        self.assertFalse(BENCHMARK["grade"](record, CASES["explorer-map"], POLICY)[1])
        record.update(role="security", false_positives=1)
        case = CASES["security-tenant-boundary"]
        record["scores"] = {key: 1 for key in case["rubric"]}
        record["hard_checks"] = {key: True for key in case["hard_checks"]}
        self.assertFalse(BENCHMARK["grade"](record, case, POLICY)[1])

    def test_unknown_pricing_requires_actual_cost(self):
        record = attempt()
        record["model"] = "claude-sonnet-5"
        with self.assertRaises(ValueError):
            BENCHMARK["cost"](record, POLICY)
        record["reported_cost_usd"] = 0.1
        self.assertEqual(BENCHMARK["cost"](record, POLICY), 0.1)

    def test_invalid_measurements_and_incomplete_grading_are_rejected(self):
        for key, value in (("input_tokens", -1), ("output_tokens", True), ("input_tokens", math.nan)):
            record = attempt()
            record["usage"][key] = value
            with self.assertRaises(ValueError):
                BENCHMARK["cost"](record, POLICY)
        record = attempt()
        record["scores"].pop("scope")
        with self.assertRaises(ValueError):
            BENCHMARK["grade"](record, CASES["explorer-map"], POLICY)

    def test_incomplete_or_mismatched_outcomes_are_rejected(self):
        for records in ([attempt()], [outcome()], [attempt(), outcome(), outcome()],
                        [attempt(), {**outcome(), "workflow": "bug"}]):
            with self.assertRaises(ValueError):
                BENCHMARK["summarize"](copy.deepcopy(records), POLICY, CASES)


if __name__ == "__main__":
    unittest.main()
