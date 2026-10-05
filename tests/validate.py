#!/usr/bin/env python3
"""Validate Agent Rig source definitions and local Markdown links (Python 3.11+)."""

import argparse
from pathlib import Path
import re
import sys
import tomllib
from urllib.parse import unquote, urlsplit


EFFORTS = {"low", "medium", "high", "xhigh", "max"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def headings_and_links(path: Path) -> tuple[set[str], list[str]]:
    """Ignore code examples when checking headings and Markdown links."""
    anchors: set[str] = set()
    links: list[str] = []
    fence = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        marker = re.match(r"^\s*(`{3,}|~{3,})(.*)$", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = ""
            continue
        if marker:
            fence = marker[1]
            continue
        heading = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
        if heading:
            anchor = re.sub(r"[^\w -]", "", heading[1].lower()).replace(" ", "-")
            unique = anchor
            suffix = 0
            while unique in anchors:
                suffix += 1
                unique = f"{anchor}-{suffix}"
            anchors.add(unique)
        links.extend(re.findall(r"\[[^\]]+\]\(([^\s)]+)\)", line))
    require(not fence, f"{path}: unclosed Markdown fence")
    return anchors, links


def validate(root: Path) -> None:
    agents = {}
    for path in sorted((root / "agents").glob("*.toml")):
        config = tomllib.loads(path.read_text(encoding="utf-8"))
        require(re.fullmatch(r"[a-z_]+", path.stem), f"{path}: invalid logical role name")
        require(config.get("name") == f"agent_rig_{path.stem}", f"{path}: name must match its namespaced filename")
        for field in ("description", "developer_instructions"):
            require(isinstance(config.get(field), str) and config[field].strip(), f"{path}: {field} must be nonempty")
        require(("model" in config) == ("model_reasoning_effort" in config), f"{path}: specify model and effort together, or inherit both")
        if "model" in config:
            require(isinstance(config["model"], str) and config["model"].strip(), f"{path}: model must be nonempty")
            require(isinstance(config["model_reasoning_effort"], str) and config["model_reasoning_effort"] in EFFORTS, f"{path}: unsupported reasoning effort")
        agents[path.stem] = config
    require(agents, "No agent definitions found")

    workflows = {path.stem for path in (root / "workflows").glob("*.md")}
    require(workflows, "No workflow definitions found")
    require(all(re.fullmatch(r"[a-z_]+", name) for name in workflows), "Invalid workflow filename")
    presets = {}
    for path in sorted((root / "presets").glob("*.preset")):
        fields = {}
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line or line.startswith("#"):
                continue
            field, separator, value = line.partition(": ")
            require(separator and field in {"agents", "workflows"} and field not in fields, f"{path}:{number}: invalid or duplicate preset field")
            names = value.split()
            require(names and len(names) == len(set(names)), f"{path}:{number}: empty or duplicate membership")
            definitions = agents if field == "agents" else workflows
            require(all(name in definitions for name in names), f"{path}:{number}: references an undefined {field} entry")
            fields[field] = set(names)
        require(set(fields) == {"agents", "workflows"}, f"{path}: missing required preset field")
        presets[path.stem] = fields
    require(set(presets) == {"minimal", "backend", "security", "full"}, "Expected all four standard presets")
    require(presets["full"]["agents"] == set(agents), "Full preset must include every source role")
    require(presets["full"]["workflows"] == workflows, "Full preset must include every source workflow")
    require(tomllib.loads((root / "templates/config.toml").read_text(encoding="utf-8")) == {}, "Config template must preserve inherited settings")

    documents = [root / "README.md", *sorted((root / "workflows").glob("*.md")), *sorted((root / "templates").glob("*.md"))]
    link_count = 0
    for path in documents:
        anchors, links = headings_and_links(path)
        for link in links:
            parts = urlsplit(link)
            if parts.scheme or parts.netloc:
                continue
            destination = path.parent / unquote(parts.path) if parts.path else path
            require(destination.exists(), f"{path}: missing local link target {link}")
            if parts.fragment:
                target_anchors = anchors if destination == path else headings_and_links(destination)[0]
                require(unquote(parts.fragment) in target_anchors, f"{path}: missing heading target {link}")
            link_count += 1

    sources = [root / "README.md", root / "Makefile", root / ".gitignore", root / ".gitattributes"]
    for directory in ("agents", "workflows", "presets", "templates", "bin", "tests"):
        sources.extend(path for path in (root / directory).iterdir() if path.is_file())
    for path in sources:
        content = path.read_bytes()
        require(content.endswith(b"\n"), f"{path}: missing final newline")
        require(b"\r" not in content, f"{path}: source files must use LF line endings")
        require(all(line.rstrip() == line for line in content.splitlines()), f"{path}: trailing whitespace")
    print(f"Source checks passed: {len(agents)} agents, {len(workflows)} workflows, {len(presets)} presets, {link_count} local links, TOML and source formatting.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        validate(args.root.resolve())
    except (OSError, ValueError, TypeError) as error:
        print(f"Source validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
