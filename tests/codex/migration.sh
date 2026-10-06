#!/usr/bin/env bash
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/../lib.sh"

legacy_install() {
    local destination=$1 scope=$2 name path crc bytes
    if [ "$scope" = global ]; then
        install_global "$SOURCE_ROOT" "$destination" --preset minimal
        agent_dir=agents
    else
        install "$SOURCE_ROOT" "$destination" --preset minimal
        agent_dir=.codex/agents
    fi
    mv "$destination/.agent-rig/codex/workflows" "$destination/.agent-rig/workflows"
    sed 's|.agent-rig/codex/workflows/|.agent-rig/workflows/|g' "$destination/AGENTS.md" > "$TEST_ROOT/legacy-instructions"
    cp "$TEST_ROOT/legacy-instructions" "$destination/AGENTS.md"
    printf 'agent-rig-manifest\t1\npreset\tminimal\nscope\t%s\n' "$scope" > "$destination/.agent-rig/manifest.tsv"
    for name in explorer implementer tester reviewer; do
        path=$agent_dir/agent_rig_$name.toml
        read -r crc bytes < <(cksum < "$destination/$path")
        printf 'file\t%s\t%s\t%s\n' "$path" "$crc" "$bytes" >> "$destination/.agent-rig/manifest.tsv"
    done
    for name in feature bug quick; do
        path=.agent-rig/workflows/$name.md
        read -r crc bytes < <(cksum < "$destination/$path")
        printf 'file\t%s\t%s\t%s\n' "$path" "$crc" "$bytes" >> "$destination/.agent-rig/manifest.tsv"
    done
    read -r crc bytes < <(cksum < "$destination/AGENTS.md")
    printf 'block\tAGENTS.md\t%s\t%s\n' "$crc" "$bytes" >> "$destination/.agent-rig/manifest.tsv"
    rm "$destination/.agent-rig/codex/manifest.tsv"
    mkdir -p "$destination/.agent-rig/backups/history"
    printf 'Keep legacy history\n' > "$destination/.agent-rig/backups/history/keep"
    printf 'Keep untracked legacy workflow\n' > "$destination/.agent-rig/workflows/custom.md"
}

for scope in project global; do
    destination=$TEST_ROOT/migrate-$scope
    mkdir "$destination"
    legacy_install "$destination" "$scope"
    cp "$destination/.agent-rig/manifest.tsv" "$TEST_ROOT/legacy-manifest"
    cp "$destination/AGENTS.md" "$TEST_ROOT/legacy-block"
    # Claude can coexist without modifying or adopting legacy Codex state.
    if [ "$scope" = project ]; then
        install "$SOURCE_ROOT" "$destination" --provider claude --preset minimal
    else
        env CLAUDE_CONFIG_DIR="$destination" bash "$SOURCE_ROOT/bin/agent-rig" install --yes --provider claude --global --preset minimal > "$TEST_ROOT/output" 2>&1 || fail 'Claude coexistence failed'
    fi
    assert_same "$TEST_ROOT/legacy-manifest" "$destination/.agent-rig/manifest.tsv"
    (cd "$destination" && find .agent-rig/claude -type f -exec cksum {} \; && cksum CLAUDE.md) | sort > "$TEST_ROOT/claude-before"
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    if [ "$scope" = project ]; then
        install "$SOURCE_ROOT" "$destination" --preset minimal --dry-run
    else
        install_global "$SOURCE_ROOT" "$destination" --preset minimal --dry-run
    fi
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    if [ "$scope" = project ]; then install "$SOURCE_ROOT" "$destination" --preset minimal
    else install_global "$SOURCE_ROOT" "$destination" --preset minimal; fi
    assert_missing "$destination/.agent-rig/manifest.tsv"
    assert_file "$destination/.agent-rig/codex/manifest.tsv"
    assert_contains "$destination/AGENTS.md" '.agent-rig/codex/workflows/feature.md'
    assert_missing "$destination/.agent-rig/workflows/feature.md"
    assert_contains "$destination/.agent-rig/workflows/custom.md" 'Keep untracked'
    assert_contains "$destination/.agent-rig/backups/history/keep" 'Keep legacy history'
    find_backup "$destination"
    assert_same "$TEST_ROOT/legacy-manifest" "$backup/.agent-rig/manifest.tsv"
    assert_same "$TEST_ROOT/legacy-block" "$backup/AGENTS.md"
    (cd "$destination" && find .agent-rig/claude -type f -exec cksum {} \; && cksum CLAUDE.md) | sort > "$TEST_ROOT/claude-after"
    assert_same "$TEST_ROOT/claude-before" "$TEST_ROOT/claude-after"
    pass "$scope legacy migration preserves history, untracked content, and Claude state"

    destination=$TEST_ROOT/remove-$scope
    mkdir "$destination"
    legacy_install "$destination" "$scope"
    if [ "$scope" = project ]; then
        bash "$SOURCE_ROOT/bin/agent-rig" uninstall --target "$destination" > "$TEST_ROOT/output" 2>&1 || fail 'Legacy removal failed'
    else
        env CODEX_HOME="$destination" bash "$SOURCE_ROOT/bin/agent-rig" uninstall --global > "$TEST_ROOT/output" 2>&1 || fail 'Legacy global removal failed'
    fi
    assert_missing "$destination/.agent-rig/manifest.tsv"
    assert_missing "$destination/$agent_dir/agent_rig_explorer.toml"
    assert_contains "$destination/.agent-rig/backups/history/keep" 'Keep legacy history'
    pass "$scope legacy uninstall works without a migration first"
done

project=$TEST_ROOT/modified
mkdir "$project"
legacy_install "$project" project
printf '\nLocal legacy edit\n' >> "$project/.agent-rig/workflows/feature.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$SOURCE_ROOT" "$project" --preset minimal
assert_contains "$TEST_ROOT/output" 'locally modified'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install "$SOURCE_ROOT" "$project" --preset minimal --replace-modified
find_backup "$project"
assert_contains "$backup/.agent-rig/workflows/feature.md" 'Local legacy edit'
pass 'Legacy migration protects local edits and backs up explicit replacements'

project=$TEST_ROOT/legacy-locked
mkdir "$project"
legacy_install "$project" project
mkdir "$project/.agent-rig/.install-lock"
reject "$SOURCE_ROOT" "$project" --preset minimal
assert_contains "$TEST_ROOT/output" 'legacy .agent-rig/.install-lock'
assert_file "$project/.agent-rig/manifest.tsv"
assert_missing "$project/.agent-rig/codex/.install-lock"
pass 'Legacy migration respects the old lock and releases its own lock on failure'

project=$TEST_ROOT/dual-manifests
mkdir "$project"
legacy_install "$project" project
cp "$project/.agent-rig/manifest.tsv" "$project/.agent-rig/codex/manifest.tsv"
reject "$SOURCE_ROOT" "$project" --preset minimal
assert_contains "$TEST_ROOT/output" 'Both legacy and provider manifests'
pass 'Ambiguous dual Codex manifests require reconciliation'

project=$TEST_ROOT/rollback
mkdir "$project"
legacy_install "$project" project
fingerprint_tree "$project" > "$TEST_ROOT/before"
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
if env PATH="$TEST_ROOT/fake-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$project/.agent-rig/codex/manifest.tsv" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/failed" bash "$SOURCE_ROOT/bin/agent-rig" install --yes --target "$project" --preset minimal > "$TEST_ROOT/output" 2>&1; then fail 'Migration failure not triggered'; fi
assert_contains "$TEST_ROOT/output" 'Write failed; restoring'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$project/.agent-rig/.install-lock"
assert_missing "$project/.agent-rig/codex/.install-lock"
pass 'Failed migration restores legacy files and releases both locks'
printf '\nAll %s migration checks passed.\n' "$passed"
