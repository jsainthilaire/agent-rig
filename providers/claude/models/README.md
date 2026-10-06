# Claude model policy

[policy.tsv](policy.tsv) is the single source of truth for Claude role models, effort defaults, pricing metadata, and quality thresholds. All presets share it. The provider renders native model and effort frontmatter into installed agents, copies the validated policy to `.agent-rig/claude/models/policy.tsv`, and includes the tier table in the managed `CLAUDE.md` section. Codex assets and model policy remain independent.

Policy reviewed on **2026-10-05**. These defaults follow the requested role strategy and current provider specifications; they have not yet been proven the cheapest reliable choices by authenticated benchmark runs.

| Tier | Pinned model | Assigned roles | Effort |
| --- | --- | --- | --- |
| FAST | `claude-haiku-4-5-20251001` | explorer | omitted; unsupported |
| BALANCED | `claude-sonnet-5-5` | implementer, database, tester, debugger | medium |
| STRONG | `claude-opus-5-5` | reviewer, security | high |
| ESCALATION | `claude-fable-5-1` | exceptional bounded attempts only | high for definitions using this tier |

The lineup and effort capabilities come from the [model reference](https://platform.claude.com/docs/en/models/overview). The dated Haiku ID and the newer dateless release IDs identify fixed snapshots, unlike rolling family aliases; see [model versioning](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions). No lookup or automatic model upgrade occurs during installation.

| Tier | Input / output USD per million tokens | Context tokens | Reliable knowledge cutoff | Relative latency |
| --- | --- | --- | --- | --- |
| FAST | $1 / $5 | 200,000 | February 2025 | fastest |
| BALANCED | $2 / $10 | 1,000,000 | June 2026 | fast |
| STRONG | $4 / $20 | 1,000,000 | June 2026 | moderate |
| ESCALATION | $10 / $50 | 1,000,000 | June 2026 | slower |

Specifications and relative latency are from the [model reference](https://platform.claude.com/docs/en/models/overview); rates, including cache writes and cache reads in the policy, are from the [pricing reference](https://platform.claude.com/docs/en/about-claude/pricing). Rates are a dated standard API estimate, not a Claude subscription bill or partner-specific quote. Use actual billed cost when available. Tokenizers differ across model generations, so measure actual usage rather than assuming identical token counts.

## Policy format and installation

TSV keeps installation dependent only on Bash and standard Unix tools. Data is validated by [policy.awk](policy.awk), never sourced as shell code. Records are:

```text
version <schema version>
reviewed <YYYY-MM-DD>
tier <name> <pinned model> <effort or -> <input rate> <output rate> <5m cache write rate> <1h cache write rate> <cache read rate> <context tokens> <knowledge cutoff YYYY-MM> <relative latency>
role <name> <default tier> <next tier> <minimum rubric score>
```

Fields are separated by tabs. Comments and blank lines are allowed. The provider rejects missing or duplicate records, aliases, malformed prices, unsupported Haiku effort, invalid role references, and default escalation roles before writing. Source agent Markdown files contain model/effort placeholders; the provider renderer replaces them, retaining tools and instructions. Source templates must be installed or rendered before use in Claude Code.

Repeat install to adopt a policy update. Generated agents, instruction tables, and the installed policy copy are managed together and participate in conflict protection, backups, uninstall, and rollback. Existing `model: inherit` installations upgrade through their recorded checksums. Local native frontmatter edits remain protected and can override defaults for one project. The installed policy copy documents the release; editing it alone does not re-render agents. Reconcile local edits or use `--replace-modified` when deliberately adopting new defaults.

## Escalation and effort

Default to FAST exploration, BALANCED engineering, and STRONG review/security. Escalate explorer to BALANCED when repository navigation is unreliable. Escalate database work for irreversible migrations, critical financial integrity, complex transaction boundaries, or subtle concurrency. Escalate debugging when discriminating investigations fail or materially disagree. STRONG work reaches ESCALATION only for exceptional unresolved risk or unusually valuable decisions.

Root states the evidence, bounded question, exact model, ownership, and stop condition before escalation. Allow one bounded attempt per higher tier, then report unresolved limitations. No escalation role is installed and normal workflows do not invoke Fable. Missing roles still fall back to root; quick does not change the root model.

Native per-invocation model overrides can select a higher tier, but the role's frontmatter effort remains unless the runtime supports a separate override. Haiku has no configurable effort; do not invent one. See the [native subagent model and effort reference](https://code.claude.com/docs/en/sub-agents). Account restrictions and forced-model settings may substitute another model: verify and record actual runtime selection. Rig does not change session settings, permissions, skills, memory, hooks, or the user's root model.

## Evaluation and deliberate upgrades

Use the provider-specific [benchmark suite](../benchmarks/README.md) before claiming reliability or changing pins. Quality thresholds are initial acceptance targets, not observed benchmark scores. Require correctness and scoped edits from implementer, independent edge-case reasoning from tester, evidence-driven diagnosis from debugger, and real findings with low false positives from reviewer/security. Read-only roles must leave the fixture unchanged. Explorer must reliably map paths before speed or cost decides between candidates.

For each candidate, evaluate coding, reasoning, repository understanding, tool-use failures, latency, input/output/cached usage, context fit, knowledge freshness relevant to the task, reliability, and cost per successful outcome. Include failed attempts, retries, parallel debugger instances, and root work in workflow totals. Compare several trials and representative real repositories, not one favorable sample. Use browsing or supplied current references for security/framework facts absent from the model's knowledge; a recent cutoff alone is not a quality result.

Change only the tiers or effort defaults justified by evidence. Review current IDs, capabilities, access, and pricing; update the review date and metadata; run representative feature, bug, review, and security workflows; then run source and lifecycle checks. Keep upgrade evidence with the release. Do not fetch a latest model automatically or change Codex as part of a Claude upgrade. Preset-specific policies, automatic project override files, and rolling aliases can be added later if useful.
