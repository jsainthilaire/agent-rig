# Trusted Codex adapter. Native formats and discovery rules belong here.
provider_label=Codex
legacy_manifest_candidate=.agent-rig/manifest.tsv
legacy_lock_path=.agent-rig/.install-lock
agent_extension=toml
agent_prefix=agent_rig_
instructions_template=AGENTS.md
instructions_file=AGENTS.md
instruction_candidates='AGENTS.md AGENTS.override.md'

provider_prepare_install() { :; }
provider_render_file() { cp "$1" "$2"; }
provider_extra_files() { :; }
provider_render_instructions() { cat "$PROVIDER_ROOT/templates/$instructions_template"; }

provider_global_target() {
    if [ -n "${CODEX_HOME:-}" ]; then target=$CODEX_HOME
    else
        [ -n "${HOME:-}" ] || die 'HOME is required when CODEX_HOME is not set'
        target=$HOME/.codex
    fi
}

provider_paths() {
    if [ "$install_scope" = global ]; then
        agent_directory=agents
        config_path=config.toml
    else
        agent_directory=.codex/agents
        config_path=.codex/config.toml
    fi
    configuration_paths=$config_path
}

provider_manifest_patterns() {
    local roles='agent_rig_[a-z_]+|explorer|implementer|database|tester|reviewer|debugger|security'
    if [ "$install_scope" = global ]; then
        manifest_files='^agents/agent_rig_[a-z_]+[.]toml$'
    else
        manifest_files="^[.]codex/agents/($roles)[.]toml$"
    fi
    manifest_files="$manifest_files|^[.]agent-rig/codex/workflows/[a-z_]+[.]md$"
    if [ -n "$legacy_manifest" ]; then
        manifest_files="$manifest_files|^[.]agent-rig/workflows/[a-z_]+[.]md$"
    fi
    manifest_blocks='^AGENTS([.]override)?[.]md$'
}

provider_choose_instructions() {
    snapshot AGENTS.md
    snapshot AGENTS.override.md
    if [ -s "$target/AGENTS.override.md" ] && grep -q '[^[:space:]]' "$target/AGENTS.override.md"; then
        instructions_file=AGENTS.override.md
    fi
}

provider_prepare_config() {
    snapshot "$config_path"
    if [ -f "$target/$config_path" ]; then config_preserved=1
    else
        mkdir -p "$stage/new/$(dirname -- "$config_path")"
        cp "$PROVIDER_ROOT/templates/config.toml" "$stage/new/$config_path"
        plan_write "$config_path"
    fi
}

provider_report() {
    if [ "$operation" = uninstall ]; then
        printf 'Codex configuration, instructions outside Rig sections, and backup history are preserved.\n'
    elif [ "$config_preserved" -eq 1 ]; then
        printf 'Existing %s preserved byte-for-byte.\n' "$config_path"
        printf 'Codex discovers namespaced Rig agents in %s/ automatically.\n' "$agent_directory"
        printf 'If multi-agent tools are disabled, reconcile enabled = true in the existing [agents] table manually.\n'
        printf 'Role models and efforts are independent; see providers/codex/templates/config.toml for guidance.\n'
    fi
    printf 'Use a new Codex session to reload the setup. Rig activates only through leading workflow aliases.\n'
}
