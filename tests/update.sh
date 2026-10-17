#!/usr/bin/env bash
# Exercise update as a public command, using only disposable installations.
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

rig_run() {
    local operation=$1 rig=$2 provider=$3 destination=$4 scope=$5
    shift 5
    if [ "$scope" = global ]; then
        env CODEX_HOME="$destination" CLAUDE_CONFIG_DIR="$destination" bash "$rig/bin/agent-rig" "$operation" --provider "$provider" --global "$@" > "$TEST_ROOT/output" 2>&1
    else
        bash "$rig/bin/agent-rig" "$operation" --provider "$provider" --target "$destination" "$@" > "$TEST_ROOT/output" 2>&1
    fi
}
rig_ok() {
    rig_run "$@" || { cat "$TEST_ROOT/output" >&2; fail 'Expected successful lifecycle command'; }
}
update_reject() {
    if rig_run update "$@"; then fail 'Expected update rejection'; fi
}
assert_unchanged() {
    fingerprint_tree "$1" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
}
provider_fingerprint() {
    local destination=$1 provider=$2 instructions=$3
    (cd "$destination" && find ".$provider" ".agent-rig/$provider" -type f -exec cksum {} \; && cksum "$instructions") | sort
}

# Omitted --preset must retain every installed preset, rather than expand it.
for provider in codex claude; do
    rig=$TEST_ROOT/global-source-$provider
    fixture "$rig"
    destination=$TEST_ROOT/global-refresh-$provider
    mkdir "$destination"
    rig_ok install "$rig" "$provider" "$destination" global --yes --preset security
    printf '\nUpdated global guidance.\n' >> "$rig/providers/$provider/workflows/security.md"
    rig_ok update "$rig" "$provider" "$destination" global --yes < /dev/null
    assert_same "$rig/providers/$provider/workflows/security.md" "$destination/.agent-rig/$provider/workflows/security.md"
    assert_contains "$destination/.agent-rig/$provider/manifest.tsv" "$(printf 'preset\tsecurity')"
    assert_contains "$destination/.agent-rig/$provider/manifest.tsv" "$(printf 'scope\tglobal')"
    pass "$provider global update applies changed source and preserves scope and preset"

    for scope in project global; do
        for preset in minimal backend security full; do
            destination=$TEST_ROOT/$provider-$scope-$preset
            mkdir "$destination"
            rig_ok install "$SOURCE_ROOT" "$provider" "$destination" "$scope" --yes --preset "$preset"
            fingerprint_tree "$destination" > "$TEST_ROOT/before"
            rig_ok update "$SOURCE_ROOT" "$provider" "$destination" "$scope" < /dev/null
            assert_contains "$TEST_ROOT/output" 'Already up to date.'
            assert_unchanged "$destination"
            assert_contains "$destination/.agent-rig/$provider/manifest.tsv" "$(printf 'preset\t%s' "$preset")"
            assert_missing "$destination/.agent-rig/$provider/backups"
            assert_missing "$destination/.agent-rig/$provider/.install-lock"
            pass "$provider $scope update preserves $preset and requires no confirmation for no-op"
        done
    done
done

# A real update refreshes workflows and instructions while retaining user data
# and the other provider's complete installation.
for provider in codex claude; do
    rig=$TEST_ROOT/changed-source-$provider
    fixture "$rig"
    project="$TEST_ROOT/update $provider with spaces"
    mkdir -p "$project/.codex" "$project/.claude"
    printf 'model = "user-model"\n' > "$project/.codex/config.toml"
    printf '{"permissions":{"deny":["Bash(rm *)"]}}\n' > "$project/.claude/settings.json"
    printf 'User Codex instructions' > "$project/AGENTS.md"
    printf 'User Claude instructions' > "$project/CLAUDE.md"
    cp "$project/.codex/config.toml" "$TEST_ROOT/config"
    cp "$project/.claude/settings.json" "$TEST_ROOT/settings"
    rig_ok install "$rig" codex "$project" project --yes --preset backend
    rig_ok install "$rig" claude "$project" project --yes --preset backend
    if [ "$provider" = codex ]; then
        instructions=AGENTS.md; other=claude; other_instructions=CLAUDE.md
    else
        instructions=CLAUDE.md; other=codex; other_instructions=AGENTS.md
    fi
    printf 'User suffix without newline' >> "$project/$instructions"
    provider_fingerprint "$project" "$other" "$other_instructions" > "$TEST_ROOT/other-before"
    cp "$project/.agent-rig/$provider/workflows/feature.md" "$TEST_ROOT/old-workflow"
    cp "$project/.agent-rig/$provider/manifest.tsv" "$TEST_ROOT/old-manifest"
    printf '\nNew update command workflow.\n' >> "$rig/providers/$provider/workflows/feature.md"
    printf '\nNew update command guidance.\n' >> "$rig/providers/$provider/templates/$instructions"
    (cd "$project" && find ".agent-rig/$provider/backups" -type f -exec cksum {} \;) | sort > "$TEST_ROOT/backups-before"
    fingerprint_tree "$project" > "$TEST_ROOT/before"
    rig_ok update "$rig" "$provider" "$project" project --dry-run < /dev/null
    assert_contains "$TEST_ROOT/output" 'Dry run: no target files changed.'
    assert_unchanged "$project"
    printf 'n\n' | rig_ok update "$rig" "$provider" "$project" project
    assert_contains "$TEST_ROOT/output" 'Continue with update? [y/N]'
    assert_unchanged "$project"
    update_reject "$rig" "$provider" "$project" project < /dev/null
    assert_contains "$TEST_ROOT/output" 'No confirmation received'
    assert_unchanged "$project"
    (cd "$project" && find ".agent-rig/$provider/backups" -type f -exec cksum {} \;) | sort > "$TEST_ROOT/backups-after"
    assert_same "$TEST_ROOT/backups-before" "$TEST_ROOT/backups-after"
    printf 'yes\n' | rig_ok update "$rig" "$provider" "$project" project
    assert_contains "$TEST_ROOT/output" 'Updating Agent Rig...'
    assert_contains "$TEST_ROOT/output" 'Updated successfully.'
    assert_same "$rig/providers/$provider/workflows/feature.md" "$project/.agent-rig/$provider/workflows/feature.md"
    assert_contains "$project/$instructions" 'New update command guidance.'
    assert_contains "$project/$instructions" "User $([ "$provider" = codex ] && printf Codex || printf Claude) instructions"
    tail -c 27 "$project/$instructions" > "$TEST_ROOT/suffix"
    printf 'User suffix without newline' > "$TEST_ROOT/expected-suffix"
    assert_same "$TEST_ROOT/expected-suffix" "$TEST_ROOT/suffix"
    provider_fingerprint "$project" "$other" "$other_instructions" > "$TEST_ROOT/other-after"
    assert_same "$TEST_ROOT/other-before" "$TEST_ROOT/other-after"
    assert_same "$TEST_ROOT/config" "$project/.codex/config.toml"
    assert_same "$TEST_ROOT/settings" "$project/.claude/settings.json"
    backup=$(find "$project/.agent-rig/$provider/backups" -name manifest.tsv -print | tail -1)
    assert_same "$TEST_ROOT/old-manifest" "$backup"
    backup=$(find "$project/.agent-rig/$provider/backups" -name feature.md -print | tail -1)
    assert_same "$TEST_ROOT/old-workflow" "$backup"
    pass "$provider real update, dry run, cancellation, EOF, confirmation, backups, and provider isolation"

    printf '\nLocal customization.\n' >> "$project/.agent-rig/$provider/workflows/feature.md"
    cp "$project/.agent-rig/$provider/workflows/feature.md" "$TEST_ROOT/local-workflow"
    fingerprint_tree "$project" > "$TEST_ROOT/before"
    update_reject "$rig" "$provider" "$project" project --yes
    assert_contains "$TEST_ROOT/output" 'locally modified'
    assert_unchanged "$project"
    rig_ok update "$rig" "$provider" "$project" project -y --replace-modified --preset minimal
    assert_contains "$project/.agent-rig/$provider/manifest.tsv" "$(printf 'preset\tminimal')"
    assert_same "$rig/providers/$provider/workflows/feature.md" "$project/.agent-rig/$provider/workflows/feature.md"
    assert_missing "$project/.agent-rig/$provider/workflows/review.md"
    backup=$(find "$project/.agent-rig/$provider/backups" -name feature.md -exec sh -c 'cmp -s "$1" "$2" && printf "%s\n" "$1"; exit 0' sh '{}' "$TEST_ROOT/local-workflow" \;)
    [ -n "$backup" ] || fail 'Missing backup of local workflow customization'
    pass "$provider update protects local changes and supports backed-up replacement and explicit preset switching"

    mkdir "$project/.agent-rig/$provider/.install-lock"
    fingerprint_tree "$project" > "$TEST_ROOT/before"
    update_reject "$rig" "$provider" "$project" project --yes --preset full
    assert_unchanged "$project"
    [ -d "$project/.agent-rig/$provider/.install-lock" ] || fail 'Update removed another process lock'
    pass "$provider update respects lifecycle lock"
done

for provider in codex claude; do
    for scope in project global; do
        destination=$TEST_ROOT/missing-$provider-$scope
        if [ "$scope" = project ]; then mkdir "$destination"; fi
        update_reject "$SOURCE_ROOT" "$provider" "$destination" "$scope" --yes
        if [ "$scope" = global ]; then assert_missing "$destination"
        else [ -z "$(find "$destination" -mindepth 1 -print)" ] || fail 'Missing-manifest update wrote files'; fi
        update_reject "$SOURCE_ROOT" "$provider" "$destination" "$scope" --dry-run
        if [ "$scope" = global ]; then assert_missing "$destination"; fi
        pass "$provider $scope update requires installation without creating state"
    done

    destination=$TEST_ROOT/other-only-$provider
    mkdir "$destination"
    if [ "$provider" = codex ]; then other=claude; else other=codex; fi
    rig_ok install "$SOURCE_ROOT" "$other" "$destination" project --yes --preset minimal
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    update_reject "$SOURCE_ROOT" "$provider" "$destination" project --yes
    assert_unchanged "$destination"
    assert_missing "$destination/.agent-rig/$provider"
    pass "$provider update cannot treat another provider's manifest as its installation"

    destination=$TEST_ROOT/invalid-$provider
    mkdir "$destination"
    rig_ok install "$SOURCE_ROOT" "$provider" "$destination" project --yes --preset minimal
    manifest=$destination/.agent-rig/$provider/manifest.tsv
    cp "$manifest" "$TEST_ROOT/valid-manifest"
    for corruption in path preset duplicate; do
        cp "$TEST_ROOT/valid-manifest" "$manifest"
        case $corruption in
            path) printf 'file\t../../outside\t1\t1\n' >> "$manifest" ;;
            preset) sed 's/^preset.*/preset\tunknown/' "$TEST_ROOT/valid-manifest" > "$manifest" ;;
            duplicate) printf 'preset\tfull\n' >> "$manifest" ;;
        esac
        fingerprint_tree "$destination" > "$TEST_ROOT/before"
        update_reject "$SOURCE_ROOT" "$provider" "$destination" project --yes --replace-modified --preset full
        assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
        assert_unchanged "$destination"
        assert_missing "$destination/.agent-rig/$provider/backups"
    done
    cp "$TEST_ROOT/valid-manifest" "$manifest"
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    update_reject "$SOURCE_ROOT" "$provider" "$destination" global --yes
    assert_contains "$TEST_ROOT/output" 'Installation scope differs'
    assert_unchanged "$destination"
    pass "$provider rejects malformed manifests even with explicit preset and rejects wrong scope without writes"
done

# Fail a later write after an earlier workflow has changed; restore all files
# and the prior manifest, then release the shared installation lock.
mkdir "$TEST_ROOT/failing-bin"
cat > "$TEST_ROOT/failing-bin/mv" <<'SH'
#!/usr/bin/env bash
for destination; do :; done
if [ "$destination" = "$AGENT_RIG_FAIL_PATH" ] && [ ! -e "$AGENT_RIG_FAIL_ONCE" ]; then
    : > "$AGENT_RIG_FAIL_ONCE"
    exit 1
fi
exec "$AGENT_RIG_REAL_MV" "$@"
SH
chmod +x "$TEST_ROOT/failing-bin/mv"
for provider in codex claude; do
    rig=$TEST_ROOT/rollback-source-$provider
    fixture "$rig"
    destination=$TEST_ROOT/rollback-$provider
    mkdir "$destination"
    rig_ok install "$rig" "$provider" "$destination" project --yes --preset minimal
    for name in feature bug; do printf '\nUpdated workflow.\n' >> "$rig/providers/$provider/workflows/$name.md"; done
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    if env PATH="$TEST_ROOT/failing-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$destination/.agent-rig/$provider/manifest.tsv" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/failed-$provider" bash "$rig/bin/agent-rig" update --provider "$provider" --target "$destination" --yes > "$TEST_ROOT/output" 2>&1; then
        fail 'Injected update write failure was ignored'
    fi
    assert_file "$TEST_ROOT/failed-$provider"
    assert_contains "$TEST_ROOT/output" 'restoring changed files'
    assert_unchanged "$destination"
    assert_missing "$destination/.agent-rig/$provider/.install-lock"
    [ -z "$(find "$destination" -name '.agent-rig-write.*' -print)" ] || fail 'Update leaked temporary files'
    pass "$provider failed update rolls back prior files and manifest and releases lock"
done

# Provider-less legacy Codex manifests still count as an existing installation.
destination=$TEST_ROOT/legacy-codex
mkdir "$destination"
rig_ok install "$SOURCE_ROOT" codex "$destination" project --yes --preset minimal
mv "$destination/.agent-rig/codex/workflows" "$destination/.agent-rig/workflows"
sed 's|.agent-rig/codex/workflows/|.agent-rig/workflows/|g' "$destination/AGENTS.md" > "$TEST_ROOT/legacy-instructions"
cp "$TEST_ROOT/legacy-instructions" "$destination/AGENTS.md"
printf 'agent-rig-manifest\t1\npreset\tminimal\nscope\tproject\n' > "$destination/.agent-rig/manifest.tsv"
for name in explorer implementer tester reviewer; do
    path=.codex/agents/agent_rig_$name.toml
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
rig_ok update "$SOURCE_ROOT" codex "$destination" project --yes
assert_contains "$destination/.agent-rig/codex/manifest.tsv" "$(printf 'preset\tminimal')"
assert_missing "$destination/.agent-rig/manifest.tsv"
assert_contains "$destination/AGENTS.md" '.agent-rig/codex/workflows/feature.md'
pass 'Explicit update migrates a legacy Codex installation and preserves its preset'

printf '\n%s update checks passed.\n' "$passed"
