#!/usr/bin/env python3
"""Model config creation, consent, native rendering, and lifecycle regressions."""

import os
from pathlib import Path
import runpy
import shutil
import signal
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROLES = ("explorer", "implementer", "database", "tester", "reviewer", "debugger", "security")
REQUEST_EFFORTS = ("xhigh", "max", "ultra")


def files(directory):
    return {str(p.relative_to(directory)): p.read_bytes()
            for p in directory.rglob("*") if p.is_file()}


class Models(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agent-rig-models.")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.rig = self.base / "rig"
        self.rig.mkdir()
        for name in ("bin", "providers"):
            shutil.copytree(ROOT / name, self.rig / name)
        self.target = self.base / "project"
        self.target.mkdir()
        self.env = dict(os.environ, CODEX_HOME=str(self.base / "codex-home"),
                        CLAUDE_CONFIG_DIR=str(self.base / "claude-home"))

    def run_rig(self, *args, answer="", ok=True, env=None):
        result = subprocess.run(["bash", str(self.rig / "bin/agent-rig"), *map(str, args)],
                                input=answer, capture_output=True, text=True,
                                env=env or self.env, cwd=self.base, timeout=20)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def install(self, *args, provider="codex", operation="install", **kwargs):
        return self.run_rig(operation, "--provider", provider, "--target", self.target,
                            "--yes", *args, **kwargs)

    def config(self, text, path=None):
        path = path or self.target / ".agent-rig/models.ini"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def agent(self, provider="codex", role="reviewer"):
        if provider == "codex":
            return self.target / f".codex/agents/agent_rig_{role}.toml"
        return self.target / f".claude/agents/agent-rig-{role}.md"

    def assert_effort_variants(self, canonical):
        data = tomllib.loads(canonical.read_text())
        for effort in REQUEST_EFFORTS:
            name = f"{canonical.stem}_effort_{effort}"
            variant = canonical.with_name(f"{name}.toml")
            expected = dict(data, name=name, model_reasoning_effort=effort)
            self.assertEqual(tomllib.loads(variant.read_text()), expected)

    def test_generate_default_files_both_places_and_global(self):
        self.run_rig("config", "init", "--rig")
        checkout = self.rig / "models.ini"
        generated = checkout.read_text()
        self.assertEqual(generated.count("model = default"), 14)
        self.assertEqual(generated.count("effort = default"), 14)
        self.assertIn("# Current default model: gpt-6-astra", generated)
        self.run_rig("config", "init", "--target", self.target)
        self.assertEqual(files(self.target), {".agent-rig/models.ini": checkout.read_bytes()})
        self.run_rig("config", "init", "--global", "--provider", "claude")
        home_config = self.base / "claude-home/.agent-rig/models.ini"
        self.assertIn("[claude.reviewer]", home_config.read_text())
        self.assertNotIn("[codex.", home_config.read_text())
        self.run_rig("config", "init", "--global", ok=False)
        self.run_rig("config", "init", "--rig", "--target", self.target, ok=False)
        before = files(self.target)
        self.run_rig("config", "init", "--target", self.target, ok=False)
        self.assertEqual(files(self.target), before)
        self.run_rig("config", "init", "--target", self.target, "--provider", "codex", "--overwrite")
        self.assertNotIn("[claude.", (self.target / ".agent-rig/models.ini").read_text())

    def test_interactive_defaults_invalid_input_custom_values_and_cancel(self):
        answers = ["", ""] * 7
        answers[-4:] = ["bad model", "custom/reviewer:v2", "invalid-effort", "max", "", ""]
        result = self.run_rig("config", "init", "--target", self.target,
                              "--provider", "codex", "--interactive",
                              answer="\n".join(answers) + "\nyes\n")
        self.assertIn("Save this model configuration?", result.stdout)
        content = (self.target / ".agent-rig/models.ini").read_text()
        self.assertIn("model = custom/reviewer:v2", content)
        self.assertIn("effort = max", content)
        before = files(self.target)
        self.run_rig("config", "init", "--target", self.target, "--provider", "codex",
                     "--interactive", "--overwrite", answer="\n" * 14 + "no\n")
        self.assertEqual(files(self.target), before)
        self.run_rig("config", "init", "--target", self.target, "--provider", "codex",
                     "--interactive", "--overwrite", answer="\n" * 3, ok=False)
        self.assertEqual(files(self.target), before)

    def test_interactive_claude_pair_correction(self):
        # A model-only change for explorer needs an explicit effort selection.
        self.run_rig("config", "init", "--rig", "--provider", "claude", "--interactive",
                     answer="custom-model\n" + "\n" * 13 +
                     "claude.explorer.effort=high\nyes\n")
        self.assertIn("effort = high", (self.rig / "models.ini").read_text())
        self.install("--use-models-config", provider="claude")
        self.assertIn("model: custom-model", self.agent("claude", "explorer").read_text())

    def test_interactive_interruption_leaves_no_partial_config(self):
        process = subprocess.Popen(["bash", str(self.rig / "bin/agent-rig"), "config", "init",
                                    "--target", str(self.target), "--provider", "codex", "--interactive"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=self.env)
        try:
            # The first byte is a prompt; no config is published while reading.
            self.assertTrue(process.stdout.read(1))
            process.send_signal(signal.SIGINT)
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130)
            self.assertEqual(files(self.target), {})
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_consent_is_separate_and_declining_continues(self):
        self.config("[codex.reviewer]\nmodel = chosen-model\n")
        before = files(self.target)
        self.install(ok=False)
        self.assertEqual(files(self.target), before)
        result = self.install(answer="invalid\nno\n")
        self.assertIn("Model configuration files skipped", result.stdout)
        self.assertNotIn("chosen-model", self.agent().read_text())
        self.install(answer="yes\n")
        self.assertIn('model = "chosen-model"', self.agent().read_text())
        self.install("--ignore-models-config", "--models-config", self.target / ".agent-rig/models.ini", ok=False)
        self.install("--use-models-config", "--ignore-models-config", ok=False)

    def test_two_files_cli_precedence_and_explicit_input(self):
        self.config("[codex.reviewer]\nmodel = checkout-model\neffort = low\n",
                    self.rig / "models.ini")
        self.config("[codex.reviewer]\nmodel = target-model\n")
        result = self.install("--use-models-config", "--role-effort", "reviewer=max")
        data = tomllib.loads(self.agent().read_text())
        self.assertEqual((data["model"], data["model_reasoning_effort"]), ("target-model", "max"))
        self.assert_effort_variants(self.agent())
        self.assertIn("model: file-2; effort: CLI", result.stdout)
        explicit = self.config("[codex.reviewer]\nmodel = explicit-model\n", self.base / "custom models.ini")
        self.install("--models-config", explicit, "--use-models-config")
        self.assertIn('model = "explicit-model"', self.agent().read_text())
        self.install("--ignore-models-config", "--role-model", "reviewer=cli-model")
        self.assertIn('model = "cli-model"', self.agent().read_text())
        self.assert_effort_variants(self.agent())

    def test_persistence_defaults_resets_and_dormant_roles(self):
        self.install("--role-model", "reviewer=chosen-model", "--role-effort", "reviewer=low",
                     "--role-model", "security=security-choice")
        self.install("--preset", "minimal", operation="update")
        self.assertFalse(self.agent(role="security").exists())
        saved = self.target / ".agent-rig/codex/models/overrides.ini"
        self.assertIn("security-choice", saved.read_text())
        source = self.rig / "providers/codex/agents/reviewer.toml"
        source.write_text(source.read_text().replace('model = "gpt-6-astra"', 'model = "new-shipped-model"'))
        self.install(operation="update")
        self.assertIn('model = "chosen-model"', self.agent().read_text())
        self.install("--role-model", "reviewer=default", operation="update")
        data = tomllib.loads(self.agent().read_text())
        self.assertEqual((data["model"], data["model_reasoning_effort"]), ("new-shipped-model", "low"))
        self.install("--reset-role", "reviewer", operation="update")
        self.assertNotIn("[codex.reviewer]", saved.read_text())
        self.install("--preset", "full", operation="update")
        self.assertIn("security-choice", self.agent(role="security").read_text())
        self.install("--reset-role", "all", operation="update")
        self.assertEqual(saved.read_text(), "")
        self.assertIn("Already up to date", self.install(operation="update").stdout)

    def test_default_template_tracks_source_defaults(self):
        self.run_rig("config", "init", "--rig", "--provider", "codex")
        source = self.rig / "providers/codex/agents/reviewer.toml"
        source.write_text(source.read_text().replace('model = "gpt-6-astra"', 'model = "new-default"'))
        self.install("--use-models-config")
        self.assertIn('model = "new-default"', self.agent().read_text())
        self.assertFalse((self.target / ".agent-rig/codex/models/overrides.ini").exists())

    def test_custom_source_with_inherited_codex_defaults_still_installs(self):
        source = self.rig / "providers/codex/agents/reviewer.toml"
        source.write_text("\n".join(line for line in source.read_text().splitlines()
                                    if not line.startswith(("model =", "model_reasoning_effort ="))) + "\n")
        self.install()
        self.assertNotIn("model", tomllib.loads(self.agent().read_text()))
        self.assert_effort_variants(self.agent())
        self.install("--role-model", "reviewer=explicit-model", "--role-effort", "reviewer=high")
        self.assertEqual(tomllib.loads(self.agent().read_text())["model"], "explicit-model")
        self.assert_effort_variants(self.agent())

    def test_request_effort_variants_preserve_all_native_role_fields(self):
        source = self.rig / "providers/codex/agents/reviewer.toml"
        # Native-looking lines inside instructions must remain literal instructions.
        text, closing = source.read_text().rsplit('"""', 1)
        source.write_text(text + '\nname = "literal-example"\n'
                          'model_reasoning_effort = "low"\n' + '"""' + closing)
        self.install()
        for role in ROLES:
            with self.subTest(role=role):
                self.assert_effort_variants(self.agent(role=role))
        before = files(self.target)
        self.assertIn("Already up to date", self.install(operation="update").stdout)
        self.assertEqual(files(self.target), before)

    def test_ultra_is_codex_only_for_source_config_and_cli(self):
        source = self.rig / "providers/codex/agents/reviewer.toml"
        source.write_text(source.read_text().replace('model_reasoning_effort = "high"',
                                                    'model_reasoning_effort = "ultra"'))
        provider = self.rig / "providers/codex"
        validated = runpy.run_path(str(provider / "validate.py"))["validate"](provider, self.assertTrue)
        self.assertEqual(validated["reviewer"]["model_reasoning_effort"], "ultra")
        self.install()
        self.assertEqual(tomllib.loads(self.agent().read_text())["model_reasoning_effort"], "ultra")
        self.config("[codex.reviewer]\neffort = ultra\n")
        self.install("--use-models-config")
        self.assert_effort_variants(self.agent())
        self.install("--ignore-models-config", "--role-effort", "tester=ultra")
        self.assertEqual(tomllib.loads(self.agent(role="tester").read_text())["model_reasoning_effort"], "ultra")
        before = files(self.target)
        self.install("--ignore-models-config", "--role-effort", "reviewer=ultra", provider="claude", ok=False)
        self.assertEqual(files(self.target), before)
        self.config("[claude.reviewer]\neffort = ultra\n")
        before = files(self.target)
        # Entire input is validated even when its entries target the other provider.
        self.install("--use-models-config", ok=False)
        self.assertEqual(files(self.target), before)
        self.install("--use-models-config", provider="claude", ok=False)
        self.assertEqual(files(self.target), before)

    def test_variant_collisions_updates_and_preset_retirement(self):
        variant = self.agent(role="database_effort_ultra")
        variant.parent.mkdir(parents=True)
        variant.write_text('# User-owned effort role\n')
        before = files(self.target)
        rejected = self.install(ok=False)
        self.assertIn("unmanaged destination collision", rejected.stdout + rejected.stderr)
        self.assertEqual(files(self.target), before)
        self.install("--replace-modified")
        backups = self.target / ".agent-rig/codex/backups"
        self.assertTrue(any(p.read_text() == '# User-owned effort role\n'
                            for p in backups.rglob(variant.name)))
        variant.write_text(variant.read_text() + '# Local variant change\n')
        before = files(self.target)
        self.install(operation="update", ok=False)
        self.assertEqual(files(self.target), before)
        rejected = self.install("--preset", "minimal", operation="update", ok=False)
        self.assertIn("locally modified; removed by preset switch", rejected.stdout + rejected.stderr)
        self.assertEqual(files(self.target), before)
        self.install("--preset", "minimal", "--replace-modified", operation="update")
        for role in ("database", "debugger", "security"):
            self.assertFalse(self.agent(role=role).exists())
            for effort in REQUEST_EFFORTS:
                self.assertFalse(self.agent(role=f"{role}_effort_{effort}").exists())
                self.assertNotIn(f"agent_rig_{role}_effort_{effort}",
                                 (self.target / "AGENTS.md").read_text())
        for role in ("explorer", "implementer", "tester", "reviewer"):
            self.assert_effort_variants(self.agent(role=role))

    def test_request_effort_instruction_contract(self):
        # These are prompt conventions, not an executable parser. Check the
        # installed contract; live agent routing requires authenticated smoke tests.
        self.install("--preset", "minimal")
        instructions = (self.target / "AGENTS.md").read_text()
        clauses = (
            'rig feature effort=ultra:', 'rig bug effort=xhigh :',
            'rig feature: effort=max Add search.', '@feature effort=ultra Add search.',
            'whitespace before the colon is optional',
            'unknown, empty, or repeated pre-colon effort',
            'malformed Rig invocation', 'pre-colon `reviewer=` modifier is unsupported',
            '`xhigh|max|ultra` describes alternatives and is not a valid value',
            'may appear in either order after the alias',
            'Stop parsing modifiers at the first ordinary task text',
            'ignore quoted examples and later occurrences',
            'including one repeated across the colon',
            'A modifier alone never activates Rig',
            'Reset request effort for every new user request',
            'use the canonical installed role names and their configured efforts',
            'including follow-ups and replacement agents',
            'native role file settings take precedence',
            'Do not edit installations or persist configuration changes',
            'do not silently downgrade', 'does not change root\'s reasoning effort',
            'root-only execution has no specialist effort to change',
            'permitted read-only specialist assignments',
            'does not change the external reviewer',
            'An explicit native reviewer selection uses its matching effort variant',
        )
        for clause in clauses:
            with self.subTest(clause=clause):
                self.assertIn(clause, instructions)
        for role in ("explorer", "implementer", "tester", "reviewer"):
            names = ' | '.join(f'`agent_rig_{role}_effort_{effort}`' for effort in REQUEST_EFFORTS)
            self.assertIn(f'| {role} | {names} |', instructions)
        self.assertNotIn('agent_rig_database_effort_', instructions)

    def test_provider_isolation_and_claude_native_fields(self):
        config = self.config("[codex.reviewer]\nmodel = codex-choice\neffort = low\n"
                             "[claude.reviewer]\nmodel = claude-choice\neffort = max\n"
                             "[claude.explorer]\nmodel = new-model\neffort = high\n")
        self.install("--use-models-config")
        before = self.agent().read_bytes()
        self.install("--use-models-config", provider="claude")
        self.assertEqual(self.agent().read_bytes(), before)
        native = self.agent("claude").read_text()
        self.assertIn("model: claude-choice\neffort: max", native)
        source = (self.rig / "providers/claude/agents/reviewer.md").read_text()
        self.assertEqual(native.split("---", 2)[2], source.split("---", 2)[2])
        instructions = (self.target / "CLAUDE.md").read_text()
        self.assertIn("| reviewer | `claude-choice` | max |", instructions)
        manifest = (self.target / ".agent-rig/claude/manifest.tsv").read_text()
        self.assertNotIn("\t.agent-rig/models.ini\t", manifest)
        config.unlink()
        self.install(provider="claude", operation="update")
        self.assertIn("model: claude-choice", self.agent("claude").read_text())

    def test_model_and_effort_stay_independent_and_known_incompatibilities_fail(self):
        self.install("--role-model", "implementer=custom-model", provider="claude")
        self.assertIn("effort: medium", self.agent("claude", "implementer").read_text())
        before = files(self.target)
        self.install("--role-model", "implementer=claude-haiku-4-5-20251001", provider="claude", ok=False)
        self.assertEqual(files(self.target), before)
        self.install("--role-model", "implementer=claude-haiku-4-5-20251001",
                     "--role-effort", "implementer=omit", provider="claude")
        self.assertNotIn("\neffort:", self.agent("claude", "implementer").read_text())
        self.install("--role-model", "explorer=custom-model", provider="claude", ok=False)
        self.install("--role-model", "explorer=custom-model", "--role-effort", "explorer=omit", provider="claude")
        self.install("--role-model", "reviewer=123", provider="claude")
        self.assertIn('model: "123"', self.agent("claude").read_text())

    def test_invalid_data_is_rejected_without_writes(self):
        invalid = ["[other.reviewer]\nmodel = foo\n", "[codex.unknown]\nmodel = foo\n",
                   "[codex.reviewer]\nbad = foo\n", "model = foo\n",
                   "[codex.reviewer]\nmodel = foo\nmodel = bar\n",
                   "[codex.reviewer]\n[codex.reviewer]\n", "[codex.reviewer]\neffort = omit\n",
                   "[codex.reviewer]\nmodel = $(touch unsafe)\n",
                   "[codex.reviewer]\nmodel = `touch unsafe`\n",
                   "[claude.reviewer]\neffort = nonsense\n", "[codex.reviewer]\nmodel = inherit\n"]
        for text in invalid:
            with self.subTest(text=text):
                self.config(text)
                before = files(self.target)
                self.install("--use-models-config", ok=False)
                self.assertEqual(files(self.target), before)
        self.assertFalse((self.base / "unsafe").exists())
        for args in [("--role-model", "reviewer=a", "--role-model", "reviewer=b"),
                     ("--role-effort", "unknown=high"), ("--reset-role", "unknown"),
                     ("--role-model", "reviewer="), ("--role-model", "reviewer"),
                     ("--role-model", "reviewer=a\nsecurity\tmodel\tb")]:
            before = files(self.target)
            self.install("--ignore-models-config", *args, ok=False)
            self.assertEqual(files(self.target), before)

    def test_dry_run_conflicts_and_uninstall_preserve_input(self):
        config = self.config("[codex.reviewer]\nmodel = chosen-model\n")
        before = files(self.target)
        self.install("--use-models-config", "--dry-run")
        self.assertEqual(files(self.target), before)
        self.install("--use-models-config")
        agent = self.agent()
        data = tomllib.loads(agent.read_text())
        source = tomllib.loads((self.rig / "providers/codex/agents/reviewer.toml").read_text())
        self.assertEqual(data["developer_instructions"], source["developer_instructions"])
        agent.write_text(agent.read_text() + "# manual edit\n")
        before = files(self.target)
        self.install("--ignore-models-config", "--role-model", "reviewer=another-model", operation="update", ok=False)
        self.assertEqual(files(self.target), before)
        self.install("--ignore-models-config", "--role-model", "reviewer=another-model",
                     "--replace-modified", operation="update")
        self.run_rig("uninstall", "--target", self.target)
        self.assertTrue(config.exists())
        self.assertFalse((self.target / ".agent-rig/codex/models/overrides.ini").exists())

    def test_global_discovery_and_saved_overrides(self):
        for provider in ("codex", "claude"):
            with self.subTest(provider=provider):
                home = self.base / f"{provider}-home"
                self.config(f"[{provider}.reviewer]\nmodel = global-choice\n", home / ".agent-rig/models.ini")
                args = ["--global", "--provider", provider, "--yes"]
                self.run_rig("install", *args, "--use-models-config")
                self.assertIn("global-choice", (home / f".agent-rig/{provider}/models/overrides.ini").read_text())
                if provider == "codex":
                    for role in ROLES:
                        self.assert_effort_variants(home / f"agents/agent_rig_{role}.toml")
                self.run_rig("update", *args, "--ignore-models-config")
                self.run_rig("uninstall", "--global", "--provider", provider)
                self.assertTrue((home / ".agent-rig/models.ini").exists())
                if provider == "codex":
                    self.assertEqual(list((home / "agents").glob("agent_rig_*.toml")), [])

    def test_symlink_config_destination_rejected(self):
        outside = self.base / "outside"
        outside.mkdir()
        (self.target / ".agent-rig").symlink_to(outside, target_is_directory=True)
        self.run_rig("config", "init", "--target", self.target, ok=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_failed_update_rolls_back_saved_choices_and_agents(self):
        self.install("--role-model", "reviewer=before")
        before = files(self.target)
        failing_bin = self.base / "failing-bin"
        failing_bin.mkdir()
        wrapper = failing_bin / "mv"
        wrapper.write_text('''#!/usr/bin/env bash
last=''
for arg in "$@"; do last=$arg; done
if [ "$last" = "$MODEL_FAIL_DEST" ] && [ ! -e "$MODEL_FAIL_ONCE" ]; then
    touch "$MODEL_FAIL_ONCE"
    exit 1
fi
exec "$MODEL_REAL_MV" "$@"
''')
        wrapper.chmod(0o755)
        env = dict(self.env, PATH=f"{failing_bin}:{self.env['PATH']}",
                   MODEL_REAL_MV=shutil.which("mv"), MODEL_FAIL_DEST=str(self.target / "AGENTS.md"),
                   MODEL_FAIL_ONCE=str(self.base / "failed-once"))
        # Change the workflow too so the instruction block is actually written.
        self.install("--role-model", "reviewer=after", "--preset", "minimal",
                     operation="update", env=env, ok=False)
        self.assertTrue((self.base / "failed-once").exists())
        after = {name: content for name, content in files(self.target).items()
                 if ".agent-rig/codex/backups/" not in name}
        self.assertEqual(before, after)
        self.assertFalse((self.target / ".agent-rig/codex/.install-lock").exists())
        self.install(operation="update")
        self.assertIn('model = "before"', self.agent().read_text())
        for role in ROLES:
            self.assert_effort_variants(self.agent(role=role))


if __name__ == "__main__":
    unittest.main()
