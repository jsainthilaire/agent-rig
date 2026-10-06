# Trusted Claude Code adapter. No Codex configuration or instructions are read.
provider_label='Claude Code'
legacy_manifest_candidate=''
legacy_lock_path=''
agent_extension=md
agent_prefix=agent-rig-
instructions_template=CLAUDE.md
instructions_file=CLAUDE.md
instruction_candidates=CLAUDE.md

provider_prepare_install() {
    awk -f "$PROVIDER_ROOT/models/policy.awk" "$PROVIDER_ROOT/models/policy.tsv" > "$stage/claude-model-policy.tsv" || die 'Invalid Claude model policy'
}

provider_render_file() {
    local source=$1 destination=$2 role
    case $source in
        "$PROVIDER_ROOT"/agents/*.md)
            role=$(basename -- "$source" .md)
            awk -v role="$role" -f "$PROVIDER_ROOT/models/render.awk" "$stage/claude-model-policy.tsv" "$source" > "$destination" ;;
        *) cp "$source" "$destination" ;;
    esac
}

provider_extra_files() {
    prepare_managed_file "$stage/claude-model-policy.tsv" "$state_directory/models/policy.tsv"
}

provider_render_instructions() {
    cat "$PROVIDER_ROOT/templates/$instructions_template"
    printf '\n### Installed Claude model tiers\n\n| Tier | Pinned model | Default effort |\n| --- | --- | --- |\n'
    awk -F '\t' '$1 == "tier" { printf "| %s | `%s` | %s |\n", $2, $3, ($4 == "-" ? "not supported" : $4) }' "$stage/claude-model-policy.tsv"
    printf '\n| Role | Default tier | Next tier |\n| --- | --- | --- |\n'
    awk -F '\t' '$1 == "role" { printf "| %s | %s | %s |\n", $2, $3, $4 }' "$stage/claude-model-policy.tsv"
    if [ "$global_install" -eq 1 ]; then
        printf '\nInstalled policy: `%s/%s/models/policy.tsv`.\n' "$target" "$state_directory"
    else
        printf '\nInstalled policy: `%s/models/policy.tsv`, relative to this section.\n' "$state_directory"
    fi
}

provider_global_target() {
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then target=$CLAUDE_CONFIG_DIR
    else
        [ -n "${HOME:-}" ] || die 'HOME is required when CLAUDE_CONFIG_DIR is not set'
        target=$HOME/.claude
    fi
}

provider_paths() {
    if [ "$install_scope" = global ]; then agent_directory=agents
    else agent_directory=.claude/agents; fi
}

provider_manifest_patterns() {
    if [ "$install_scope" = global ]; then
        manifest_files='^agents/agent-rig-[a-z_]+[.]md$'
    else
        manifest_files='^[.]claude/agents/agent-rig-[a-z_]+[.]md$'
    fi
    manifest_files="$manifest_files|^[.]agent-rig/claude/workflows/[a-z_]+[.]md$"
    manifest_files="$manifest_files|^[.]agent-rig/claude/models/policy[.]tsv$"
    manifest_blocks='^CLAUDE[.]md$'
}

provider_choose_instructions() { snapshot CLAUDE.md; }
# Leave settings, permissions, hooks, and memory entirely under user control.
provider_prepare_config() { :; }

provider_report() {
    printf 'Claude Code settings, instructions outside Rig sections, and backup history are preserved.\n'
    printf 'Start a new Claude Code session to load the subagents. Rig activates only through leading workflow aliases.\n'
}
