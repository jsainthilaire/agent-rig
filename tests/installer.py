#!/usr/bin/env python3
"""Exercise confirmation and terminal presentation in disposable destinations."""

import os
from pathlib import Path
import pty
import re
import select
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "bin/agent-rig"
PROMPT = b"Continue with installation? [y/N]"


def command(destination, provider="codex", scope="project", *options):
    args = ["bash", str(INSTALLER), "install", "--provider", provider, "--preset", "minimal"]
    env = dict(os.environ, TERM="xterm-256color")
    env.pop("NO_COLOR", None)
    if scope == "global":
        args.append("--global")
        env["CODEX_HOME" if provider == "codex" else "CLAUDE_CONFIG_DIR"] = str(destination)
    else:
        args.extend(["--target", str(destination)])
    return args + list(options), env


def run(destination, provider="codex", scope="project", *options, answer=""):
    args, env = command(destination, provider, scope, *options)
    return subprocess.run(args, env=env, input=answer, capture_output=True, text=True, timeout=15)


def files(destination):
    return {str(path.relative_to(destination)): path.read_bytes()
            for path in destination.rglob("*") if path.is_file()}


def unchanged(destination, before):
    assert files(destination) == before, "Cancellation changed destination files"
    assert not (destination / ".agent-rig").exists(), "Cancellation created state directories"


def terminal(destination, *, no_color=False, term="xterm-256color", answer="yes\n"):
    args, env = command(destination)
    env["TERM"] = term
    if no_color:
        env["NO_COLOR"] = ""  # Presence, even when empty, disables colors.
    master, slave = pty.openpty()
    process = subprocess.Popen(args, env=env, stdin=subprocess.PIPE, stdout=slave, stderr=slave)
    os.close(slave)
    output = b""
    sent = False
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break  # PTYs report EIO when the child closes its side.
                if not chunk:
                    break
                output += chunk
            if PROMPT in output and not sent:
                assert not list(destination.iterdir()), "Installer wrote before confirmation"
                process.stdin.write(answer.encode())
                process.stdin.flush()
                process.stdin.close()
                sent = True
        assert sent, output.decode()
        assert process.wait(timeout=2) == 0, output.decode()
        return output
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)


def main():
    with tempfile.TemporaryDirectory(prefix="agent-rig-ui-tests.") as temp:
        base = Path(temp)
        for provider in ("codex", "claude"):
            for scope in ("project", "global"):
                destination = base / f"{provider}-{scope}"
                if scope == "project":
                    destination.mkdir()
                for answer in ("no\n", "\n", "invalid\nn\n"):
                    result = run(destination, provider, scope, answer=answer)
                    assert result.returncode == 0, result.stderr
                    assert "Installation cancelled" in result.stdout
                    assert PROMPT.decode() in result.stdout
                    assert "Scope:  " + scope in result.stdout
                    assert str(destination) in result.stdout
                    assert "minimal (4 agents, 3 workflows)" in result.stdout
                    assert not files(destination)
                    assert not (destination / ".agent-rig").exists()
                    if scope == "global":
                        assert not destination.exists(), "Cancellation created a global home"

                result = run(destination, provider, scope)
                assert result.returncode != 0, "EOF must stop unattended installation"
                assert "Use --yes" in result.stderr
                result = run(destination, provider, scope, "--dry-run")
                assert result.returncode == 0, result.stderr
                assert "Dry run: no target files changed." in result.stdout
                assert PROMPT.decode() not in result.stdout
                assert not files(destination)
                if scope == "global":
                    assert not destination.exists()

                # Detect the chosen provider's settings even without instructions.
                config_dir = destination if scope == "global" else destination / f".{provider}"
                config_dir.mkdir(parents=True, exist_ok=True)
                config = config_dir / ("config.toml" if provider == "codex" else "settings.json")
                config.write_text('model = "custom"\n' if provider == "codex" else '{"permissions": {"allow": []}}\n')
                before = files(destination)
                result = run(destination, provider, scope, answer="no\n")
                assert f"Existing {'Codex' if provider == 'codex' else 'Claude Code'} configuration detected" in result.stdout
                assert "merge its agents and managed instructions" in result.stdout
                assert str(config.relative_to(destination)) in result.stdout
                unchanged(destination, before)

                instructions = destination / ("AGENTS.md" if provider == "codex" else "CLAUDE.md")
                instructions.write_text("Keep my project instructions without final newline")
                before = files(destination)
                result = run(destination, provider, scope, answer="  YeS  \n")
                assert result.returncode == 0, result.stderr
                assert "Installed successfully." in result.stdout
                assert "100%" in result.stdout
                assert "\033" not in result.stdout and "\r" not in result.stdout
                assert config.read_bytes() == before[str(config.relative_to(destination))]
                assert instructions.read_bytes().startswith(before[instructions.name])
                assert (destination / f".agent-rig/{provider}/manifest.tsv").is_file()

                # No-op installs never prompt or show a progress bar.
                result = run(destination, provider, scope)
                assert result.returncode == 0, result.stderr
                assert "Already up to date." in result.stdout
                assert PROMPT.decode() not in result.stdout and "100%" not in result.stdout

                # A declined preset switch must keep managed content and backups.
                before = files(destination)
                result = run(destination, provider, scope, "--preset", "full", answer="no\n")
                assert result.returncode == 0, result.stderr
                assert files(destination) == before
                result = run(destination, provider, scope, "--preset", "full", "--yes")
                assert result.returncode == 0, result.stderr
                assert PROMPT.decode() not in result.stdout
                assert "Confirmation accepted via --yes." in result.stdout
                assert "100%" in result.stdout
                print(f"PASS: {provider} {scope} confirmation, merging, dry run, and automation")

        for name, no_color, term in (("color", False, "xterm-256color"),
                                      ("no-color", True, "xterm-256color"),
                                      ("dumb", False, "dumb")):
            destination = base / name
            destination.mkdir()
            output = terminal(destination, no_color=no_color, term=term)
            assert (b"\033[" in output) == (name == "color"), output
            percentages = [int(value) for value in re.findall(rb"(\d+)%", output)]
            assert percentages[0] == 0 and percentages[-1] == 100, output
            assert percentages == sorted(set(percentages)), output
            if term != "dumb":
                assert len(percentages) > 2, "Terminal bar did not advance during installation"
            else:
                assert percentages == [0, 100], output
            assert b"Installed successfully." in output
            print(f"PASS: terminal {name} presentation and progress after confirmation")

        destination = base / "terminal-cancel"
        destination.mkdir()
        output = terminal(destination, answer="no\n")
        assert b"Installation cancelled" in output and b"100%" not in output
        assert not list(destination.iterdir())
        destination = base / "short-yes"
        destination.mkdir()
        result = run(destination, "claude", "project", "-y")
        assert result.returncode == 0, result.stderr
        assert PROMPT.decode() not in result.stdout
        print("PASS: terminal cancellation and -y automation")


if __name__ == "__main__":
    main()
