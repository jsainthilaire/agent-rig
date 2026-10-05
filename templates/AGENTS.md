## Activation: explicit workflow aliases only

Agent Rig activates only when the user's request starts with a standalone `@feature`, `@bug`, `@review`, `@security`, or `@quick` token, after optional whitespace. An alias mentioned later, quoted, or shown as an example does not activate it. These tokens select workflows, not individual agents, and are prompt conventions rather than native Codex commands.

Without a leading workflow alias, Agent Rig is inactive. Ignore the rest of this managed section and use the user's existing setup, project instructions, and normal Codex behavior. Do not automatically select a Rig workflow, read Rig workflow files, impose Rig coordination or validation rules, or spawn `agent_rig_*` roles. Existing non-Rig agents remain governed by the user's setup. Evaluate activation for each user request; a previous alias does not activate a later unprefixed request.

All rules and installed-role lists below apply only within an explicitly activated Agent Rig request. A bounded assignment to a subagent remains part of that activated request; include its workflow context in the assignment.

## Root ownership and workflow selection

The root agent owns the user's outcome: understand the request, select a workflow, decide the design, delegate bounded work, reconcile findings, coordinate edits, verify completion, and present the result. Subagents support these decisions and must not redefine the goal.

The installed preset lists the roles and workflows available through Agent Rig. Treat those lists as the available Agent Rig set; do not assume every role is installed. When both global and project Agent Rig sections are present, use the project section's preset, role list, and workflow paths. Additional roles or rules supplied by this repository remain repository-specific.

The leading alias selects the corresponding workflow when installed. Honor that selection unless clearly inappropriate; explain any change. If an alias is unavailable, explain and adapt the closest available workflow to the same requested outcome, with root handling missing expertise. An unavailable review or assessment workflow still does not authorize implementation. Workflow adaptation is allowed only after explicit activation.

Before delegating, read the selected workflow from its path in the installed workflow list below. For an activated request, these instructions authorize root to spawn available Rig specialist agents when bounded delegation or independent validation adds value. Use the namespaced Codex names listed below, such as `agent_rig_explorer`, rather than generic role names belonging to the user's existing setup. Quick is root-only. Do not spawn a role merely because it exists. When delegation is unavailable, root performs the necessary stages and reports any loss of independent validation.

Resolve relative workflow paths against the directory containing this Agent Rig section, including when working in a project subdirectory. Global workflow paths are absolute.

## Coordination and independent validation

- Give each assignment the active Rig workflow, goal, requirements, relevant context, bounded scope, expected output, and explicit file ownership when edits are needed.
- Keep architectural decisions and acceptance of review findings with root. Root handles diagnosis or implementation when the preset lacks debugger or implementer.
- For assessment-only requests, use existing checks or disposable reproductions and report proposed tests and fixes without persistent source or test edits. When the user requests changes, root assigns implementation and test ownership.
- Run independent exploration, specialist analysis, or separate debugging hypotheses in parallel when useful. Avoid duplication and overlapping edits.
- Assign disjoint file ownership before multiple agents write. Sequence changes when ownership overlaps; preserve existing user work.
- Keep orchestration shallow: root normally delegates directly. Subagents must not spawn further agents without explicit root authorization and a clear benefit.
- Obtain independent testing and review after substantial implementation. When running them in parallel, reviewer examines an explicit stable target; tester edits only separately owned test files outside that target. Reconcile and review subsequent tests and fixes before final verification.
- Ask specialists for evidence, locations, and limitations. Rank actionable review findings CRITICAL/HIGH/MEDIUM/LOW; do not manufacture findings. Root resolves conflicting recommendations with evidence.
- Close or reuse finished agents where supported and respect the runtime's concurrency limits. Root always performs final verification and states which checks passed, failed, or could not run.

## Project customization and session boundaries

Repository-specific instructions outside this managed section and applicable directory instructions govern project conventions. Apply Agent Rig only to explicitly activated requests; resolve conflicts in favor of the user's explicit instructions and applicable repository-specific requirements, subject to higher-priority session instructions.

Preserve the active collaboration mode. Plan Mode permits exploration and planning, not implementation; delegation does not bypass it. Respect permission and tool boundaries. Agent Rig cannot enable tools or override runtime restrictions.

Projects may edit installed roles and workflows or override model settings. The installer protects local edits on future installs. Keep project-specific instructions outside this marked section when possible so they survive updates.
