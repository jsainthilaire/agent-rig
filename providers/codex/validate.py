"""Validate native Codex TOML assets."""
import re
import tomllib

EFFORTS = {"low", "medium", "high", "xhigh", "max"}


def validate(root, require):
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
    require(tomllib.loads((root / "templates/config.toml").read_text(encoding="utf-8")) == {}, "Config template must preserve inherited settings")
    return agents

