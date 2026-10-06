# Bug workflow

Apply only within an explicitly activated Agent Rig request.

Use for a failure whose cause is not immediately obvious. For an obvious low-risk fix, choose quick unless the user's explicit choice warrants the additional investigation.

1. Root establishes observed versus expected behavior and a reproduction or concrete failure evidence.
2. Explorer traces the relevant execution and data paths.
3. When the cause remains ambiguous and debugger is available, root assigns separate, discriminating hypotheses to debugger agents. Run independent investigations in parallel; avoid repeated exploration of the same hypothesis. Use one debugger when a second would add little value.
4. Root combines evidence, eliminates unsupported hypotheses, and decides the diagnosis and smallest valid fix.
5. Implementer applies that fix within explicit ownership. If implementer is absent, root implements it.
6. Tester independently verifies the failure scenario, appropriate regression coverage, and relevant edge cases.
7. Reviewer independently reviews the stable fix. Root coordinates accepted corrections and affected rechecks.
8. Root performs final verification and reports the cause, corrected behavior, checks, and unresolved limitations.

When debugger is absent, root investigates and owns the diagnosis. Root performs other missing stages as needed. Do not apply speculative fixes before establishing enough evidence. In Plan Mode, produce the diagnosis and fix plan without editing files.
