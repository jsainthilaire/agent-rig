# Trusted Codex adapter. Native formats and discovery rules belong here.
provider_label=Codex
legacy_manifest_candidate=.agent-rig/manifest.tsv
legacy_lock_path=.agent-rig/.install-lock
agent_extension=toml
agent_prefix=agent_rig_
instructions_template=AGENTS.md
instructions_file=AGENTS.md
instruction_candidates='AGENTS.md AGENTS.override.md'

provider_model_defaults() {
    local role
    for role in $model_roles; do
        awk -v role="$role" '
            /^model = / { model = $0; sub(/^[^"]*"/, "", model); sub(/".*$/, "", model) }
            /^model_reasoning_effort = / { effort = $0; sub(/^[^"]*"/, "", effort); sub(/".*$/, "", effort) }
            /^developer_instructions = / { exit }
            END {
                if ((model == "") != (effort == "")) exit 1
                printf "%s\t%s\t%s\n", role, (model ? model : "inherit"), (effort ? effort : "inherit")
            }
        ' "$PROVIDER_ROOT/agents/$role.toml" || die "Invalid defaults for $role"
    done
}

provider_prepare_install() { :; }
provider_render_file() {
    case $1 in
        "$PROVIDER_ROOT"/agents/*.toml)
            awk -v role="$(basename -- "$1" .toml)" -f "$PROVIDER_ROOT/models/render.awk" "$stage/model-effective.tsv" "$1" > "$2" ;;
        *) cp "$1" "$2" ;;
    esac
}
provider_extra_files() {
    local role effort effective variant
    mkdir -p "$stage/effort-sources"
    for role in $agents; do
        effective=$stage/effort-sources/$role.toml
        provider_render_file "$PROVIDER_ROOT/agents/$role.toml" "$effective"
        for effort in xhigh max ultra; do
            variant=$stage/effort-sources/agent_rig_${role}_effort_$effort.toml
            awk -v name="agent_rig_${role}_effort_$effort" -v effort="$effort" '
                /^developer_instructions = / {
                    if (!effort_seen) print "model_reasoning_effort = \"" effort "\""
                    instructions = 1
                }
                !instructions && /^name = / { print "name = \"" name "\""; next }
                !instructions && /^model_reasoning_effort = / {
                    print "model_reasoning_effort = \"" effort "\""
                    effort_seen = 1
                    next
                }
                { print }
            ' "$effective" > "$variant"
            prepare_managed_file "$variant" "$agent_directory/agent_rig_${role}_effort_$effort.toml"
        done
    done
    prepare_managed_file "$RIG_ROOT/providers/claude/review.sh" "$state_directory/reviewers/claude.sh"
}
provider_render_instructions() {
    local role
    cat "$PROVIDER_ROOT/templates/$instructions_template"
    printf '\n## Installed request effort variants (active Rig requests only)\n\n'
    printf 'Only the roles listed below have installed effort variants. Select the name in the requested effort column.\n\n'
    printf '| Role | `effort=xhigh` | `effort=max` | `effort=ultra` |\n| --- | --- | --- | --- |\n'
    for role in $agents; do
        printf '| %s | `agent_rig_%s_effort_xhigh` | `agent_rig_%s_effort_max` | `agent_rig_%s_effort_ultra` |\n' "$role" "$role" "$role" "$role"
    done
    if [ "$global_install" -eq 1 ]; then
        printf '\nExternal reviewer runner: `%s/%s/reviewers/claude.sh`.\n' "$target" "$state_directory"
    else
        printf '\nExternal reviewer runner: `%s/reviewers/claude.sh`, relative to this section.\n' "$state_directory"
    fi
}

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
    manifest_files="$manifest_files|^[.]agent-rig/codex/reviewers/claude[.]sh$"
    manifest_files="$manifest_files|^[.]agent-rig/codex/models/overrides[.]ini$"
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
    printf 'Use a new Codex session to reload the setup. Rig activates through leading rig <workflow>: prefixes (recommended) or compatible @ aliases.\n'
}
