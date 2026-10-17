# Codex model policy

Codex source role TOML files own their shipped model and reasoning effort defaults. The installer applies optional per-role overrides when rendering installed agents. Neither Claude model aliases nor Claude settings participate in Codex selection.

Use `agent-rig config init --rig` or `agent-rig config init --target DIRECTORY` to generate an editable default-based INI file. Add `--interactive` for guided creation. Installation asks before loading discovered files; `--use-models-config` accepts loading and `--ignore-models-config` skips discovery. `--role-model ROLE=MODEL` and `--role-effort ROLE=EFFORT` override individual settings. Explicit choices are retained across updates; `default` clears one setting and `--reset-role ROLE|all` clears saved choices before file/CLI input. See the [configuration guide](../../../README.md#choose-your-own-models-and-effort).

Installed native role files remain editable and protected by conflict handling. Source TOML edits change shipped defaults for future installs. The saved `.agent-rig/codex/models/overrides.ini` is managed installer state; user-authored input files remain through uninstall.

See the [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
