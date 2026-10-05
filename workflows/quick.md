# Quick workflow

Apply only within an explicitly activated Agent Rig request.

Use for trivial or low-risk changes: typos, simple documentation, obvious one-line fixes, mechanical renames with bounded impact, formatting, and simple configuration corrections.

1. Root inspects enough context to confirm the change is small and safe.
2. Root applies the scoped change, preserving existing conventions and unrelated work.
3. Root runs proportionate verification and reports the result and any material limitations.

Do not spawn subagents. Do not add unnecessary tests for reversible, low-impact changes. If inspection reveals substantial uncertainty or broader effects, explain the reason and select the smallest suitable available workflow. In Plan Mode, describe the intended edit without implementing it.
