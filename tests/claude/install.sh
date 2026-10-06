#!/usr/bin/env bash
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/../lib.sh"

claude_run() {
    local operation=$1 rig=$2 destination=$3 scope=$4
    shift 4
    if [ "$scope" = global ]; then
        env CLAUDE_CONFIG_DIR="$destination" bash "$rig/bin/agent-rig" "$operation" --provider claude --global "$@" > "$TEST_ROOT/output" 2>&1
    else
        bash "$rig/bin/agent-rig" "$operation" --provider claude --target "$destination" "$@" > "$TEST_ROOT/output" 2>&1
    fi
}
claude_ok() {
    claude_run "$@" || { cat "$TEST_ROOT/output" >&2; fail 'Claude operation failed'; }
}
claude_reject() {
    if claude_run "$@"; then fail 'Expected Claude rejection'; fi
}
provider_fingerprint() {
    local destination=$1 provider=$2
    (cd "$destination" && find ".$provider" ".agent-rig/$provider" -type f -exec cksum {} \; && cksum "$3") | sort
}

assert_claude_agent() {
    local rig=$1 role=$2 installed=$3
    awk -f "$rig/providers/claude/models/policy.awk" "$rig/providers/claude/models/policy.tsv" > "$TEST_ROOT/expected-policy"
    awk -v role="$role" -f "$rig/providers/claude/models/render.awk" "$TEST_ROOT/expected-policy" "$rig/providers/claude/agents/$role.md" > "$TEST_ROOT/expected-agent"
    assert_same "$TEST_ROOT/expected-agent" "$installed"
}

for scope in project global; do
    for preset in minimal backend security full; do
        destination=$TEST_ROOT/$scope-$preset
        mkdir "$destination"
        claude_ok install "$SOURCE_ROOT" "$destination" "$scope" --preset "$preset"
        if [ "$scope" = global ]; then agent_dir=agents; else agent_dir=.claude/agents; fi
        roles=$(sed -n 's/^agents: //p' "$SOURCE_ROOT/providers/claude/presets/$preset.preset")
        workflows=$(sed -n 's/^workflows: //p' "$SOURCE_ROOT/providers/claude/presets/$preset.preset")
        count=0
        for role in $roles; do
            assert_claude_agent "$SOURCE_ROOT" "$role" "$destination/$agent_dir/agent-rig-$role.md"
            assert_contains "$destination/CLAUDE.md" "agent-rig-$role"
            count=$((count + 1))
        done
        [ "$(find "$destination/$agent_dir" -type f | wc -l)" -eq "$count" ] || fail 'Incorrect role membership'
        count=0
        for workflow in $workflows; do
            assert_same "$SOURCE_ROOT/providers/claude/workflows/$workflow.md" "$destination/.agent-rig/claude/workflows/$workflow.md"
            assert_contains "$destination/CLAUDE.md" ".agent-rig/claude/workflows/$workflow.md"
            count=$((count + 1))
        done
        [ "$(find "$destination/.agent-rig/claude/workflows" -type f | wc -l)" -eq "$count" ] || fail 'Incorrect workflow membership'
        assert_contains "$destination/CLAUDE.md" '<!-- agent-rig:begin -->'
        assert_contains "$destination/CLAUDE.md" '<!-- agent-rig:end -->'
        assert_contains "$destination/CLAUDE.md" 'Without a leading workflow alias, Agent Rig is inactive.'
        assert_contains "$destination/.agent-rig/claude/manifest.tsv" "$(printf 'provider\tclaude')"
        if [ "$scope" = global ]; then
            assert_contains "$destination/CLAUDE.md" "$destination/.agent-rig/claude/workflows/"
        fi
        assert_missing "$destination/AGENTS.md"
        assert_missing "$destination/.codex"
        assert_missing "$destination/.agent-rig/codex"
        fingerprint_tree "$destination" > "$TEST_ROOT/before"
        claude_ok install "$SOURCE_ROOT" "$destination" "$scope" --preset "$preset"
        assert_contains "$TEST_ROOT/output" 'Already up to date.'
        fingerprint_tree "$destination" > "$TEST_ROOT/after"
        assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
        claude_ok uninstall "$SOURCE_ROOT" "$destination" "$scope"
        assert_missing "$destination/.agent-rig/claude/manifest.tsv"
        [ ! -s "$destination/CLAUDE.md" ] || fail 'Instructions were not removed'
        [ "$(find "$destination/$agent_dir" -type f | wc -l)" -eq 0 ] || fail 'Agents remained'
        pass "Claude $scope $preset membership, idempotence, activation, and removal"
    done

done

missing=$TEST_ROOT/missing/home
claude_ok install "$SOURCE_ROOT" "$missing" global --dry-run
assert_missing "$TEST_ROOT/missing"
claude_ok uninstall "$SOURCE_ROOT" "$missing" global
assert_missing "$TEST_ROOT/missing"
pass 'Claude global dry run and manifest-free removal create no directories'

user_home=$TEST_ROOT/user-home
mkdir "$user_home"
env -u CLAUDE_CONFIG_DIR HOME="$user_home" bash "$SOURCE_ROOT/bin/agent-rig" install --provider claude --global --preset minimal > "$TEST_ROOT/output" 2>&1 || fail 'Claude HOME fallback failed'
assert_file "$user_home/.claude/agents/agent-rig-explorer.md"
pass 'Claude global discovery honors the HOME fallback'

# A real source update must change only the selected provider, in either order.
for first in codex claude; do
    rig=$TEST_ROOT/source-$first
    fixture "$rig"
    project=$TEST_ROOT/coexist-$first
    mkdir -p "$project/.claude" "$project/.codex"
    printf '{"permissions":{"deny":["Bash(rm *)"]}}\n' > "$project/.claude/settings.json"
    printf '{"local":true}\n' > "$project/.claude/settings.local.json"
    printf '# Custom instructions without EOF newline' > "$project/CLAUDE.md"
    cp "$project/CLAUDE.md" "$TEST_ROOT/original-claude"
    cp "$project/.claude/settings.json" "$TEST_ROOT/settings"
    cp "$project/.claude/settings.local.json" "$TEST_ROOT/local-settings"
    if [ "$first" = codex ]; then
        install "$rig" "$project"
        claude_ok install "$rig" "$project" project
    else
        claude_ok install "$rig" "$project" project
        install "$rig" "$project"
    fi
    printf 'Custom trailing instructions without EOF newline' >> "$project/CLAUDE.md"
    printf '\n\nCustom trailing instructions without EOF newline' >> "$TEST_ROOT/original-claude"
    provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-before"
    printf '\nUpdated native Claude guidance.\n' >> "$rig/providers/claude/agents/explorer.md"
    printf '\nUpdated Claude workflow.\n' >> "$rig/providers/claude/workflows/feature.md"
    printf '\nUpdated Claude orchestration.\n' >> "$rig/providers/claude/templates/CLAUDE.md"
    claude_ok install "$rig" "$project" project
    assert_claude_agent "$rig" explorer "$project/.claude/agents/agent-rig-explorer.md"
    provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-after"
    assert_same "$TEST_ROOT/codex-before" "$TEST_ROOT/codex-after"
    provider_fingerprint "$project" claude CLAUDE.md > "$TEST_ROOT/claude-before"
    printf '\n# Updated Codex agent\n' >> "$rig/providers/codex/agents/explorer.toml"
    printf '\nUpdated Codex workflow.\n' >> "$rig/providers/codex/workflows/feature.md"
    printf '\nUpdated Codex orchestration.\n' >> "$rig/providers/codex/templates/AGENTS.md"
    install "$rig" "$project"
    provider_fingerprint "$project" claude CLAUDE.md > "$TEST_ROOT/claude-after"
    assert_same "$TEST_ROOT/claude-before" "$TEST_ROOT/claude-after"
    provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-before"
    claude_ok uninstall "$rig" "$project" project
    provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-after"
    assert_same "$TEST_ROOT/codex-before" "$TEST_ROOT/codex-after"
    assert_same "$TEST_ROOT/original-claude" "$project/CLAUDE.md"
    claude_ok install "$rig" "$project" project
    provider_fingerprint "$project" claude CLAUDE.md > "$TEST_ROOT/claude-before"
    bash "$rig/bin/agent-rig" uninstall --target "$project" > "$TEST_ROOT/output" 2>&1 || fail 'Codex removal failed'
    provider_fingerprint "$project" claude CLAUDE.md > "$TEST_ROOT/claude-after"
    assert_same "$TEST_ROOT/claude-before" "$TEST_ROOT/claude-after"
    assert_same "$TEST_ROOT/settings" "$project/.claude/settings.json"
    assert_same "$TEST_ROOT/local-settings" "$project/.claude/settings.local.json"
    pass "Both providers coexist ($first first); real updates, backups, and removal remain isolated"
done

project=$TEST_ROOT/modified
mkdir "$project"
install "$SOURCE_ROOT" "$project"
claude_ok install "$SOURCE_ROOT" "$project" project
provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-before"
printf '\nLocal edits.\n' >> "$project/.claude/agents/agent-rig-explorer.md"
printf '\nLocal workflow edits.\n' >> "$project/.agent-rig/claude/workflows/feature.md"
sed 's/## Root ownership/## Custom root ownership/' "$project/CLAUDE.md" > "$TEST_ROOT/edited"
cp "$TEST_ROOT/edited" "$project/CLAUDE.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
claude_reject install "$SOURCE_ROOT" "$project" project
assert_contains "$TEST_ROOT/output" 'managed section locally modified'
claude_reject uninstall "$SOURCE_ROOT" "$project" project
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
claude_ok install "$SOURCE_ROOT" "$project" project --replace-modified --preset minimal
assert_missing "$project/.claude/agents/agent-rig-database.md"
[ -d "$project/.agent-rig/claude/backups" ] || fail 'Expected Claude backups'
assert_same "$TEST_ROOT/edited" "$(find "$project/.agent-rig/claude/backups" -name CLAUDE.md | head -1)"
provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-after"
assert_same "$TEST_ROOT/codex-before" "$TEST_ROOT/codex-after"
printf '\nNew local edit.\n' >> "$project/.claude/agents/agent-rig-explorer.md"
claude_ok uninstall "$SOURCE_ROOT" "$project" project --remove-modified
provider_fingerprint "$project" codex AGENTS.md > "$TEST_ROOT/codex-after"
assert_same "$TEST_ROOT/codex-before" "$TEST_ROOT/codex-after"
pass 'Claude protects local edits; explicit replacement/removal backs up changes and preserves Codex'

# Ownership must remain isolated even when a manifest has been tampered with.
for provider in codex claude; do
    project=$TEST_ROOT/foreign-$provider
    mkdir "$project"
    install "$SOURCE_ROOT" "$project"
    claude_ok install "$SOURCE_ROOT" "$project" project
    if [ "$provider" = claude ]; then foreign=.codex/agents/agent_rig_explorer.toml
    else foreign=.claude/agents/agent-rig-explorer.md; fi
    read -r crc bytes < <(cksum < "$project/$foreign")
    printf 'file\t%s\t%s\t%s\n' "$foreign" "$crc" "$bytes" >> "$project/.agent-rig/$provider/manifest.tsv"
    fingerprint_tree "$project" > "$TEST_ROOT/before"
    if bash "$SOURCE_ROOT/bin/agent-rig" uninstall --provider "$provider" --target "$project" --remove-modified > "$TEST_ROOT/output" 2>&1; then fail 'Foreign ownership accepted'; fi
    assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
    fingerprint_tree "$project" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    pass "$provider manifest cannot claim the other provider's content"
done

for path in .claude .claude/agents CLAUDE.md .agent-rig .agent-rig/claude .agent-rig/claude/manifest.tsv .agent-rig/claude/backups .agent-rig/claude/.install-lock .agent-rig/claude/workflows; do
    project=$TEST_ROOT/link-${path//\//-}
    mkdir -p "$project/$(dirname -- "$path")"
    ln -s "$TEST_ROOT" "$project/$path"
    claude_reject install "$SOURCE_ROOT" "$project" project --replace-modified
    assert_contains "$TEST_ROOT/output" 'symlink'
done
pass 'Claude rejects destination symlinks before writing'

project=$TEST_ROOT/malformed
mkdir "$project"
printf '<!-- agent-rig:begin -->\nBroken instructions\n' > "$project/CLAUDE.md"
claude_reject install "$SOURCE_ROOT" "$project" project --replace-modified
assert_contains "$TEST_ROOT/output" 'Malformed or duplicate'
assert_missing "$project/.claude"
pass 'Claude rejects malformed markers even with explicit replacement'

project=$TEST_ROOT/locked
mkdir "$project"
claude_ok install "$SOURCE_ROOT" "$project" project
mkdir "$project/.agent-rig/claude/.install-lock"
claude_reject uninstall "$SOURCE_ROOT" "$project" project
assert_contains "$TEST_ROOT/output" 'Another Agent Rig operation holds'
install "$SOURCE_ROOT" "$project"
pass 'Provider locks protect their lifecycle while allowing the other provider to install'

# Trigger failure after preceding writes/deletions; rollback must restore both
# content and ownership state, without touching the other provider.
mkdir "$TEST_ROOT/fake-bin"
cat > "$TEST_ROOT/fake-bin/mv" <<'SH'
#!/usr/bin/env bash
last=''
for arg in "$@"; do last=$arg; done
if [ "$last" = "$AGENT_RIG_FAIL_PATH" ] && [ ! -e "$AGENT_RIG_FAIL_ONCE" ]; then
    touch "$AGENT_RIG_FAIL_ONCE"
    exit 1
fi
exec "$AGENT_RIG_REAL_MV" "$@"
SH
chmod +x "$TEST_ROOT/fake-bin/mv"
for operation in install uninstall; do
    project=$TEST_ROOT/rollback-$operation
    rig=$TEST_ROOT/rollback-source-$operation
    fixture "$rig"
    mkdir "$project"
    install "$rig" "$project"
    claude_ok install "$rig" "$project" project --preset minimal
    printf '\nUpdated agent.\n' >> "$rig/providers/claude/agents/explorer.md"
    printf '\nUpdated root guidance.\n' >> "$rig/providers/claude/templates/CLAUDE.md"
    fingerprint_tree "$project" > "$TEST_ROOT/before"
    # Both install and uninstall rewrite the instruction file after agent writes
    # or deletions, so failing that move exercises restoration of prior changes.
    if env PATH="$TEST_ROOT/fake-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$project/CLAUDE.md" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/failed-$operation" bash "$rig/bin/agent-rig" "$operation" --provider claude --target "$project" > "$TEST_ROOT/output" 2>&1; then fail 'Injected failure was ignored'; fi
    assert_contains "$TEST_ROOT/output" 'Write failed; restoring'
    fingerprint_tree "$project" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    assert_missing "$project/.agent-rig/claude/.install-lock"
    pass "Failed Claude $operation restores prior content and manifest while preserving Codex"
done

for provider in codex claude; do
    project=$TEST_ROOT/lookalike-$provider
    mkdir "$project"
    install "$SOURCE_ROOT" "$project" --provider "$provider" --preset minimal
    cp "$project/.agent-rig/$provider/manifest.tsv" "$TEST_ROOT/valid-manifest"
    for path in "xagent-rig/$provider/workflows/featureXmd"; do
        mkdir -p "$project/$(dirname -- "$path")"
        printf 'Unowned lookalike file\n' > "$project/$path"
        read -r crc bytes < <(cksum < "$project/$path")
        printf 'file\t%s\t%s\t%s\n' "$path" "$crc" "$bytes" >> "$project/.agent-rig/$provider/manifest.tsv"
        fingerprint_tree "$project" > "$TEST_ROOT/before"
        if bash "$SOURCE_ROOT/bin/agent-rig" uninstall --provider "$provider" --target "$project" --remove-modified > "$TEST_ROOT/output" 2>&1; then fail 'Lookalike namespace was accepted'; fi
        assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
        fingerprint_tree "$project" > "$TEST_ROOT/after"
        assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
        cp "$TEST_ROOT/valid-manifest" "$project/.agent-rig/$provider/manifest.tsv"
    done
    if [ "$provider" = codex ]; then path=AGENTSXmd; else path=CLAUDEXmd; fi
    awk -F '\t' -v path="$path" 'BEGIN { OFS = "\t" } $1 == "block" { $2 = path } { print }' "$TEST_ROOT/valid-manifest" > "$project/.agent-rig/$provider/manifest.tsv"
    if bash "$SOURCE_ROOT/bin/agent-rig" uninstall --provider "$provider" --target "$project" --remove-modified > "$TEST_ROOT/output" 2>&1; then fail 'Lookalike extension was accepted'; fi
    assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
    pass "$provider manifest patterns preserve literal dots and reject lookalike namespaces"
done

if bash "$SOURCE_ROOT/bin/agent-rig" install --provider unknown --target "$TEST_ROOT" > "$TEST_ROOT/output" 2>&1; then fail 'Unknown provider accepted'; fi
assert_contains "$TEST_ROOT/output" 'Unknown provider'
pass 'Unknown providers are rejected'
printf '\nAll %s Claude and coexistence checks passed.\n' "$passed"
