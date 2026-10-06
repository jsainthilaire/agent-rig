## Activation: explicit workflow aliases only

Agent Rig activates only when the user's request starts with a standalone `@feature`, `@bug`, `@review`, `@security`, or `@quick` token, after optional whitespace. Quoted aliases, examples, and mentions later in a request do not activate it. These are prompt conventions, not native Claude Code slash commands or file imports.

Without a leading workflow alias, Agent Rig is inactive. Ignore the rest of this managed section and use the user's existing setup, project instructions, and normal Claude Code behavior. Do not automatically read Rig workflows, impose Rig coordination rules, or delegate to `agent-rig-*` roles. Re-evaluate each user request; a previous alias does not activate a later unprefixed request.

All rules and installed-role lists below apply only within an explicitly activated Agent Rig request. Bounded subagent assignments remain part of that activated request; include the workflow context in each assignment.

## Root ownership and workflow selection

Root owns the user's outcome: understand the request, choose the design, delegate bounded work, reconcile evidence and findings, coordinate edits, verify completion, and present the result. Subagents advise or implement assigned work; they do not redefine the goal.

Use the preset, roles, and workflow paths installed below. When both project and user-level Claude Rig sections are present, use the project section's preset, role list, and workflow paths. Do not assume every role is installed. A full preset makes roles available, not mandatory.

Read the selected workflow before delegation. Honor the leading alias unless clearly inappropriate; explain any adaptation. If a workflow or specialist is absent, root performs the necessary stages. Review and security assessments do not authorize implementation by themselves.

Use Claude Code's native subagent mechanism with the names listed below, such as `agent-rig-explorer`. Provide every subagent with the active workflow, goal, requirements, relevant context, bounded scope, expected output, and explicit ownership of any files it may edit. Subagents have separate context; do not assume they received the conversation. Use foreground subagents for stages whose results are needed before proceeding. Run independent analysis in parallel only when useful and supported. Do not use Agent Teams or require worktree isolation.

Quick is root-only. If subagents are unavailable, root completes the required stages and reports any loss of independent validation. Respect the runtime's concurrency limits.

Resolve relative workflow paths against the directory containing this Rig section, even when the session starts in a project subdirectory. User-level workflow paths are absolute.

## Coordination and independent validation

- Keep design, diagnosis, and acceptance of findings with root. Assign independent debugging hypotheses rather than duplicating investigations.
- Assign disjoint file ownership before concurrent edits; sequence work with overlapping ownership and preserve existing user changes.
- Explorer, database, reviewer, and security inspect and report. They have read and search tools without shell or editing tools. Root or implementer owns repairs. Debugger may run safe checks using Bash but must not edit source or shared state.
- Tester may execute checks and edit explicitly assigned tests. For assessment-only work, use existing checks or disposable reproductions without persistent edits.
- After substantial implementation, obtain independent testing and review of a stable target. Parallel testing must keep writes outside that review target. Reconcile valid findings, test affected behavior, and review later fixes and tests before final verification.
- Ask for evidence, locations, limitations, and actionable findings ranked CRITICAL/HIGH/MEDIUM/LOW. Do not manufacture findings. Root resolves disagreements with evidence.
- Subagents return to root and must not spawn other subagents. Root always performs final verification and reports passed, failed, or unavailable checks.

## Project customization and permissions

Instructions outside this section govern project conventions. Resolve conflicts in favor of explicit user instructions and applicable project requirements, subject to runtime policies. Preserve the current permission mode; plan mode allows analysis, not persistent edits. Do not bypass permissions, enable tools, or change settings to perform Rig work.

This provider owns Claude instructions only. Use this section and the Claude workflows listed below independently of Codex configuration. No imports of another provider's instructions are required.

Keep project-specific instructions outside the markers so updates preserve them. Installed roles and workflows are editable copies; the installer protects local changes. Rig does not enable persistent memory, hooks, skills, or Agent Teams by default. Installed agents consume the Claude provider model policy. Local model and effort overrides belong in native agent frontmatter; preserve them and report the model the runtime actually used.

## Cost-aware model selection and bounded escalation

Use the installed default tier for each role across all presets. Explorer favors efficient repository navigation; everyday implementation, database analysis, testing, and independent debugging hypotheses use balanced models. Reviewer and security use strong models for independent judgment. A role's available tools and file ownership remain unchanged when its model changes. Quick stays root-only and does not change the user's root model.

Escalate only with concrete evidence: low confidence backed by missing reasoning, a valid fix followed by continuing failures, material debugger disagreement, architectural uncertainty, unresolved high-impact security risk, irreversible migration consequences, or findings root cannot reconcile. First narrow the assignment and supply missing repository context. Raise explorer to balanced if navigation is unreliable. Raise balanced work to strong when needed, especially high-risk financial data, complex migrations, distributed transactions, or subtle concurrency. Use escalation only after strong reasoning is insufficient or an exceptional high-value decision justifies it. Do not run escalating copies routinely or repeat identical hypotheses.

Before an escalated attempt, root states the trigger, the bounded question, the exact model ID from the installed tier table, the retained tool/file boundaries, and the stop condition. Permit one bounded attempt at each higher tier; return evidence and unresolved limitations rather than escalating indefinitely. Use a native per-invocation model override when supported. Model overrides do not automatically change a role's effort setting: retain its installed effort unless the runtime supports an explicit bounded effort override. Tier effort values are defaults for definitions rendered with that tier. Never rewrite installed agents or session configuration automatically to escalate.

The escalation model is a policy option, not another installed role, and is absent from normal workflow stages. If a requested model is unavailable, overridden, or substituted by runtime policy, report it; do not claim that stronger validation occurred. Respect the user's model access and permission settings. Assess cost across attempts and the completed workflow, including retries and root verification, rather than token price alone. Record actual model, effort, usage, elapsed time, findings, and validation limits when evaluating the policy.
