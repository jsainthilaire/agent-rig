# Plan workflow

Apply only within an explicitly activated Agent Rig request.

Use to research requested changes and save an actionable Markdown plan. This workflow never implements the proposed changes, even when the request describes changes to make.

1. Root records the invocation working directory before exploration, then reads relevant project instructions and inspects the current implementation without persistent edits.
2. Root clarifies the goal, intended behavior, acceptance criteria, constraints, and material tradeoffs. Resolve blocking questions before finalizing the plan; record explicit assumptions for non-blocking details.
3. Use installed specialists only when bounded research or independent review adds value. Every assignment is read-only and includes the planning-only boundary; tester or implementer availability does not authorize edits. Root performs any needed analysis when specialists are unavailable and owns all decisions and the document.
4. Prepare a decision-complete plan covering the goal, intended behavior, implementation steps, affected interfaces, test scenarios, risks, and assumptions. Reconcile specialist findings before finalizing it.
5. If the request already supplies a save destination, use it without asking again. Otherwise ask where to save, proposing `<invocation-directory>/<descriptive-kebab-case-slug>.md`. An explicitly empty reply accepts that default; silence or unavailable input does not. Keep the completed plan in chat while a destination answer is pending.
6. Resolve relative destinations against the recorded invocation directory, even if exploration changed directories. For an existing directory or a destination explicitly supplied as a directory, append the proposed filename. If the file exists, propose the first available numbered alternative, such as `<slug>-2.md`, and obtain the destination choice before writing. Only update an existing plan when the user explicitly requests that update; preserve unrelated content.
7. Preserve the active runtime mode and permissions. If writes are prohibited, return the complete plan in chat, identify the supplied or proposed destination, and mark saving as pending. Do not change modes, bypass permissions, or claim a save occurred.
8. Once a destination is selected and writes are permitted, root saves only the requested Markdown plan and creates its parent directories if needed. Read it back to verify the saved content. If saving or verification fails, return the complete plan in chat and report the failure and destination honestly.
9. After a verified save, link the file and briefly summarize the plan. Stop without starting implementation.

The requested plan document and required parent directories are the only authorized persistent changes. Do not modify source, tests, configuration, or other artifacts; do not run checks that rewrite them. General workflow adaptation and requests describing proposed changes do not relax this boundary. Saved plans are user artifacts, outside the installer's manifests, and remain through Rig updates and uninstall.
