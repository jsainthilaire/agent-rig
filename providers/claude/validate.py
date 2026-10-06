"""Validate the intentionally small scalar YAML subset used by Claude assets.

No general YAML parser dependency is needed for these native frontmatter files.
Extend this provider validator when adopting additional native fields or syntax.
"""
import re
import runpy


def validate(root, require):
    policy_module = runpy.run_path(str(root / "models/policy.py"))
    policy = policy_module["load"](root / "models")
    agents = {}
    for path in sorted((root / "agents").glob("*.md")):
        require(path.stem in policy["roles"], f"{path}: undefined policy role")
        source = path.read_text(encoding="utf-8")
        require(source.count("model: __AGENT_RIG_MODEL__") == 1 and source.count("effort: __AGENT_RIG_EFFORT__") == 1, f"{path}: models must consume the centralized policy")
        lines = policy_module["render"](root / "models", path.stem, path).splitlines()
        require(lines and lines[0] == "---", f"{path}: missing frontmatter")
        require("---" in lines[1:], f"{path}: unclosed frontmatter")
        end = lines.index("---", 1)
        config = {}
        for line in lines[1:end]:
            match = re.fullmatch(r"([a-zA-Z]+): ([^\n]+)", line)
            require(match is not None, f"{path}: expected scalar YAML frontmatter")
            key, value = match.groups()
            require(key not in config, f"{path}: duplicate field {key}")
            # Plain scalars only; reject YAML collections, tags, comments, aliases,
            # implicit non-string values, and mapping separators.
            require(value[0] not in "[{&*!|>'\"%@`" and ": " not in value and " #" not in value, f"{path}: unsupported scalar syntax")
            require(value.lower() not in {"true", "false", "null", "~"}, f"{path}: expected string")
            config[key] = value
        tier = policy["tiers"][policy["roles"][path.stem]["tier"]]
        fields = {"name", "description", "tools", "model"}
        if tier["effort"]:
            fields.add("effort")
        require(set(config) == fields, f"{path}: unexpected or missing native fields")
        require(config["name"] == f"agent-rig-{path.stem}", f"{path}: incorrect namespaced name")
        require(config["model"] == tier["model"], f"{path}: model must match provider policy")
        require(config.get("effort") == tier["effort"], f"{path}: effort must match model capability and policy")
        tools = {tool.strip() for tool in config["tools"].split(",")}
        require(tools <= {"Read", "Grep", "Glob", "Edit", "Write", "Bash"}, f"{path}: unknown tool")
        if path.stem in {"explorer", "database", "reviewer", "security"}:
            require(tools == {"Read", "Grep", "Glob"}, f"{path}: role must remain read-only")
        body = "\n".join(lines[end + 1:])
        require(body.strip() and "explicitly activated Agent Rig request" in body, f"{path}: missing activation gate")
        require("Do not spawn subagents or Agent Teams" in body, f"{path}: missing delegation boundary")
        agents[path.stem] = config
    template = (root / "templates/CLAUDE.md").read_text()
    require("@AGENTS.md" not in template and "agent_rig_" not in template, "Claude must own independent instructions")
    return agents
