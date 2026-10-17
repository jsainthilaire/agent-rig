# Trusted Claude Code adapter. No Codex configuration or instructions are read.
provider_label='Claude Code'
legacy_manifest_candidate=''
legacy_lock_path=''
agent_extension=md
agent_prefix=agent-rig-
instructions_template=CLAUDE.md
instructions_file=CLAUDE.md
instruction_candidates=CLAUDE.md

provider_model_defaults() {
    awk -f "$PROVIDER_ROOT/models/policy.awk" "$PROVIDER_ROOT/models/policy.tsv" > "$stage/default-policy.tsv" || die 'Invalid Claude model policy'
    awk -F '\t' '
        $1 == "tier" { models[$2] = $3; efforts[$2] = ($4 == "-" ? "omit" : $4) }
        $1 == "role" { printf "%s\t%s\t%s\n", $2, models[$3], efforts[$3] }
    ' "$stage/default-policy.tsv"
}

provider_prepare_install() {
    awk -f "$PROVIDER_ROOT/models/policy.awk" "$PROVIDER_ROOT/models/policy.tsv" > "$stage/claude-model-policy.tsv" || die 'Invalid Claude model policy'
    cp "$stage/claude-model-policy.tsv" "$stage/claude-render-policy.tsv"
    awk -F '\t' '{ print "effective\t" $1 "\t" $2 "\t" ($3 == "omit" ? "-" : $3) }' "$stage/model-effective.tsv" >> "$stage/claude-render-policy.tsv"
}

provider_render_file() {
    local source=$1 destination=$2 role
    case $source in
        "$PROVIDER_ROOT"/agents/*.md)
            role=$(basename -- "$source" .md)
            awk -v role="$role" -f "$PROVIDER_ROOT/models/render.awk" "$stage/claude-render-policy.tsv" "$source" > "$destination" ;;
        *) cp "$source" "$destination" ;;
    esac
}

provider_extra_files() {
    prepare_managed_file "$stage/claude-model-policy.tsv" "$state_directory/models/policy.tsv"
    prepare_managed_file "$RIG_ROOT/providers/codex/review.sh" "$state_directory/reviewers/codex.sh"
}

provider_render_instructions() {
    cat "$PROVIDER_ROOT/templates/$instructions_template"
    if [ "$global_install" -eq 1 ]; then
        printf '\nExternal reviewer runner: `%s/%s/reviewers/codex.sh`.\n' "$target" "$state_directory"
    else
        printf '\nExternal reviewer runner: `%s/reviewers/codex.sh`, relative to this section.\n' "$state_directory"
    fi
    printf '\n### Installed Claude model tiers\n\n| Tier | Pinned model | Default effort |\n| --- | --- | --- |\n'
    awk -F '\t' '$1 == "tier" { printf "| %s | `%s` | %s |\n", $2, $3, ($4 == "-" ? "not supported" : $4) }' "$stage/claude-model-policy.tsv"
    printf '\n| Role | Default tier | Next tier |\n| --- | --- | --- |\n'
    awk -F '\t' '$1 == "role" { printf "| %s | %s | %s |\n", $2, $3, $4 }' "$stage/claude-model-policy.tsv"
    models_instruction_table
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
    if [ "$install_scope" = global ]; then
        agent_directory=agents
        configuration_paths='settings.json settings.local.json'
    else
        agent_directory=.claude/agents
        configuration_paths='.claude/settings.json .claude/settings.local.json'
    fi
}

provider_manifest_patterns() {
    if [ "$install_scope" = global ]; then
        manifest_files='^agents/agent-rig-[a-z_]+[.]md$'
    else
        manifest_files='^[.]claude/agents/agent-rig-[a-z_]+[.]md$'
    fi
    manifest_files="$manifest_files|^[.]agent-rig/claude/workflows/[a-z_]+[.]md$"
    manifest_files="$manifest_files|^[.]agent-rig/claude/models/policy[.]tsv$"
    manifest_files="$manifest_files|^[.]agent-rig/claude/models/overrides[.]ini$"
    manifest_files="$manifest_files|^[.]agent-rig/claude/reviewers/codex[.]sh$"
    manifest_blocks='^CLAUDE[.]md$'
}

provider_choose_instructions() { snapshot CLAUDE.md; }
# Leave settings, permissions, hooks, and memory entirely under user control.
provider_prepare_config() { :; }

provider_report() {
    printf 'Claude Code settings, instructions outside Rig sections, and backup history are preserved.\n'
    printf 'Start a new Claude Code session to load the subagents. Rig activates through leading rig <workflow>: prefixes (recommended) or compatible @ aliases.\n'
}
