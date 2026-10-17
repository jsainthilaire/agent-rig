#!/usr/bin/env python3
"""Exercise external review contracts with fake CLIs and disposable installs."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROVIDERS = ("codex", "claude")
FAKE_CLI = r'''
import json
import os
from pathlib import Path
import sys

provider = Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ.get("REVIEW_MODE", "success")
call = {"provider": provider, "args": args, "cwd": os.getcwd()}
with Path(os.environ["REVIEW_CALLS"]).open("a") as calls:
    calls.write(json.dumps(call) + "\n")
if provider == "codex" and "mcp" in args and "list" in args:
    final_probe = "-c" in args
    if mode == "mcp-error" or (mode == "mcp-final-error" and final_probe):
        print("cannot inspect MCP configuration", file=sys.stderr)
        sys.exit(19)
    if mode == "mcp-invalid-json" or (mode == "mcp-final-invalid-json" and final_probe):
        print("not JSON")
        sys.exit(0)
    if mode == "mcp-invalid-shape":
        print('{"servers": []}')
        sys.exit(0)
    servers = []
    if mode in ("mcp-two", "mcp-still-enabled", "mcp-invalid-name", "mcp-invalid-enabled",
                "mcp-final-invalid-enabled"):
        names = ["writer", "read-only_2"]
        if mode == "mcp-invalid-name":
            names[0] = "unsafe.server"
        for name in names:
            disabled = f"mcp_servers.{name}.enabled=false" in args
            enabled = not disabled or mode == "mcp-still-enabled"
            if mode == "mcp-invalid-enabled" or (mode == "mcp-final-invalid-enabled" and final_probe):
                enabled = "false"
            servers.append({"name": name, "enabled": enabled})
    print(json.dumps(servers))
    sys.exit(0)
prompt = sys.stdin.read()
Path(os.environ["REVIEW_CAPTURE"]).write_text(json.dumps({
    "provider": provider, "args": args, "cwd": os.getcwd(), "prompt": prompt,
    "CLAUDECODE": os.environ.get("CLAUDECODE"),
    "CODEX_HOME": os.environ.get("CODEX_HOME"),
    "CLAUDE_CONFIG_DIR": os.environ.get("CLAUDE_CONFIG_DIR"),
}))
if mode == "error":
    print("authentication or nested-session failure", file=sys.stderr)
    print("partial output is not a completed review")
    sys.exit(23)
response = {"empty": "", "whitespace": " \n\t"}.get(mode, "No actionable findings.\n")
if provider == "codex":
    if mode != "missing-final":
        Path(args[args.index("--output-last-message") + 1]).write_text(response)
    print("execution events must not be returned as the review")
else:
    sys.stdout.write(response)
'''


def tree(destination):
    return {str(path.relative_to(destination)): path.read_bytes()
            for path in destination.rglob("*") if path.is_file()}


class ReviewRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agent-rig-review-tests.")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.target = self.base / "project spaces ' $literal `literal` ;"
        self.target.mkdir()
        self.capture = self.base / "capture.json"
        self.calls = self.base / "calls.jsonl"
        self.cli_directory = self.base / "bin"
        self.cli_directory.mkdir()
        # An isolated PATH guarantees these tests never reach a real model CLI.
        for command in ("mktemp", "cat", "grep", "rm"):
            (self.cli_directory / command).symlink_to(shutil.which(command))
        (self.cli_directory / "python3").symlink_to(sys.executable)
        for provider in PROVIDERS:
            path = self.cli_directory / provider
            path.write_text(f"#!{sys.executable}\n" + FAKE_CLI)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.cli_directory),
                        REVIEW_CAPTURE=str(self.capture), REVIEW_CALLS=str(self.calls),
                        CLAUDECODE="preserve-nested-guard",
                        HOME=str(self.base), CODEX_HOME=str(self.base / "codex config"),
                        CLAUDE_CONFIG_DIR=str(self.base / "claude config"), TMPDIR=str(self.base))
        for provider in PROVIDERS:
            directory = Path(self.env["CODEX_HOME" if provider == "codex" else "CLAUDE_CONFIG_DIR"])
            directory.mkdir()
            (directory / "user-config").write_text("Keep configured model and authentication.\n")

    def run_review(self, provider, brief="Review the current changes.\n", args=None, mode="success"):
        self.capture.unlink(missing_ok=True)
        self.calls.unlink(missing_ok=True)
        env = dict(self.env, REVIEW_MODE=mode)
        return subprocess.run(["/bin/bash", str(ROOT / f"providers/{provider}/review.sh"),
                               *(args if args is not None else ["--target", str(self.target)])],
                              input=brief, capture_output=True, text=True,
                              cwd=self.base, env=env, timeout=15)

    def test_literal_brief_target_environment_and_final_response(self):
        brief = "Review commit abc123.\n$(touch injected) `touch injected` ' \" ;\n"
        before = tree(self.target)
        for provider in PROVIDERS:
            with self.subTest(provider=provider):
                result = self.run_review(provider, brief, ["--target", self.target.name])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "No actionable findings.\n")
                captured = json.loads(self.capture.read_text())
                self.assertEqual(captured["provider"], provider)
                self.assertEqual(captured["cwd"], str(self.target))
                self.assertTrue(captured["prompt"].endswith(brief))
                self.assertIn("assessment-only", captured["prompt"])
                for variable in ("CLAUDECODE", "CODEX_HOME", "CLAUDE_CONFIG_DIR"):
                    self.assertEqual(captured[variable], self.env[variable])
                self.assertFalse((self.base / "injected").exists())
                self.assertEqual(tree(self.target), before)
                self.assertFalse(list(self.base.glob("agent-rig-*-review.*")))
                for config in ("codex config", "claude config"):
                    self.assertEqual((self.base / config / "user-config").read_text(),
                                     "Keep configured model and authentication.\n")

    def test_read_only_cli_contracts(self):
        for provider in PROVIDERS:
            with self.subTest(provider=provider):
                result = self.run_review(provider)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads(self.capture.read_text())["args"]
                self.assertNotIn("--model", args)
                self.assertNotIn("--dangerously-skip-permissions", args)
                self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", args)
                if provider == "codex":
                    self.assertIn("exec", args)
                    self.assertEqual(args[args.index("--sandbox") + 1], "read-only")
                    self.assertIn("--ephemeral", args)
                    self.assertIn("--output-last-message", args)
                    self.assertEqual(args[-1], "-")
                    overrides = [args[index + 1] for index, arg in enumerate(args) if arg == "-c"]
                    self.assertIn("approval_policy=never", overrides)
                    disabled = [args[index + 1] for index, arg in enumerate(args)
                                if arg == "--disable"]
                    for feature in ("apps", "plugins", "multi_agent", "browser_use",
                                    "browser_use_external", "computer_use"):
                        self.assertIn(feature, disabled)
                else:
                    self.assertIn("--print", args)
                    self.assertEqual(args[args.index("--output-format") + 1], "text")
                    self.assertEqual(set(args[args.index("--tools") + 1].split(",")),
                                     {"Read", "Grep", "Glob"})
                    self.assertEqual(set(args[args.index("--allowedTools") + 1].split(",")),
                                     {"Read", "Grep", "Glob"})
                    self.assertEqual(args[args.index("--permission-mode") + 1], "dontAsk")
                    self.assertIn("--strict-mcp-config", args)
                    self.assertEqual(json.loads(args[args.index("--mcp-config") + 1]),
                                     {"mcpServers": {}})
                    self.assertIn("--no-session-persistence", args)
                    self.assertIn("--disable-slash-commands", args)

    def test_invalid_inputs_do_not_invoke_a_cli(self):
        for provider in PROVIDERS:
            for args in ([], ["--unknown"], ["--target"], ["--target", ""],
                         ["--target", str(self.base / "absent")],
                         ["--target", str(self.target), "--target", str(self.target)],
                         ["--help", "extra"]):
                with self.subTest(provider=provider, args=args):
                    result = self.run_review(provider, args=args)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue(result.stderr)
                    self.assertFalse(self.capture.exists())
            for brief in ("", " \n\t"):
                with self.subTest(provider=provider, brief=brief):
                    result = self.run_review(provider, brief)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(self.capture.exists())
            result = self.run_review(provider, args=["--help"])
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--target", result.stdout)
            self.assertFalse(self.capture.exists())

    def test_unavailable_cli_fails_without_fallback(self):
        for provider in PROVIDERS:
            with self.subTest(provider=provider):
                path = self.cli_directory / provider
                saved = path.read_bytes()
                path.unlink()
                try:
                    result = self.run_review(provider)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("unavailable", result.stderr)
                    self.assertFalse(self.capture.exists())
                finally:
                    path.write_bytes(saved)
                    path.chmod(0o755)

    def test_failure_and_incomplete_output_are_not_successful_reviews(self):
        for provider in PROVIDERS:
            modes = ("error", "empty", "whitespace")
            if provider == "codex":
                modes += ("missing-final",)
            for mode in modes:
                with self.subTest(provider=provider, mode=mode):
                    result = self.run_review(provider, mode=mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertTrue(result.stderr)
                    self.assertEqual(json.loads(self.capture.read_text())["provider"], provider)
                    if mode == "error":
                        self.assertEqual(result.returncode, 23)
                        self.assertIn("authentication or nested-session failure", result.stderr)
                    self.assertFalse(list(self.base.glob("agent-rig-*-review.*")))

    def test_codex_disables_inherited_mcp_servers_before_review(self):
        result = self.run_review("codex", mode="mcp-two")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(len(calls), 3)
        for call in calls:
            self.assertEqual(call["provider"], "codex")
            self.assertEqual(call["cwd"], str(self.target))
        for call in calls[:2]:
            self.assertIn("mcp", call["args"])
            self.assertIn("list", call["args"])
            self.assertIn("--json", call["args"])
        self.assertIn("exec", calls[-1]["args"])
        for call in calls[1:]:
            overrides = [call["args"][index + 1] for index, arg in enumerate(call["args"])
                         if arg == "-c"]
            self.assertIn("mcp_servers.writer.enabled=false", overrides)
            self.assertIn("mcp_servers.read-only_2.enabled=false", overrides)
        # The verification probe must exercise the same restrictions as exec.
        for flag in ("-c", "--disable"):
            values = [[call["args"][index + 1] for index, arg in enumerate(call["args"])
                       if arg == flag] for call in calls[1:]]
            self.assertEqual(values[0], values[1])
        self.assertEqual(result.stdout, "No actionable findings.\n")

    def test_codex_mcp_preflight_fails_closed(self):
        for mode in ("mcp-error", "mcp-invalid-json", "mcp-invalid-shape", "mcp-invalid-name",
                     "mcp-invalid-enabled", "mcp-still-enabled", "mcp-final-error",
                     "mcp-final-invalid-json", "mcp-final-invalid-enabled"):
            with self.subTest(mode=mode):
                result = self.run_review("codex", mode=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertTrue(result.stderr)
                self.assertFalse(self.capture.exists(), "An unsafe preflight invoked a model")
                calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
                self.assertTrue(calls)
                self.assertTrue(all("mcp" in call["args"] for call in calls))
                self.assertFalse(list(self.base.glob("agent-rig-*-review.*")))

    def test_codex_requires_python_for_safe_config_inspection(self):
        (self.cli_directory / "python3").unlink()
        result = self.run_review("codex")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("python3", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.capture.exists())
        self.assertFalse(self.calls.exists())
        # Claude's separate tool restriction does not require Python at runtime.
        result = self.run_review("claude")
        self.assertEqual(result.returncode, 0, result.stderr)


class ReviewerInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="agent-rig-review-install.")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def lifecycle(self, destination, provider, scope="project", operation="install", *options):
        args = ["bash", str(ROOT / "bin/agent-rig"), operation, "--provider", provider]
        env = dict(os.environ)
        if scope == "global":
            args.append("--global")
            env["CODEX_HOME" if provider == "codex" else "CLAUDE_CONFIG_DIR"] = str(destination)
        else:
            args += ["--target", str(destination)]
        if operation != "uninstall":
            args += ["--yes", "--preset", "minimal"]
        return subprocess.run(args + list(options), env=env, input="", capture_output=True,
                              text=True, timeout=30)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_install_guidance_idempotency_and_legacy_update(self):
        for provider in PROVIDERS:
            other = "claude" if provider == "codex" else "codex"
            for scope in ("project", "global"):
                with self.subTest(provider=provider, scope=scope):
                    destination = self.base / f"{provider} {scope}"
                    if scope == "project":
                        destination.mkdir()
                    self.assert_success(self.lifecycle(destination, provider, scope))
                    relative = f".agent-rig/{provider}/reviewers/{other}.sh"
                    runner = destination / relative
                    self.assertEqual(runner.read_bytes(),
                                     (ROOT / f"providers/{other}/review.sh").read_bytes())
                    self.assertEqual(list(runner.parent.iterdir()), [runner])
                    instructions = (destination / ("AGENTS.md" if provider == "codex"
                                                   else "CLAUDE.md")).read_text()
                    self.assertIn("reviewer=claude", instructions)
                    self.assertIn("reviewer=codex", instructions)
                    guidance = str(runner) if scope == "global" else relative
                    self.assertIn(f"`{guidance}`", instructions)
                    manifest = destination / f".agent-rig/{provider}/manifest.tsv"
                    record = f"file\t{relative}\t"
                    self.assertIn(record, manifest.read_text())
                    before = tree(destination)
                    result = self.lifecycle(destination, provider, scope)
                    self.assert_success(result)
                    self.assertIn("Already up to date.", result.stdout)
                    self.assertEqual(tree(destination), before)
                    # A prior installation has no runner record. Updating adds it.
                    manifest.write_text("".join(line for line in manifest.read_text().splitlines(True)
                                                if not line.startswith(record)))
                    runner.unlink()
                    self.assert_success(self.lifecycle(destination, provider, scope, "update"))
                    self.assertEqual(runner.read_bytes(),
                                     (ROOT / f"providers/{other}/review.sh").read_bytes())
                    self.assertIn(record, manifest.read_text())
                    self.assert_success(self.lifecycle(destination, provider, scope, "uninstall"))
                    self.assertFalse(runner.exists())
                    self.assertFalse(manifest.exists())

    def test_local_edits_backups_and_provider_isolation(self):
        destination = self.base / "shared project"
        destination.mkdir()
        for provider in PROVIDERS:
            self.assert_success(self.lifecycle(destination, provider))
        for provider in PROVIDERS:
            other = "claude" if provider == "codex" else "codex"
            runner = destination / f".agent-rig/{provider}/reviewers/{other}.sh"
            original = runner.read_bytes()
            modified = original + b"\n# Keep local review policy.\n"
            runner.write_bytes(modified)
            before = tree(destination)
            rejected = self.lifecycle(destination, provider, "project", "update")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("locally modified", rejected.stdout + rejected.stderr)
            self.assertEqual(tree(destination), before)
            self.assert_success(self.lifecycle(destination, provider, "project", "update",
                                               "--replace-modified"))
            self.assertEqual(runner.read_bytes(), original)
            backups = destination / f".agent-rig/{provider}/backups"
            self.assertTrue(any(path.read_bytes() == modified
                                for path in backups.rglob(f"{other}.sh")))
        for provider in PROVIDERS:
            other = "claude" if provider == "codex" else "codex"
            other_state = destination / f".agent-rig/{other}"
            other_native = destination / f".{other}"
            before_state, before_native = tree(other_state), tree(other_native)
            other_instructions = destination / ("AGENTS.md" if other == "codex" else "CLAUDE.md")
            before_instructions = other_instructions.read_bytes() if other_instructions.exists() else None
            self.assert_success(self.lifecycle(destination, provider, "project", "uninstall"))
            self.assertEqual(tree(other_state), before_state)
            self.assertEqual(tree(other_native), before_native)
            if before_instructions is not None:
                self.assertEqual(other_instructions.read_bytes(), before_instructions)
            self.assertFalse((destination / f".agent-rig/{provider}/reviewers/{other}.sh").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
