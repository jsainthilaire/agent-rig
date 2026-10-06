#!/usr/bin/env bash
# All removal targets are disposable projects or Codex homes under TEST_ROOT.
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/../lib.sh"

install_scoped() {
    local rig=$1 destination=$2 scope=$3
    shift 3
    if [ "$scope" = global ]; then
        install_global "$rig" "$destination" "$@"
    else
        install "$rig" "$destination" "$@"
    fi
}

run_uninstall() {
    local rig=$1 destination=$2 scope=$3
    shift 3
    if [ "$scope" = global ]; then
        env CODEX_HOME="$destination" bash "$rig/bin/agent-rig" uninstall --global "$@" > "$TEST_ROOT/output" 2>&1
    else
        bash "$rig/bin/agent-rig" uninstall --target "$destination" "$@" > "$TEST_ROOT/output" 2>&1
    fi
}

uninstall_ok() {
    if ! run_uninstall "$@"; then
        cat "$TEST_ROOT/output" >&2
        fail "Uninstall failed: $2"
    fi
}

reject_uninstall() {
    if run_uninstall "$@"; then fail "Expected uninstall rejection: $2"; fi
}

assert_managed_removed() {
    local destination=$1 manifest=$2 kind rel crc bytes
    while IFS="$(printf '\t')" read -r kind rel crc bytes; do
        [ "$kind" = file ] || continue
        assert_missing "$destination/$rel"
    done < "$manifest"
    assert_missing "$destination/.agent-rig/codex/manifest.tsv"
    assert_missing "$destination/.agent-rig/codex/.install-lock"
}

for scope in project global; do
    if [ "$scope" = global ]; then agent_dir=agents; config_rel=config.toml; else agent_dir=.codex/agents; config_rel=.codex/config.toml; fi
    destination="$TEST_ROOT/$scope with spaces"
    mkdir -p "$destination/$agent_dir"
    printf 'model = "my-model"\n[agents]\nenabled = false\n' > "$destination/$config_rel"
    cp "$destination/$config_rel" "$TEST_ROOT/config"
    printf 'name = "explorer"\n# My own agent\n' > "$destination/$agent_dir/explorer.toml"
    cp "$destination/$agent_dir/explorer.toml" "$TEST_ROOT/user-role"
    install_scoped "$SOURCE_ROOT" "$destination" "$scope"
    cp "$destination/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/manifest"
    cp "$destination/$agent_dir/agent_rig_explorer.toml" "$TEST_ROOT/installed-role"
    cp "$destination/AGENTS.md" "$TEST_ROOT/block"
    # Keep exact outside bytes, including Unicode, CRLF, and no final newline.
    printf '# My instructions: café\r\nKeep these rules.\r\n' > "$TEST_ROOT/prefix"
    printf '\nMy suffix: résumé, no final newline' > "$TEST_ROOT/suffix"
    cat "$TEST_ROOT/prefix" "$TEST_ROOT/block" "$TEST_ROOT/suffix" > "$destination/AGENTS.md"
    cat "$TEST_ROOT/prefix" "$TEST_ROOT/suffix" > "$TEST_ROOT/outside"
    cp "$destination/AGENTS.md" "$TEST_ROOT/installed-instructions"
    printf '# Untracked workflow\n' > "$destination/.agent-rig/codex/workflows/custom.md"
    cp "$destination/.agent-rig/codex/workflows/custom.md" "$TEST_ROOT/custom-workflow"
    mkdir -p "$destination/.agent-rig/codex/backups/history"
    printf 'Earlier backup\n' > "$destination/.agent-rig/codex/backups/history/keep.txt"
    cp "$destination/.agent-rig/codex/backups/history/keep.txt" "$TEST_ROOT/old-backup"

    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope" --dry-run
    assert_contains "$TEST_ROOT/output" 'Dry run: no target files changed.'
    assert_contains "$TEST_ROOT/output" "delete $agent_dir/agent_rig_explorer.toml"
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    [ "$(find "$destination/.agent-rig/codex/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ] || fail 'Dry run created backups'
    assert_missing "$destination/.agent-rig/codex/.install-lock"
    pass "$scope uninstall dry run previews removals without changing files or backups"

    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
    assert_contains "$TEST_ROOT/output" 'Uninstalled successfully.'
    backup=$(sed -n 's/^Backups: //p' "$TEST_ROOT/output")
    [ -n "$backup" ] || fail 'Uninstall should report its backup directory'
    assert_same "$TEST_ROOT/installed-role" "$backup/$agent_dir/agent_rig_explorer.toml"
    assert_same "$TEST_ROOT/installed-instructions" "$backup/AGENTS.md"
    assert_same "$TEST_ROOT/manifest" "$backup/.agent-rig/codex/manifest.tsv"
    assert_missing "$backup/$config_rel"
    assert_managed_removed "$destination" "$TEST_ROOT/manifest"
    assert_same "$TEST_ROOT/outside" "$destination/AGENTS.md"
    assert_same "$TEST_ROOT/config" "$destination/$config_rel"
    assert_same "$TEST_ROOT/user-role" "$destination/$agent_dir/explorer.toml"
    assert_same "$TEST_ROOT/custom-workflow" "$destination/.agent-rig/codex/workflows/custom.md"
    assert_same "$TEST_ROOT/old-backup" "$destination/.agent-rig/codex/backups/history/keep.txt"
    pass "$scope uninstall removes owned content and preserves user files, exact instruction bytes, and backup history"

    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
    assert_contains "$TEST_ROOT/output" 'no files removed.'
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    [ "$(find "$destination/.agent-rig/codex/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2 ] || fail 'Repeat uninstall created backups'
    install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset minimal
    assert_file "$destination/$agent_dir/agent_rig_explorer.toml"
    assert_file "$destination/.agent-rig/codex/manifest.tsv"
    assert_same "$TEST_ROOT/config" "$destination/$config_rel"
    assert_same "$TEST_ROOT/user-role" "$destination/$agent_dir/explorer.toml"
    pass "$scope repeat uninstall is a no-op and reinstall works with preserved user setup"

    for preset in minimal backend security; do
        destination=$TEST_ROOT/$scope-$preset
        mkdir "$destination"
        install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset "$preset"
        cp "$destination/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/manifest"
        uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
        assert_managed_removed "$destination" "$TEST_ROOT/manifest"
        [ ! -s "$destination/AGENTS.md" ] || fail 'Generated instruction file still has Rig content'
        assert_same "$SOURCE_ROOT/providers/codex/templates/config.toml" "$destination/$config_rel"
        pass "$scope $preset removal follows the manifest and keeps generated configuration"
    done

    destination=$TEST_ROOT/$scope-modified
    mkdir "$destination"
    install_scoped "$SOURCE_ROOT" "$destination" "$scope"
    cp "$destination/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/manifest"
    printf '\n# My role customization\n' >> "$destination/$agent_dir/agent_rig_explorer.toml"
    printf '\nMy workflow customization\n' >> "$destination/.agent-rig/codex/workflows/feature.md"
    sed 's/^# Agent Rig$/# My customized Rig/' "$destination/AGENTS.md" > "$TEST_ROOT/edited-block"
    cat "$TEST_ROOT/edited-block" > "$destination/AGENTS.md"
    printf '\nKeep this suffix.' >> "$destination/AGENTS.md"
    printf '\nKeep this suffix.' > "$TEST_ROOT/outside"
    cp "$destination/$agent_dir/agent_rig_explorer.toml" "$TEST_ROOT/edited-role"
    cp "$destination/.agent-rig/codex/workflows/feature.md" "$TEST_ROOT/edited-workflow"
    cp "$destination/AGENTS.md" "$TEST_ROOT/edited-instructions"
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    reject_uninstall "$SOURCE_ROOT" "$destination" "$scope"
    assert_contains "$TEST_ROOT/output" "$agent_dir/agent_rig_explorer.toml (locally modified"
    assert_contains "$TEST_ROOT/output" '.agent-rig/codex/workflows/feature.md (locally modified'
    assert_contains "$TEST_ROOT/output" 'AGENTS.md (managed section locally modified)'
    assert_contains "$TEST_ROOT/output" '--remove-modified'
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    assert_missing "$destination/.agent-rig/codex/backups"
    pass "$scope removal protects modified roles, workflows, and instructions before writing"

    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope" --remove-modified --dry-run
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    assert_missing "$destination/.agent-rig/codex/backups"
    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope" --remove-modified
    find_backup "$destination"
    assert_same "$TEST_ROOT/edited-role" "$backup/$agent_dir/agent_rig_explorer.toml"
    assert_same "$TEST_ROOT/edited-workflow" "$backup/.agent-rig/codex/workflows/feature.md"
    assert_same "$TEST_ROOT/edited-instructions" "$backup/AGENTS.md"
    assert_same "$TEST_ROOT/outside" "$destination/AGENTS.md"
    assert_managed_removed "$destination" "$TEST_ROOT/manifest"
    pass "$scope explicit removal backs up local changes and preserves surrounding instructions"

    destination=$TEST_ROOT/$scope-override
    mkdir "$destination"
    printf '# Fallback instructions\n' > "$destination/AGENTS.md"
    printf '# Active override without a final newline' > "$destination/AGENTS.override.md"
    cp "$destination/AGENTS.md" "$TEST_ROOT/fallback"
    cp "$destination/AGENTS.override.md" "$TEST_ROOT/override"
    printf '\n\n' >> "$TEST_ROOT/override"
    install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset minimal
    assert_contains "$destination/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.override.md\t')"
    cp "$destination/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/manifest"
    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
    assert_same "$TEST_ROOT/fallback" "$destination/AGENTS.md"
    assert_same "$TEST_ROOT/override" "$destination/AGENTS.override.md"
    assert_managed_removed "$destination" "$TEST_ROOT/manifest"
    pass "$scope uninstall strips the tracked override and preserves fallback instructions"

    destination=$TEST_ROOT/$scope-new-override
    mkdir "$destination"
    install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset minimal
    printf '# Newly active user override\n' > "$destination/AGENTS.override.md"
    cp "$destination/AGENTS.override.md" "$TEST_ROOT/override"
    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
    assert_same "$TEST_ROOT/override" "$destination/AGENTS.override.md"
    [ ! -s "$destination/AGENTS.md" ] || fail 'Inactive tracked instruction section remained'
    pass "$scope uninstall follows the recorded instruction path even after another override becomes active"

    for variant in missing-file missing-block; do
        destination=$TEST_ROOT/$scope-$variant
        mkdir "$destination"
        install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset minimal
        cp "$destination/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/manifest"
        rm "$destination/$agent_dir/agent_rig_explorer.toml" "$destination/.agent-rig/codex/workflows/feature.md"
        if [ "$variant" = missing-file ]; then
            rm "$destination/AGENTS.md"
        else
            printf '# Already removed Rig; keep this file.' > "$destination/AGENTS.md"
            cp "$destination/AGENTS.md" "$TEST_ROOT/replacement"
        fi
        uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
        assert_managed_removed "$destination" "$TEST_ROOT/manifest"
        if [ "$variant" = missing-file ]; then
            assert_missing "$destination/AGENTS.md"
        else
            assert_same "$TEST_ROOT/replacement" "$destination/AGENTS.md"
        fi
        pass "$scope removal accepts already missing files and $variant instructions"
    done
done

project=$TEST_ROOT/duplicate-section
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
cp "$project/AGENTS.md" "$project/AGENTS.override.md"
printf '\nKeep fallback.' >> "$project/AGENTS.md"
printf '\nKeep override.' >> "$project/AGENTS.override.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject_uninstall "$SOURCE_ROOT" "$project" project
assert_contains "$TEST_ROOT/output" 'AGENTS.override.md (unmanaged marked section)'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
uninstall_ok "$SOURCE_ROOT" "$project" project --remove-modified
printf '\nKeep fallback.' > "$TEST_ROOT/fallback"
printf '\nKeep override.' > "$TEST_ROOT/override"
assert_same "$TEST_ROOT/fallback" "$project/AGENTS.md"
assert_same "$TEST_ROOT/override" "$project/AGENTS.override.md"
find_backup "$project"
assert_file "$backup/AGENTS.md"
assert_file "$backup/AGENTS.override.md"
pass 'Additional Rig-marked sections require explicit removal and both instruction files are backed up'

project=$TEST_ROOT/malformed-markers
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
sed '/<!-- agent-rig:end -->/d' "$project/AGENTS.md" > "$TEST_ROOT/malformed"
cp "$TEST_ROOT/malformed" "$project/AGENTS.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject_uninstall "$SOURCE_ROOT" "$project" project --remove-modified
assert_contains "$TEST_ROOT/output" 'Malformed or duplicate Agent Rig markers'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$project/.agent-rig/codex/backups"
pass 'Explicit removal cannot bypass malformed markers or remove surrounding user content'

project=$TEST_ROOT/no-manifest
mkdir -p "$project/.codex/agents"
printf '# Untracked role\n' > "$project/.codex/agents/agent_rig_explorer.toml"
printf '<!-- agent-rig:begin -->\nUntracked section\n<!-- agent-rig:end -->\n' > "$project/AGENTS.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
uninstall_ok "$SOURCE_ROOT" "$project" project --remove-modified
assert_contains "$TEST_ROOT/output" 'No install manifest found'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$project/.agent-rig"
pass 'Without a manifest, uninstall does not guess ownership or remove untracked content'

codex_home="$TEST_ROOT/missing-global-parent/codex home"
uninstall_ok "$SOURCE_ROOT" "$codex_home" global
assert_contains "$TEST_ROOT/output" 'no files removed.'
assert_missing "$TEST_ROOT/missing-global-parent"
pass 'Uninstall does not create a missing Codex home or its parents'

test_user_home=$TEST_ROOT/fallback-user-home
env -u CODEX_HOME HOME="$test_user_home" bash "$SOURCE_ROOT/bin/agent-rig" install --global --preset minimal > "$TEST_ROOT/output" 2>&1 || fail 'HOME fallback install failed'
env -u CODEX_HOME HOME="$test_user_home" bash "$SOURCE_ROOT/bin/agent-rig" uninstall --global > "$TEST_ROOT/output" 2>&1 || fail 'HOME fallback uninstall failed'
assert_missing "$test_user_home/.codex/agents/agent_rig_explorer.toml"
assert_missing "$test_user_home/.codex/.agent-rig/codex/manifest.tsv"
assert_file "$test_user_home/.codex/config.toml"
pass 'Global uninstall falls back to HOME/.codex when CODEX_HOME is unset'

for scope in project global; do
    destination=$TEST_ROOT/$scope-invalid-manifest
    mkdir "$destination"
    install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset minimal
    cp "$destination/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/valid-manifest"
    printf 'file\t../external-file\t0\t0\n' >> "$destination/.agent-rig/codex/manifest.tsv"
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    reject_uninstall "$SOURCE_ROOT" "$destination" "$scope" --remove-modified
    assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    assert_missing "$destination/.agent-rig/codex/backups"
    cp "$TEST_ROOT/valid-manifest" "$destination/.agent-rig/codex/manifest.tsv"
    if [ "$scope" = global ]; then wrong_scope=project; else wrong_scope=global; fi
    reject_uninstall "$SOURCE_ROOT" "$destination" "$wrong_scope"
    assert_contains "$TEST_ROOT/output" 'Installation scope differs from the manifest'
    assert_same "$TEST_ROOT/valid-manifest" "$destination/.agent-rig/codex/manifest.tsv"
    pass "$scope uninstall rejects unsafe manifest paths and the wrong installation scope"
done

project=$TEST_ROOT/symlink-file
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
external=$TEST_ROOT/external-file
printf 'External content\n' > "$external"
cp "$external" "$TEST_ROOT/external-original"
rm "$project/.codex/agents/agent_rig_explorer.toml"
ln -s "$external" "$project/.codex/agents/agent_rig_explorer.toml"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject_uninstall "$SOURCE_ROOT" "$project" project --remove-modified
assert_contains "$TEST_ROOT/output" 'Destination is a symlink'
assert_same "$TEST_ROOT/external-original" "$external"
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
ln -s "$project" "$TEST_ROOT/linked-project"
reject_uninstall "$SOURCE_ROOT" "$TEST_ROOT/linked-project" project
assert_contains "$TEST_ROOT/output" 'Target directory is a symlink'
pass 'Uninstall rejects symlink files and target directories without touching external data'

project=$TEST_ROOT/legacy-install
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
printf 'agent-rig-manifest\t1\npreset\tminimal\n' > "$TEST_ROOT/legacy-manifest"
for name in explorer implementer tester reviewer; do
    mv "$project/.codex/agents/agent_rig_$name.toml" "$project/.codex/agents/$name.toml"
    read -r crc bytes < <(cksum < "$project/.codex/agents/$name.toml")
    printf 'file\t.codex/agents/%s.toml\t%s\t%s\n' "$name" "$crc" "$bytes" >> "$TEST_ROOT/legacy-manifest"
done
awk -F '\t' '$1 == "block" || ($1 == "file" && $2 ~ /^\.agent-rig\//)' "$project/.agent-rig/codex/manifest.tsv" >> "$TEST_ROOT/legacy-manifest"
cp "$TEST_ROOT/legacy-manifest" "$project/.agent-rig/codex/manifest.tsv"
uninstall_ok "$SOURCE_ROOT" "$project" project
assert_managed_removed "$project" "$TEST_ROOT/legacy-manifest"
pass 'Legacy project manifests without scope remove their recorded generic roles'

rig=$TEST_ROOT/source-independent
fixture "$rig"
project=$TEST_ROOT/source-independent-project
mkdir "$project"
install "$rig" "$project" --preset minimal
cp "$project/.agent-rig/codex/manifest.tsv" "$TEST_ROOT/manifest"
rm -rf "$rig/providers/codex/agents" "$rig/providers/codex/workflows" "$rig/providers/codex/presets" "$rig/providers/codex/templates"
uninstall_ok "$rig" "$project" project
assert_managed_removed "$project" "$TEST_ROOT/manifest"
pass 'Uninstall depends on the recorded manifest and works without source templates or presets'

project=$TEST_ROOT/locked
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
mkdir "$project/.agent-rig/codex/.install-lock"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject_uninstall "$SOURCE_ROOT" "$project" project
assert_contains "$TEST_ROOT/output" 'Another Agent Rig operation holds'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
[ -d "$project/.agent-rig/codex/.install-lock" ] || fail 'Uninstall removed another operation lock'
assert_missing "$project/.agent-rig/codex/backups"
pass 'Uninstall respects the shared installation lock'

# A role edited after its checksum was captured must survive the pending removal.
project=$TEST_ROOT/preflight-change
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
cp "$project/AGENTS.md" "$TEST_ROOT/original-instructions"
cp "$project/.codex/agents/agent_rig_explorer.toml" "$TEST_ROOT/concurrent-role"
printf '\n# Concurrent customization\n' >> "$TEST_ROOT/concurrent-role"
mkdir "$TEST_ROOT/changing-bin"
cat > "$TEST_ROOT/changing-bin/dd" <<'EOF'
#!/usr/bin/env bash
"$AGENT_RIG_REAL_DD" "$@" || exit "$?"
if [ ! -f "$AGENT_RIG_CHANGE_ONCE" ]; then
    printf '\n# Concurrent customization\n' >> "$AGENT_RIG_CHANGE_PATH"
    : > "$AGENT_RIG_CHANGE_ONCE"
fi
EOF
chmod +x "$TEST_ROOT/changing-bin/dd"
if env PATH="$TEST_ROOT/changing-bin:$PATH" AGENT_RIG_REAL_DD="$(command -v dd)" AGENT_RIG_CHANGE_PATH="$project/.codex/agents/agent_rig_explorer.toml" AGENT_RIG_CHANGE_ONCE="$TEST_ROOT/changed-once" bash "$SOURCE_ROOT/bin/agent-rig" uninstall --target "$project" > "$TEST_ROOT/output" 2>&1; then
    fail 'A destination changed during preflight should stop uninstall'
fi
assert_contains "$TEST_ROOT/output" 'Destination changed during preflight: .codex/agents/agent_rig_explorer.toml'
assert_same "$TEST_ROOT/concurrent-role" "$project/.codex/agents/agent_rig_explorer.toml"
assert_same "$TEST_ROOT/original-instructions" "$project/AGENTS.md"
assert_file "$project/.codex/agents/agent_rig_tester.toml"
assert_file "$project/.agent-rig/codex/manifest.tsv"
assert_missing "$project/.agent-rig/codex/backups"
assert_missing "$project/.agent-rig/codex/.install-lock"
pass 'A concurrent role edit stops removal before writing and preserves the edit'

# Fail the final deletion after roles, workflows, and instructions were changed.
mkdir "$TEST_ROOT/failing-bin"
cat > "$TEST_ROOT/failing-bin/rm" <<'EOF'
#!/usr/bin/env bash
for argument; do
    if [ "$argument" = "$AGENT_RIG_FAIL_PATH" ] && [ ! -f "$AGENT_RIG_FAIL_ONCE" ]; then
        : > "$AGENT_RIG_FAIL_ONCE"
        printf 'Injected delete failure\n' >&2
        exit 1
    fi
done
exec "$AGENT_RIG_REAL_RM" "$@"
EOF
chmod +x "$TEST_ROOT/failing-bin/rm"
for scope in project global; do
    destination=$TEST_ROOT/$scope-rollback
    mkdir "$destination"
    install_scoped "$SOURCE_ROOT" "$destination" "$scope" --preset minimal
    chmod 640 "$destination/AGENTS.md"
    cp -p "$destination/AGENTS.md" "$TEST_ROOT/original-instructions"
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    if [ "$scope" = global ]; then scope_args=(--global); else scope_args=(--target "$destination"); fi
    if env CODEX_HOME="$destination" PATH="$TEST_ROOT/failing-bin:$PATH" AGENT_RIG_REAL_RM="$(command -v rm)" AGENT_RIG_FAIL_PATH="$destination/.agent-rig/codex/manifest.tsv" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/$scope-failed-once" bash "$SOURCE_ROOT/bin/agent-rig" uninstall "${scope_args[@]}" > "$TEST_ROOT/output" 2>&1; then
        fail 'Injected delete failure should fail uninstall'
    fi
    assert_contains "$TEST_ROOT/output" 'Injected delete failure'
    assert_contains "$TEST_ROOT/output" 'restoring changed files'
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    [ "$(ls -l "$destination/AGENTS.md" | awk '{print $1}')" = "$(ls -l "$TEST_ROOT/original-instructions" | awk '{print $1}')" ] || fail 'Rollback changed file permissions'
    assert_missing "$destination/.agent-rig/codex/.install-lock"
    [ -z "$(find "$destination" -name '.agent-rig-write.*' -o -name '.agent-rig-restore.*')" ] || fail 'Uninstall leaked temporary files'
    find_backup "$destination"
    assert_same "$TEST_ROOT/original-instructions" "$backup/AGENTS.md"
    uninstall_ok "$SOURCE_ROOT" "$destination" "$scope"
    assert_missing "$destination/.agent-rig/codex/manifest.tsv"
    pass "$scope mid-uninstall failure restores deleted files, instruction bytes, permissions, and the manifest"
done

project=$TEST_ROOT/invalid-options
mkdir "$project"
reject_uninstall "$SOURCE_ROOT" "$project" project --preset full
assert_contains "$TEST_ROOT/output" '--preset is only supported by install'
reject_uninstall "$SOURCE_ROOT" "$project" project --replace-modified
assert_contains "$TEST_ROOT/output" 'Use --remove-modified with uninstall'
reject "$SOURCE_ROOT" "$project" --remove-modified
assert_contains "$TEST_ROOT/output" '--remove-modified is only supported by uninstall'
reject_uninstall "$SOURCE_ROOT" "$project" project --global
assert_contains "$TEST_ROOT/output" '--global and --target are mutually exclusive'
reject_uninstall "$SOURCE_ROOT" "$TEST_ROOT/missing-project" project
assert_contains "$TEST_ROOT/output" 'Target directory does not exist'
reject_uninstall "$SOURCE_ROOT" "$SOURCE_ROOT" project
assert_contains "$TEST_ROOT/output" 'source checkout'
if bash "$SOURCE_ROOT/bin/agent-rig" uninstall > "$TEST_ROOT/output" 2>&1; then fail 'Uninstall needs an explicit destination'; fi
assert_contains "$TEST_ROOT/output" '--target or --global is required'
bash "$SOURCE_ROOT/bin/agent-rig" uninstall --help > "$TEST_ROOT/output"
assert_contains "$TEST_ROOT/output" 'uninstall --global'
assert_contains "$TEST_ROOT/output" '--remove-modified'
[ -z "$(find "$project" -mindepth 1 -print)" ] || fail 'Invalid options created destination files'
pass 'Uninstall requires an explicit valid destination and rejects install-only flags'

printf '\nAll %s uninstall checks passed.\n' "$passed"
