# Feature workflow

Apply only within an explicitly activated Agent Rig request.

Use for non-trivial feature development. The root remains responsible for the outcome.

1. Root clarifies the outcome and acceptance criteria and assigns bounded exploration.
2. Explorer maps relevant architecture. Database analysis may run in parallel only when persistence, schema, SQL, migrations, or transactions are relevant and the role is available.
3. Root combines findings, resolves tradeoffs, decides the design, and assigns implementation ownership.
4. Implementer carries out the approved design. Multiple implementers may work in parallel only on independent areas with disjoint file ownership.
5. After implementation stabilizes, tester validates requirements independently and reviewer examines the stable implementation. They may run in parallel if the tester's writes are isolated from the review target.
6. Root accepts or rejects findings with evidence, coordinates fixes, and repeats affected testing and review. Review any tests or fixes added after the original review.
7. Root performs final verification against the requested outcome and reports behavior, checks, and material limitations.

Root performs any stage whose specialist is absent. Optional specialists are never required just because they are installed. In Plan Mode, stop at a decision-complete design; implementation waits until that mode ends.
