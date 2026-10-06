# Claude role benchmarks

[cases.json](cases.json) defines one small seeded task per role; [fixture/](fixture/) is a disposable Python repository. The suite covers navigation, scoped coding and validation, migration reasoning, independent test discovery, async root-cause diagnosis, stable-target review, and tenant authorization. The fixture deliberately contains defects and is not production code.

Run offline consistency checks:

```bash
python3 providers/claude/benchmarks/evaluate.py --check
```

For an actual trial, copy the fixture to a fresh temporary directory. Give the model only the selected case's prompt and context, preserving its role tools and file ownership. Keep the rubric and hard checks for independent grading. Use the pinned model and effort under evaluation, collect the transcript, actual model/effort, tool failures, token usage, elapsed wall time, and reported cost when available. Verify allowed edits from the diff; inspect commands for shared-state changes. Grade against the rubric and required hard checks, including known seeded defects and false positives. Discard the temporary repository after grading. Do not give subsequent candidates a previous candidate's solution or mutate this source fixture.

Score each rubric item from 0 to 1: 0 is wrong/missing, 0.5 is partial, and 1 is complete. Hard checks must all pass. Reviewer/security findings must have zero false positives for the initial acceptance gate. Thresholds in the model policy are opinionated initial targets, not measured performance. Several independent trials and real repository tasks are required to support an upgrade decision. Repeat representative feature, bug, review, and security workflows after role trials; include parallel debug attempts, retries, and root verification.

## Measured result records

[evaluate.py](evaluate.py) reads JSONL records and reports role quality, tool failures, latency, average attempt cost, cost per successful bounded task, and workflow cost per successful outcome. Failed attempts and failed workflows remain in the numerator. Zero-success groups have a null cost-per-success value. The final attempt determines whether a bounded role task passed; use distinct task IDs for independent debugger hypotheses. Whole-workflow elapsed time comes from the outcome record, so parallel agent times are not incorrectly summed.

An agent attempt records actual measurements and independent grading:

```json
{"type":"agent","run_id":"trial-1","task_id":"explore-1","workflow":"feature","role":"explorer","case_id":"explorer-map","model":"claude-haiku-4-5-20251001","effort":null,"latency_seconds":8.2,"usage":{"input_tokens":1500,"output_tokens":400},"false_positives":0,"tool_errors":0,"scores":{"call_paths":1,"tests":1,"conventions":1,"scope":1},"hard_checks":{"call_paths":true,"read_only":true}}
```

The example describes the schema, not a measured run. Add one final record per workflow trial, verified independently against the requested outcome:

```json
{"type":"outcome","run_id":"trial-1","workflow":"feature","success":true,"latency_seconds":42.0}
```

Root work uses `role: "root"` with actual usage/cost, model, effort, latency, false-positive and tool-error counts; no case ID, scores, or hard checks are required. Include every billable attempt. Record outcomes only after all attempts and final verification; do not mark the example's partial feature trial complete without the other stages actually required for that trial.

```bash
python3 providers/claude/benchmarks/evaluate.py --results /path/to/measured.jsonl
```

For API estimates, `input_tokens` must exclude cache reads/writes; `output_tokens` must include all billable output. Optional disjoint usage fields are `cache_creation_5m_input_tokens`, `cache_creation_1h_input_tokens`, and `cache_read_input_tokens`. Use `reported_cost_usd` for actual billed cost or pricing conditions outside the frozen standard rates. Unknown model pricing is rejected unless actual cost is supplied. Candidate model metadata can be provided with `--models /path/to/candidate-model-policy-directory`; that directory must contain a policy TSV compatible with the current validator. Subscription billing is not inferred from token estimates.

Reports record the policy review date and source policy hash. Save raw measured records, transcripts, grader evidence, and reports with upgrade review evidence. Compare quality, coding, reasoning, repository understanding, tool reliability, latency, token usage, context fit, relevant knowledge gaps, false positives, retry rates, and full workflow costs. Lower token prices alone do not establish a cheaper successful workflow.

Offline checks and unit tests validate this measurement pipeline without calling a model. No authenticated model evaluations or pricing guarantees are implied by passing those checks.
