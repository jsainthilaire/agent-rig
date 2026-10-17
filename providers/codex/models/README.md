# Codex model policy

Codex source role TOML files own their shipped model and reasoning effort defaults. The installer applies optional per-role overrides when rendering installed agents. Neither Claude model aliases nor Claude settings participate in Codex selection.

Use `agent-rig config init --rig` or `agent-rig config init --target DIRECTORY` to generate an editable default-based INI file. Add `--interactive` for guided creation. Installation asks before loading discovered files; `--use-models-config` accepts loading and `--ignore-models-config` skips discovery. `--role-model ROLE=MODEL` and `--role-effort ROLE=EFFORT` override individual settings. Explicit choices are retained across updates; `default` clears one setting and `--reset-role ROLE|all` clears saved choices before file/CLI input. See the [configuration guide](../../../README.md#choose-your-own-models-and-effort).

Installed native role files remain editable and protected by conflict handling. Source TOML edits change shipped defaults for future installs. The saved `.agent-rig/codex/models/overrides.ini` is managed installer state; user-authored input files remain through uninstall.

For one request, use `rig feature effort=max : Add search.` (also `effort=xhigh` or `effort=ultra`). The post-colon form `rig feature: effort=max Add search.` and compatibility form `@feature effort=max Add search.` work too. A contiguous leading `reviewer=` modifier may appear before or after a post-colon effort. Choose one value; missing effort retains the installed role defaults, and invalid or repeated leading efforts are rejected before delegation. Later or quoted tokens are ordinary task text.

The installer creates three managed variants per selected role: `agent_rig_<role>_effort_xhigh`, `agent_rig_<role>_effort_max`, and `agent_rig_<role>_effort_ultra`. Each retains the role's effective rendered model and instructions and pins the requested effort. If the canonical role inherits its model, its variants still inherit that model. Variants participate in normal conflict detection, preset switching, backup, rollback, and uninstall. Reinstall after changing source defaults or overrides to refresh them; a request never edits the installation. Edits made directly to an installed canonical role are not copied into variants.

Root selects the installed variant for every native specialist assignment, including follow-ups. Native role file settings override spawn-time model/effort choices; a spawn override on the canonical role cannot provide this behavior. The modifier does not change root effort, has no specialist effect in root-only quick, preserves read-only planning assignments, and leaves an external reviewer's provider/model defaults unchanged. Missing variants or unsupported runtime/model efforts must be reported without silently downgrading. Codex persistent effort inputs also accept `ultra`; Claude does not accept `ultra`.

The supported effort levels depend on the selected model and Codex client. Installing or validating a variant does not prove live model access or support. See the [Codex subagents guide](https://learn.chatgpt.com/docs/agent-configuration/subagents).

See the [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
