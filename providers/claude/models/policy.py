"""Provider-local policy loader for source validation and offline evaluation."""
from pathlib import Path
import subprocess


def load(directory: Path):
    result = subprocess.run(
        ["awk", "-f", str(directory / "policy.awk"), str(directory / "policy.tsv")],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Invalid Claude model policy")
    policy = {"tiers": {}, "roles": {}}
    for line in result.stdout.splitlines():
        values = line.split("\t")
        if values[0] == "tier":
            _, tier, model, effort, *metadata = values
            policy["tiers"][tier] = {
                "model": model, "effort": None if effort == "-" else effort,
                "input_usd": float(metadata[0]), "output_usd": float(metadata[1]),
                "cache_write_5m_usd": float(metadata[2]), "cache_write_1h_usd": float(metadata[3]),
                "cache_read_usd": float(metadata[4]), "context_tokens": int(metadata[5]),
                "knowledge_cutoff": metadata[6], "latency": metadata[7],
            }
        elif values[0] == "role":
            _, role, tier, next_tier, threshold = values
            policy["roles"][role] = {"tier": tier, "next_tier": next_tier, "threshold": float(threshold)}
        else:
            policy[values[0]] = values[1]
    return policy


def render(directory: Path, role: str, template: Path) -> str:
    """Use the same validated renderer as the Bash installer."""
    policy = subprocess.run(
        ["awk", "-f", str(directory / "policy.awk"), str(directory / "policy.tsv")],
        capture_output=True, text=True, check=True,
    ).stdout
    result = subprocess.run(
        ["awk", "-v", f"role={role}", "-f", str(directory / "render.awk"), "-", str(template)],
        input=policy, capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Claude agent rendering failed")
    return result.stdout
