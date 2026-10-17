# Review workflow

Apply only within an explicitly activated Agent Rig request.

Honor the request's leading `reviewer=claude|codex` modifier using the managed instructions' reviewer provider selection rules. Root runs the selected external CLI in place of the native reviewer when the other provider is requested; missing or failed external review remains incomplete without silent substitution.

Use when the requested outcome is review of existing code or a proposed change.

1. Root identifies the requirements and a stable review target, including its base or comparison when relevant.
2. Reviewer performs an independent review. Security and database may review in parallel when those concerns provide meaningful value and their roles are available.
3. Root combines and deduplicates findings, resolves disagreements using evidence, and ranks accepted findings CRITICAL/HIGH/MEDIUM/LOW.
4. Root presents actionable findings with locations, triggers, impact, and validation limitations. If there are no actionable findings, say so clearly.

Review does not authorize implementation. Recommend corrections without modifying code unless the user also requests fixes; then root selects an appropriate implementation workflow. Root fills any missing specialist stage. Avoid unnecessary security or database participation.
