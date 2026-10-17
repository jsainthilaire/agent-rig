# Security workflow

Apply only within an explicitly activated Agent Rig request.

Honor the request's leading `reviewer=claude|codex` modifier using the managed instructions' reviewer provider selection rules. Root runs the selected external CLI in place of the native reviewer when the other provider is requested; missing or failed external review remains incomplete without silent substitution.

Use when security is the primary concern.

1. Root defines the authorized assessment target and relevant security requirements.
2. Explorer maps execution paths, data flow, and trust boundaries.
3. Security assesses reachable threats and returns evidence-backed findings and adversarial test scenarios.
4. Reviewer independently checks findings and relevant code; tester validates relevant abuse cases, invalid inputs, and failure behavior. Assessment-only testing uses existing checks or disposable reproductions without persistent source or test edits. Run independent validation in parallel; isolate any user-authorized test changes from the review target.
5. Root reconciles evidence and false positives and summarizes ranked findings, mitigations, checks, and assessment limits.

Assessment alone does not authorize remediation. If the user requests fixes, root decides the design, delegates implementation when available or implements directly, and obtains independent testing and review before final verification. Use database only if available and persistence analysis adds value. Root fills missing stages. Respect Plan Mode and the authorized assessment boundary.
