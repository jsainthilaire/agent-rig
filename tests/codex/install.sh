#!/usr/bin/env bash
# Shared test support is source-controlled; no destination data is sourced.
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/../lib.sh"

# Source references and all public preset memberships.
for preset in minimal backend security full; do
    project=$TEST_ROOT/preset-$preset
    mkdir "$project"
    install "$SOURCE_ROOT" "$project" --preset "$preset"
    case $preset in
        minimal) expected_agents='explorer implementer tester reviewer'; expected_workflows='feature bug quick' ;;
        backend) expected_agents='explorer implementer database tester reviewer debugger'; expected_workflows='feature bug review quick' ;;
        security) expected_agents='explorer security reviewer tester debugger'; expected_workflows='security review bug quick' ;;
        full) expected_agents='explorer implementer database tester reviewer debugger security'; expected_workflows='feature bug review security quick' ;;
    esac
    agent_count=0
    workflow_count=0
    for name in $expected_agents; do
        assert_same "$SOURCE_ROOT/providers/codex/agents/$name.toml" "$project/.codex/agents/agent_rig_$name.toml"
        assert_contains "$project/.codex/agents/agent_rig_$name.toml" "name = \"agent_rig_$name\""
        assert_contains "$project/.codex/agents/agent_rig_$name.toml" 'developer_instructions = """'
        assert_contains "$project/AGENTS.md" "${name}: \`agent_rig_${name}\`"
        assert_missing "$project/.codex/agents/$name.toml"
        grep -Eq '^model = "[^"]+"$' "$project/.codex/agents/agent_rig_$name.toml" || fail "Missing model for $name"
        grep -Eq '^model_reasoning_effort = "(low|medium|high|xhigh|max)"$' "$project/.codex/agents/agent_rig_$name.toml" || fail "Missing or invalid effort for $name"
        agent_count=$((agent_count + 1))
    done
    for name in $expected_workflows; do
        assert_same "$SOURCE_ROOT/providers/codex/workflows/$name.md" "$project/.agent-rig/codex/workflows/$name.md"
        assert_contains "$project/AGENTS.md" "@${name}"
        workflow_count=$((workflow_count + 1))
    done
    actual=$(find "$project/.codex/agents" -type f | wc -l)
    [ "$actual" -eq "$agent_count" ] || fail "Wrong agent count for $preset"
    actual=$(find "$project/.agent-rig/codex/workflows" -type f | wc -l)
    [ "$actual" -eq "$workflow_count" ] || fail "Wrong workflow count for $preset"
    assert_same "$SOURCE_ROOT/providers/codex/templates/config.toml" "$project/.codex/config.toml"
    assert_contains "$project/.agent-rig/codex/manifest.tsv" "$(printf 'preset\t%s' "$preset")"
    assert_missing "$project/.agent-rig/codex/.install-lock"
    pass "Clean $preset installation and exact membership"
done

project=$TEST_ROOT/default
mkdir "$project"
install "$SOURCE_ROOT" "$project"
assert_contains "$project/AGENTS.md" 'Installed preset: **full**'
assert_same "$TEST_ROOT/preset-full/.agent-rig/codex/manifest.tsv" "$project/.agent-rig/codex/manifest.tsv"
fingerprint_tree "$project" > "$TEST_ROOT/before"
install "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" 'Already up to date.'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$project/.agent-rig/codex/backups"
pass 'Default full preset has exact membership and repeat installation is idempotent'

assert_contains "$project/AGENTS.md" 'Without a leading workflow alias, Agent Rig is inactive.'
assert_contains "$project/AGENTS.md" 'a previous alias does not activate a later unprefixed request.'
assert_contains "$project/AGENTS.md" 'All rules and installed-role lists below apply only within an explicitly activated Agent Rig request.'
activation_line=$(awk '/^## Activation:/ { print NR; exit }' "$project/AGENTS.md")
ownership_line=$(awk '/^## Root ownership/ { print NR; exit }' "$project/AGENTS.md")
[ "$activation_line" -lt "$ownership_line" ] || fail 'Activation must precede orchestration rules'
if grep -Eq '^[[:space:]]*[^#[:space:]]' "$project/.codex/config.toml"; then fail 'Default config must not override user settings'; fi
for name in explorer implementer database tester reviewer debugger security; do
    assert_contains "$SOURCE_ROOT/providers/codex/agents/$name.toml" 'within an explicitly activated Agent Rig request.'
done
pass 'Installed activation gate scopes Rig rules to explicitly tagged requests and config inherits user settings'

project=$TEST_ROOT/existing-roles
mkdir -p "$project/.codex/agents"
printf 'name = "explorer"\ndescription = "User explorer"\ndeveloper_instructions = "Follow my setup"\n' > "$project/.codex/agents/explorer.toml"
printf 'name = "reviewer"\ndescription = "User reviewer"\ndeveloper_instructions = "Follow my setup"\n' > "$project/.codex/agents/reviewer.toml"
cp "$project/.codex/agents/explorer.toml" "$TEST_ROOT/user-explorer"
cp "$project/.codex/agents/reviewer.toml" "$TEST_ROOT/user-reviewer"
install "$SOURCE_ROOT" "$project"
assert_same "$TEST_ROOT/user-explorer" "$project/.codex/agents/explorer.toml"
assert_same "$TEST_ROOT/user-reviewer" "$project/.codex/agents/reviewer.toml"
assert_file "$project/.codex/agents/agent_rig_explorer.toml"
assert_file "$project/.codex/agents/agent_rig_reviewer.toml"
assert_missing "$project/.agent-rig/codex/backups"
pass 'Namespaced Rig agents coexist with unchanged user explorer and reviewer roles'

# Construct the previous install format with generic agent names and a valid
# manifest. Updating must retire those managed names, rather than leave shadows.
project=$TEST_ROOT/legacy-namespace
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
printf 'agent-rig-manifest\t1\npreset\tminimal\n' > "$TEST_ROOT/legacy-manifest"
for name in explorer implementer tester reviewer; do
    sed 's/name = "agent_rig_/name = "/' "$project/.codex/agents/agent_rig_$name.toml" > "$project/.codex/agents/$name.toml"
    rm "$project/.codex/agents/agent_rig_$name.toml"
    read -r crc bytes < <(cksum < "$project/.codex/agents/$name.toml")
    printf 'file\t.codex/agents/%s.toml\t%s\t%s\n' "$name" "$crc" "$bytes" >> "$TEST_ROOT/legacy-manifest"
done
for name in feature bug quick; do
    read -r crc bytes < <(cksum < "$project/.agent-rig/codex/workflows/$name.md")
    printf 'file\t.agent-rig/codex/workflows/%s.md\t%s\t%s\n' "$name" "$crc" "$bytes" >> "$TEST_ROOT/legacy-manifest"
done
read -r crc bytes < <(cksum < "$project/AGENTS.md")
printf 'block\tAGENTS.md\t%s\t%s\n' "$crc" "$bytes" >> "$TEST_ROOT/legacy-manifest"
cp "$TEST_ROOT/legacy-manifest" "$project/.agent-rig/codex/manifest.tsv"
cp "$project/.codex/agents/explorer.toml" "$TEST_ROOT/legacy-explorer"
install "$SOURCE_ROOT" "$project" --preset minimal
for name in explorer implementer tester reviewer; do
    assert_missing "$project/.codex/agents/$name.toml"
    assert_same "$SOURCE_ROOT/providers/codex/agents/$name.toml" "$project/.codex/agents/agent_rig_$name.toml"
done
find_backup "$project"
assert_same "$TEST_ROOT/legacy-explorer" "$backup/.codex/agents/explorer.toml"
pass 'Earlier managed generic roles migrate to the Rig namespace with backups'

project=$TEST_ROOT/recreate-files
mkdir "$project"
install "$SOURCE_ROOT" "$project"
rm "$project/.codex/agents/agent_rig_explorer.toml" "$project/.agent-rig/codex/workflows/bug.md"
printf '\n# Project configuration customization\n[agents]\ndefault_subagent_reasoning_effort = "high"\n' >> "$project/.codex/config.toml"
cp "$project/.codex/config.toml" "$TEST_ROOT/custom-config"
install "$SOURCE_ROOT" "$project"
assert_same "$SOURCE_ROOT/providers/codex/agents/explorer.toml" "$project/.codex/agents/agent_rig_explorer.toml"
assert_same "$SOURCE_ROOT/providers/codex/workflows/bug.md" "$project/.agent-rig/codex/workflows/bug.md"
assert_same "$TEST_ROOT/custom-config" "$project/.codex/config.toml"
pass 'Missing managed files are recreated and edited Codex configuration is preserved'

project=$TEST_ROOT/dry-run
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset full --dry-run
assert_contains "$TEST_ROOT/output" 'Dry run: no target files changed.'
[ -z "$(find "$project" -mindepth 1 -print)" ] || fail 'Dry run created target objects'
pass 'Dry run leaves an empty target untouched'

project="$TEST_ROOT/project with spaces"
mkdir -p "$project/.codex"
printf '# Project conventions\nUse the existing API.\nNo trailing newline' > "$project/AGENTS.md"
printf '# Keep this config\nmodel = "project-model"\n[agents]\nenabled = false\n' > "$project/.codex/config.toml"
cp "$project/AGENTS.md" "$TEST_ROOT/original-agents"
cp "$project/.codex/config.toml" "$TEST_ROOT/original-config"
install "$SOURCE_ROOT" "$project" --preset backend
assert_same "$TEST_ROOT/original-config" "$project/.codex/config.toml"
size=$(wc -c < "$TEST_ROOT/original-agents")
dd if="$project/AGENTS.md" of="$TEST_ROOT/prefix" bs=1 count="$size" 2>/dev/null
assert_same "$TEST_ROOT/original-agents" "$TEST_ROOT/prefix"
assert_contains "$TEST_ROOT/output" 'Existing .codex/config.toml preserved byte-for-byte.'
find_backup "$project"
assert_same "$backup/AGENTS.md" "$TEST_ROOT/original-agents"
assert_missing "$backup/.codex/config.toml"
pass 'Paths with spaces, existing instructions, configuration, and initial backups'

# Exact preservation around a section, including multibyte text and EOF style.
project=$TEST_ROOT/outside-section
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
cp "$project/AGENTS.md" "$TEST_ROOT/old-block"
printf 'Próject-specific prefix\n\n' > "$TEST_ROOT/custom-prefix"
printf '\nKeep this suffix without a newline: 日本語' > "$TEST_ROOT/custom-suffix"
cat "$TEST_ROOT/custom-prefix" "$TEST_ROOT/old-block" "$TEST_ROOT/custom-suffix" > "$project/AGENTS.md"
install "$SOURCE_ROOT" "$project" --preset full
size=$(wc -c < "$TEST_ROOT/custom-prefix")
dd if="$project/AGENTS.md" of="$TEST_ROOT/prefix" bs=1 count="$size" 2>/dev/null
assert_same "$TEST_ROOT/custom-prefix" "$TEST_ROOT/prefix"
size=$(wc -c < "$TEST_ROOT/custom-suffix")
tail -c "$size" "$project/AGENTS.md" > "$TEST_ROOT/suffix"
assert_same "$TEST_ROOT/custom-suffix" "$TEST_ROOT/suffix"
pass 'Preset switch preserves bytes outside the managed instructions'

rig=$TEST_ROOT/updated-rig
fixture "$rig"
project=$TEST_ROOT/update
mkdir "$project"
install "$rig" "$project"
cp "$project/.codex/agents/agent_rig_explorer.toml" "$TEST_ROOT/old-explorer"
printf '\n# Updated role\n' >> "$rig/providers/codex/agents/explorer.toml"
printf '\nUpdated workflow.\n' >> "$rig/providers/codex/workflows/feature.md"
printf '\nUpdated root guidance.\n' >> "$rig/providers/codex/templates/AGENTS.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
install "$rig" "$project" --dry-run
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install "$rig" "$project"
assert_same "$rig/providers/codex/agents/explorer.toml" "$project/.codex/agents/agent_rig_explorer.toml"
assert_same "$rig/providers/codex/workflows/feature.md" "$project/.agent-rig/codex/workflows/feature.md"
assert_contains "$project/AGENTS.md" 'Updated root guidance.'
find_backup "$project"
assert_same "$TEST_ROOT/old-explorer" "$backup/.codex/agents/agent_rig_explorer.toml"
pass 'Updates refresh unchanged content and back up previous versions'

project=$TEST_ROOT/local-edits
mkdir "$project"
install "$SOURCE_ROOT" "$project"
printf '\n# Local agent customization\n' >> "$project/.codex/agents/agent_rig_explorer.toml"
printf '\nLocal workflow customization.\n' >> "$project/.agent-rig/codex/workflows/feature.md"
sed 's/## Root ownership/## Local root ownership/' "$project/AGENTS.md" > "$TEST_ROOT/edited-agents"
cp "$TEST_ROOT/edited-agents" "$project/AGENTS.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" '.codex/agents/agent_rig_explorer.toml (locally modified)'
assert_contains "$TEST_ROOT/output" '.agent-rig/codex/workflows/feature.md (locally modified)'
assert_contains "$TEST_ROOT/output" 'AGENTS.md (managed section locally modified)'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
cp "$project/.codex/agents/agent_rig_explorer.toml" "$TEST_ROOT/local-explorer"
install "$SOURCE_ROOT" "$project" --replace-modified
find_backup "$project"
assert_same "$TEST_ROOT/local-explorer" "$backup/.codex/agents/agent_rig_explorer.toml"
assert_same "$TEST_ROOT/edited-agents" "$backup/AGENTS.md"
assert_same "$SOURCE_ROOT/providers/codex/agents/explorer.toml" "$project/.codex/agents/agent_rig_explorer.toml"
pass 'All local modifications are reported and explicit replacement is backed up'

project=$TEST_ROOT/switch
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset full
printf '\n# Unrelated role\n' > "$project/.codex/agents/custom.toml"
printf '\n# Customized database role\n' >> "$project/.codex/agents/agent_rig_database.toml"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$SOURCE_ROOT" "$project" --preset minimal
assert_contains "$TEST_ROOT/output" 'locally modified; removed by preset switch'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
cp "$project/.codex/agents/agent_rig_database.toml" "$TEST_ROOT/local-database"
install "$SOURCE_ROOT" "$project" --preset minimal --replace-modified
assert_missing "$project/.codex/agents/agent_rig_database.toml"
assert_missing "$project/.codex/agents/agent_rig_debugger.toml"
assert_missing "$project/.codex/agents/agent_rig_security.toml"
assert_missing "$project/.agent-rig/codex/workflows/review.md"
assert_missing "$project/.agent-rig/codex/workflows/security.md"
assert_file "$project/.codex/agents/custom.toml"
find_backup "$project"
assert_same "$TEST_ROOT/local-database" "$backup/.codex/agents/agent_rig_database.toml"
pass 'Preset switch removes only managed obsolete files and protects local edits'

project=$TEST_ROOT/collision
mkdir -p "$project/.codex/agents"
printf 'name = "agent_rig_explorer"\n# Existing different role\n' > "$project/.codex/agents/agent_rig_explorer.toml"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" 'unmanaged destination collision'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install "$SOURCE_ROOT" "$project" --replace-modified
find_backup "$project"
assert_contains "$backup/.codex/agents/agent_rig_explorer.toml" 'Existing different role'
pass 'Unmanaged role collisions require explicit backed-up replacement'

project=$TEST_ROOT/adopt-identical
mkdir -p "$project/.codex/agents"
cp "$SOURCE_ROOT/providers/codex/agents/explorer.toml" "$project/.codex/agents/agent_rig_explorer.toml"
install "$SOURCE_ROOT" "$project"
assert_missing "$project/.agent-rig/codex/backups"
pass 'Identical unmanaged copies can be adopted without replacement'

rig=$TEST_ROOT/matching-update-rig
fixture "$rig"
project=$TEST_ROOT/matching-update
mkdir "$project"
install "$rig" "$project"
printf '\n# Updated role\n' >> "$rig/providers/codex/agents/explorer.toml"
printf '\nUpdated workflow guidance.\n' >> "$rig/providers/codex/workflows/feature.md"
printf '\nUpdated root guidance.\n' >> "$rig/providers/codex/templates/AGENTS.md"
expected_project=$TEST_ROOT/matching-update-expected
mkdir "$expected_project"
install "$rig" "$expected_project"
cp "$expected_project/AGENTS.md" "$project/AGENTS.md"
cp "$rig/providers/codex/agents/explorer.toml" "$project/.codex/agents/agent_rig_explorer.toml"
cp "$rig/providers/codex/workflows/feature.md" "$project/.agent-rig/codex/workflows/feature.md"
install "$rig" "$project"
assert_same "$expected_project/.agent-rig/codex/manifest.tsv" "$project/.agent-rig/codex/manifest.tsv"
find_backup "$project"
assert_file "$backup/.agent-rig/codex/manifest.tsv"
assert_missing "$backup/AGENTS.md"
assert_missing "$backup/.codex/agents/agent_rig_explorer.toml"
pass 'Managed files and sections already matching updated sources are adopted without replacement'

project=$TEST_ROOT/removed-section
mkdir "$project"
install "$SOURCE_ROOT" "$project"
printf '# Project instructions only\n' > "$project/AGENTS.md"
reject "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" 'managed section was removed'
assert_contains "$project/AGENTS.md" '# Project instructions only'
install "$SOURCE_ROOT" "$project" --replace-modified
assert_contains "$project/AGENTS.md" '# Project instructions only'
assert_contains "$project/AGENTS.md" '<!-- agent-rig:begin -->'
pass 'A removed managed section is a protected local edit'

for variant in missing-end reversed duplicate inline; do
    project=$TEST_ROOT/markers-$variant
    mkdir "$project"
    case $variant in
        missing-end) printf '<!-- agent-rig:begin -->\n' > "$project/AGENTS.md" ;;
        reversed) printf '<!-- agent-rig:end -->\n<!-- agent-rig:begin -->\n' > "$project/AGENTS.md" ;;
        duplicate) printf '<!-- agent-rig:begin -->\n<!-- agent-rig:end -->\n<!-- agent-rig:begin -->\n<!-- agent-rig:end -->\n' > "$project/AGENTS.md" ;;
        inline) printf 'text <!-- agent-rig:begin -->\n' > "$project/AGENTS.md" ;;
    esac
    cp "$project/AGENTS.md" "$TEST_ROOT/before-agents"
    reject "$SOURCE_ROOT" "$project" --replace-modified
    assert_contains "$TEST_ROOT/output" 'Malformed or duplicate'
    assert_same "$TEST_ROOT/before-agents" "$project/AGENTS.md"
    assert_missing "$project/.agent-rig"
done
pass 'Malformed, reversed, duplicate, and inline markers cannot be overridden'

# An untracked marked block is also a collision.
project=$TEST_ROOT/untracked-section
mkdir "$project"
printf 'prefix\n<!-- agent-rig:begin -->\ncustom section\n<!-- agent-rig:end -->\nsuffix\n' > "$project/AGENTS.md"
reject "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" 'unmanaged marked section'
install "$SOURCE_ROOT" "$project" --replace-modified
assert_contains "$project/AGENTS.md" 'prefix'
assert_contains "$project/AGENTS.md" 'suffix'
pass 'Untracked marked sections are protected while surrounding content survives'

project=$TEST_ROOT/crlf-section
mkdir "$project"
install "$SOURCE_ROOT" "$project"
awk '{ printf "%s\r\n", $0 }' "$project/AGENTS.md" > "$TEST_ROOT/crlf-block"
printf '# Project prefix\r\n\r\n' > "$TEST_ROOT/crlf-prefix"
printf '\r\nProject suffix without a newline' > "$TEST_ROOT/crlf-suffix"
cat "$TEST_ROOT/crlf-prefix" "$TEST_ROOT/crlf-block" "$TEST_ROOT/crlf-suffix" > "$project/AGENTS.md"
cp "$project/AGENTS.md" "$TEST_ROOT/crlf-before"
reject "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" 'managed section locally modified'
assert_same "$TEST_ROOT/crlf-before" "$project/AGENTS.md"
install "$SOURCE_ROOT" "$project" --replace-modified
size=$(wc -c < "$TEST_ROOT/crlf-prefix")
dd if="$project/AGENTS.md" of="$TEST_ROOT/prefix" bs=1 count="$size" 2>/dev/null
assert_same "$TEST_ROOT/crlf-prefix" "$TEST_ROOT/prefix"
size=$(wc -c < "$TEST_ROOT/crlf-suffix")
tail -c "$size" "$project/AGENTS.md" > "$TEST_ROOT/suffix"
assert_same "$TEST_ROOT/crlf-suffix" "$TEST_ROOT/suffix"
find_backup "$project"
assert_same "$TEST_ROOT/crlf-before" "$backup/AGENTS.md"
pass 'CRLF markers are recognized while local edits stay protected and surrounding bytes survive replacement'

project=$TEST_ROOT/project-override
mkdir "$project"
printf '# Fallback instructions\n' > "$project/AGENTS.md"
printf '# Active project override\nNo trailing newline' > "$project/AGENTS.override.md"
cp "$project/AGENTS.md" "$TEST_ROOT/project-fallback"
cp "$project/AGENTS.override.md" "$TEST_ROOT/project-override-prefix"
fingerprint_tree "$project" > "$TEST_ROOT/before"
install "$SOURCE_ROOT" "$project" --dry-run
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install "$SOURCE_ROOT" "$project"
assert_same "$TEST_ROOT/project-fallback" "$project/AGENTS.md"
size=$(wc -c < "$TEST_ROOT/project-override-prefix")
dd if="$project/AGENTS.override.md" of="$TEST_ROOT/prefix" bs=1 count="$size" 2>/dev/null
assert_same "$TEST_ROOT/project-override-prefix" "$TEST_ROOT/prefix"
assert_contains "$project/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.override.md\t')"
assert_contains "$project/AGENTS.override.md" 'Installed preset: **full**'
install "$SOURCE_ROOT" "$project"
assert_contains "$TEST_ROOT/output" 'Already up to date.'
pass 'Project installs use the active override and preserve fallback instructions, including during dry runs'

for variant in empty whitespace; do
    project=$TEST_ROOT/project-$variant-override
    mkdir "$project"
    : > "$project/AGENTS.override.md"
    if [ "$variant" = whitespace ]; then printf ' \t\r\n' > "$project/AGENTS.override.md"; fi
    cp "$project/AGENTS.override.md" "$TEST_ROOT/project-blank-override"
    install "$SOURCE_ROOT" "$project"
    assert_same "$TEST_ROOT/project-blank-override" "$project/AGENTS.override.md"
    assert_contains "$project/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.md\t')"
    pass "Project $variant override stays unchanged while instructions use AGENTS.md"
done

project=$TEST_ROOT/project-override-transition
mkdir "$project"
install "$SOURCE_ROOT" "$project"
cp "$project/AGENTS.md" "$TEST_ROOT/project-old-block"
printf '# Prefix conventions\n\n' > "$TEST_ROOT/project-prefix"
printf '\nSuffix conventions without a newline' > "$TEST_ROOT/project-suffix"
cat "$TEST_ROOT/project-prefix" "$TEST_ROOT/project-old-block" "$TEST_ROOT/project-suffix" > "$project/AGENTS.md"
printf '# New active override\n' > "$project/AGENTS.override.md"
install "$SOURCE_ROOT" "$project" --preset minimal
cat "$TEST_ROOT/project-prefix" "$TEST_ROOT/project-suffix" > "$TEST_ROOT/project-expected-outside"
assert_same "$TEST_ROOT/project-expected-outside" "$project/AGENTS.md"
assert_contains "$project/AGENTS.override.md" 'Installed preset: **minimal**'
assert_contains "$project/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.override.md\t')"
assert_missing "$project/.codex/agents/agent_rig_security.toml"
pass 'A newly active project override moves the managed section and preserves surrounding bytes'

external=$TEST_ROOT/external
mkdir "$external"
printf 'untouched\n' > "$external/config.toml"
cp "$external/config.toml" "$TEST_ROOT/external-original"
for location in .codex .codex/agents .codex/config.toml AGENTS.md AGENTS.override.md .agent-rig .agent-rig/codex/backups .agent-rig/codex/.install-lock .agent-rig/codex/workflows; do
    project=$TEST_ROOT/link-${location//\//-}
    mkdir -p "$project/$(dirname -- "$location")"
    ln -s "$external" "$project/$location"
    reject "$SOURCE_ROOT" "$project" --replace-modified
    assert_contains "$TEST_ROOT/output" 'symlink'
done
project=$TEST_ROOT/target-link
ln -s "$external" "$project"
reject "$SOURCE_ROOT" "$project"
assert_same "$external/config.toml" "$TEST_ROOT/external-original"
pass 'Destination and target symlinks are rejected without touching external files'

project=$TEST_ROOT/bad-manifest
mkdir "$project"
install "$SOURCE_ROOT" "$project"
printf 'agent-rig-manifest\t1\npreset\tminimal\nfile\t../../external/config.toml\t1\t1\nblock\tAGENTS.md\t1\t1\n' > "$project/.agent-rig/codex/manifest.tsv"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$SOURCE_ROOT" "$project" --replace-modified
assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_same "$external/config.toml" "$TEST_ROOT/external-original"
pass 'Invalid manifest paths cannot direct writes outside the target'

for scope in project global; do
    destination=$TEST_ROOT/manifest-unrelated-$scope
    mkdir "$destination"
    if [ "$scope" = project ]; then
        install "$SOURCE_ROOT" "$destination"
        unrelated_path=.codex/agents/custom.toml
    else
        install_global "$SOURCE_ROOT" "$destination"
        unrelated_path=agents/explorer.toml
    fi
    printf '# User-owned role\n' > "$destination/$unrelated_path"
    read -r crc bytes < <(cksum < "$destination/$unrelated_path")
    printf 'file\t%s\t%s\t%s\n' "$unrelated_path" "$crc" "$bytes" >> "$destination/.agent-rig/codex/manifest.tsv"
    fingerprint_tree "$destination" > "$TEST_ROOT/before"
    if [ "$scope" = project ]; then
        reject "$SOURCE_ROOT" "$destination" --replace-modified
    else
        reject_global "$SOURCE_ROOT" "$destination" --replace-modified
    fi
    assert_contains "$TEST_ROOT/output" 'Invalid install manifest'
    fingerprint_tree "$destination" > "$TEST_ROOT/after"
    assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
    pass "The $scope manifest cannot claim unrelated agent files for deletion"
done

project=$TEST_ROOT/locked
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
mkdir "$project/.agent-rig/codex/.install-lock"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$SOURCE_ROOT" "$project" --preset full
assert_contains "$TEST_ROOT/output" 'Another Agent Rig operation holds'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
[ -d "$project/.agent-rig/codex/.install-lock" ] || fail 'Removed another installer lock'
pass 'Concurrent installation lock is respected'

# Change a destination after preflight captured it but before application.
project=$TEST_ROOT/preflight-change
mkdir "$project"
install "$SOURCE_ROOT" "$project" --preset minimal
cp "$project/AGENTS.md" "$TEST_ROOT/concurrent-expected"
printf '\nConcurrent project edit\n' >> "$TEST_ROOT/concurrent-expected"
mkdir "$TEST_ROOT/changing-bin"
cat > "$TEST_ROOT/changing-bin/dd" <<'EOF'
#!/usr/bin/env bash
"$AGENT_RIG_REAL_DD" "$@" || exit "$?"
for argument; do
    if [ "$argument" = "if=$AGENT_RIG_CHANGE_PATH" ] && [ ! -f "$AGENT_RIG_CHANGE_ONCE" ]; then
        printf '\nConcurrent project edit\n' >> "$AGENT_RIG_CHANGE_PATH"
        : > "$AGENT_RIG_CHANGE_ONCE"
    fi
done
EOF
chmod +x "$TEST_ROOT/changing-bin/dd"
if env PATH="$TEST_ROOT/changing-bin:$PATH" AGENT_RIG_REAL_DD="$(command -v dd)" AGENT_RIG_CHANGE_PATH="$project/AGENTS.md" AGENT_RIG_CHANGE_ONCE="$TEST_ROOT/changed-once" bash "$SOURCE_ROOT/bin/agent-rig" install --target "$project" --preset full > "$TEST_ROOT/output" 2>&1; then
    fail 'A destination changed during preflight should stop installation'
fi
assert_contains "$TEST_ROOT/output" 'Destination changed during preflight: AGENTS.md'
assert_same "$project/AGENTS.md" "$TEST_ROOT/concurrent-expected"
assert_missing "$project/.codex/agents/agent_rig_database.toml"
assert_missing "$project/.agent-rig/codex/backups"
assert_missing "$project/.agent-rig/codex/.install-lock"
pass 'A concurrent destination edit stops application and preserves the edit'

# Exercise real mid-apply failure and rollback, rather than only preflight errors.
rig=$TEST_ROOT/failure-rig
fixture "$rig"
project=$TEST_ROOT/rollback
mkdir "$project"
install "$rig" "$project"
for role in explorer implementer tester; do printf '\n# Updated\n' >> "$rig/providers/codex/agents/$role.toml"; done
fingerprint_tree "$project" > "$TEST_ROOT/before"
mkdir "$TEST_ROOT/fake-bin"
cat > "$TEST_ROOT/fake-bin/mv" <<'EOF'
#!/usr/bin/env bash
for destination; do :; done
if [ "$destination" = "$AGENT_RIG_FAIL_PATH" ] && [ ! -f "$AGENT_RIG_FAIL_ONCE" ]; then
    : > "$AGENT_RIG_FAIL_ONCE"
    printf 'Injected write failure\n' >&2
    exit 1
fi
exec "$AGENT_RIG_REAL_MV" "$@"
EOF
chmod +x "$TEST_ROOT/fake-bin/mv"
if env PATH="$TEST_ROOT/fake-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$project/.codex/agents/agent_rig_tester.toml" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/failed-once" bash "$rig/bin/agent-rig" install --target "$project" > "$TEST_ROOT/output" 2>&1; then
    fail 'Injected write failure should fail installation'
fi
assert_contains "$TEST_ROOT/output" 'restoring changed files'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$project/.agent-rig/codex/.install-lock"
[ -z "$(find "$project" -name '.agent-rig-write.*' -print)" ] || fail 'Temporary destination files leaked'
pass 'Mid-apply failure restores originals and cleans up lock and temporary files'

project=$TEST_ROOT/new-install-rollback
mkdir "$project"
if env PATH="$TEST_ROOT/fake-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$project/.agent-rig/codex/manifest.tsv" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/new-failed-once" bash "$SOURCE_ROOT/bin/agent-rig" install --target "$project" > "$TEST_ROOT/output" 2>&1; then
    fail 'Injected failure should fail a new installation'
fi
assert_contains "$TEST_ROOT/output" 'restoring changed files'
[ -z "$(find "$project" -type f -print)" ] || fail 'New installation files remained after rollback'
assert_missing "$project/.agent-rig/codex/.install-lock"
pass 'Failed new installation removes all files created during application'

# Global tests always use disposable Codex homes, never the user's installation.
codex_home="$TEST_ROOT/missing global parent/codex home"
install_global "$SOURCE_ROOT" "$codex_home" --preset full --dry-run
assert_contains "$TEST_ROOT/output" 'Dry run: no target files changed.'
assert_missing "$TEST_ROOT/missing global parent"
pass 'Global dry run leaves a missing Codex home and its parents untouched'

for preset in minimal backend security full; do
    codex_home="$TEST_ROOT/global $preset/codex home"
    install_global "$SOURCE_ROOT" "$codex_home" --preset "$preset"
    for installed_role in "$codex_home"/agents/*.toml; do
        role=${installed_role##*/agent_rig_}
        role=${role%.toml}
        assert_same "$SOURCE_ROOT/providers/codex/agents/$role.toml" "$installed_role"
    done
    project=$TEST_ROOT/preset-$preset
    [ "$(find "$codex_home/agents" -type f | wc -l)" -eq "$(find "$project/.codex/agents" -type f | wc -l)" ] || fail "Wrong global agent count for $preset"
    [ "$(find "$codex_home/.agent-rig/codex/workflows" -type f | wc -l)" -eq "$(find "$project/.agent-rig/codex/workflows" -type f | wc -l)" ] || fail "Wrong global workflow count for $preset"
    assert_same "$SOURCE_ROOT/providers/codex/templates/config.toml" "$codex_home/config.toml"
    assert_contains "$codex_home/.agent-rig/codex/manifest.tsv" "$(printf 'scope\tglobal')"
    assert_contains "$codex_home/AGENTS.md" 'Installation scope: **global**'
    assert_contains "$codex_home/AGENTS.md" "use the project section's preset, role list, and workflow paths."
    assert_contains "$codex_home/AGENTS.md" 'Without a leading workflow alias, Agent Rig is inactive.'
    assert_contains "$codex_home/AGENTS.md" "$codex_home/.agent-rig/codex/workflows/bug.md"
    assert_contains "$codex_home/AGENTS.md" 'read the selected workflow from its path in the installed workflow list below.'
    assert_missing "$codex_home/.codex"
    assert_missing "$codex_home/AGENTS.override.md"
    assert_missing "$codex_home/.agent-rig/codex/.install-lock"
    pass "Global $preset installation creates the Codex-home layout and absolute workflow paths"
done

codex_home="$TEST_ROOT/global full/codex home"
fingerprint_tree "$codex_home" > "$TEST_ROOT/before"
install_global "$SOURCE_ROOT" "$codex_home"
assert_contains "$TEST_ROOT/output" 'Already up to date.'
fingerprint_tree "$codex_home" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$codex_home/.agent-rig/codex/backups"
pass 'Global repeat install is idempotent'

test_user_home=$TEST_ROOT/fallback-user-home
env -u CODEX_HOME HOME="$test_user_home" bash "$SOURCE_ROOT/bin/agent-rig" install --global > "$TEST_ROOT/output" 2>&1 || fail 'Global HOME fallback failed'
assert_file "$test_user_home/.codex/agents/agent_rig_explorer.toml"
assert_file "$test_user_home/.codex/AGENTS.md"
assert_file "$test_user_home/.codex/config.toml"
assert_contains "$test_user_home/.codex/AGENTS.md" 'Installed preset: **full**'
assert_file "$test_user_home/.codex/agents/agent_rig_security.toml"
env CODEX_HOME= HOME="$test_user_home" bash "$SOURCE_ROOT/bin/agent-rig" install --global > "$TEST_ROOT/output" 2>&1 || fail 'Empty CODEX_HOME fallback failed'
assert_contains "$TEST_ROOT/output" 'Already up to date.'
codex_home=$TEST_ROOT/explicit-codex-home
env CODEX_HOME="$codex_home" HOME="$TEST_ROOT/unused-user-home" bash "$SOURCE_ROOT/bin/agent-rig" install --global > "$TEST_ROOT/output" 2>&1 || fail 'Explicit CODEX_HOME failed'
assert_file "$codex_home/agents/agent_rig_explorer.toml"
assert_missing "$TEST_ROOT/unused-user-home"
pass 'Global installation honors CODEX_HOME and falls back to HOME/.codex when unset or empty'

codex_home="$TEST_ROOT/existing codex home"
mkdir -p "$codex_home/agents"
printf 'model = "user-model"\n[agents]\nenabled = false\n' > "$codex_home/config.toml"
printf 'name = "explorer"\ndescription = "My explorer"\ndeveloper_instructions = "Use my setup"\n' > "$codex_home/agents/explorer.toml"
printf '# My global instructions\nKeep my conventions without a final newline' > "$codex_home/AGENTS.md"
cp "$codex_home/config.toml" "$TEST_ROOT/global-config"
cp "$codex_home/agents/explorer.toml" "$TEST_ROOT/global-role"
cp "$codex_home/AGENTS.md" "$TEST_ROOT/global-instructions"
install_global "$SOURCE_ROOT" "$codex_home" --preset backend
assert_same "$TEST_ROOT/global-config" "$codex_home/config.toml"
assert_same "$TEST_ROOT/global-role" "$codex_home/agents/explorer.toml"
size=$(wc -c < "$TEST_ROOT/global-instructions")
dd if="$codex_home/AGENTS.md" of="$TEST_ROOT/prefix" bs=1 count="$size" 2>/dev/null
assert_same "$TEST_ROOT/global-instructions" "$TEST_ROOT/prefix"
assert_contains "$TEST_ROOT/output" 'Existing config.toml preserved byte-for-byte.'
find_backup "$codex_home"
assert_same "$TEST_ROOT/global-instructions" "$backup/AGENTS.md"
assert_missing "$backup/config.toml"
pass 'Global installation preserves user configuration, roles, and instruction bytes with backups'

codex_home=$TEST_ROOT/global-override
mkdir "$codex_home"
printf '# My fallback global instructions\n' > "$codex_home/AGENTS.md"
printf '# My active override\nNo trailing newline' > "$codex_home/AGENTS.override.md"
cp "$codex_home/AGENTS.md" "$TEST_ROOT/fallback-instructions"
cp "$codex_home/AGENTS.override.md" "$TEST_ROOT/override-instructions"
install_global "$SOURCE_ROOT" "$codex_home"
assert_same "$TEST_ROOT/fallback-instructions" "$codex_home/AGENTS.md"
size=$(wc -c < "$TEST_ROOT/override-instructions")
dd if="$codex_home/AGENTS.override.md" of="$TEST_ROOT/prefix" bs=1 count="$size" 2>/dev/null
assert_same "$TEST_ROOT/override-instructions" "$TEST_ROOT/prefix"
assert_contains "$codex_home/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.override.md\t')"
assert_contains "$codex_home/AGENTS.override.md" 'Installed preset: **full**'
find_backup "$codex_home"
assert_same "$TEST_ROOT/override-instructions" "$backup/AGENTS.override.md"
assert_missing "$backup/AGENTS.md"
pass 'A nonempty global AGENTS.override.md receives Rig instructions instead of the shadowed AGENTS.md'

for variant in empty whitespace; do
    codex_home=$TEST_ROOT/global-$variant-override
    mkdir "$codex_home"
    : > "$codex_home/AGENTS.override.md"
    if [ "$variant" = whitespace ]; then printf ' \t\r\n\n' > "$codex_home/AGENTS.override.md"; fi
    cp "$codex_home/AGENTS.override.md" "$TEST_ROOT/blank-override"
    install_global "$SOURCE_ROOT" "$codex_home"
    assert_same "$TEST_ROOT/blank-override" "$codex_home/AGENTS.override.md"
    assert_contains "$codex_home/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.md\t')"
    assert_contains "$codex_home/AGENTS.md" '<!-- agent-rig:begin -->'
    pass "Global $variant override remains unchanged and instructions use AGENTS.md"
done

codex_home=$TEST_ROOT/global-override-transition
install_global "$SOURCE_ROOT" "$codex_home"
printf '# New override conventions\n' > "$codex_home/AGENTS.override.md"
fingerprint_tree "$codex_home" > "$TEST_ROOT/before"
install_global "$SOURCE_ROOT" "$codex_home" --dry-run
fingerprint_tree "$codex_home" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install_global "$SOURCE_ROOT" "$codex_home"
[ ! -s "$codex_home/AGENTS.md" ] || fail 'Old Rig section was left in AGENTS.md'
assert_contains "$codex_home/AGENTS.override.md" '# New override conventions'
assert_contains "$codex_home/AGENTS.override.md" '<!-- agent-rig:begin -->'
assert_contains "$codex_home/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.override.md\t')"
install_global "$SOURCE_ROOT" "$codex_home"
assert_contains "$TEST_ROOT/output" 'Already up to date.'
pass 'A newly active global override moves the managed section on update and supports dry runs'

cp "$codex_home/AGENTS.override.md" "$TEST_ROOT/removed-override"
rm "$codex_home/AGENTS.override.md"
fingerprint_tree "$codex_home" > "$TEST_ROOT/before"
reject_global "$SOURCE_ROOT" "$codex_home"
assert_contains "$TEST_ROOT/output" 'AGENTS.override.md (previously installed managed section was removed)'
fingerprint_tree "$codex_home" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install_global "$SOURCE_ROOT" "$codex_home" --replace-modified
assert_missing "$codex_home/AGENTS.override.md"
assert_contains "$codex_home/AGENTS.md" '<!-- agent-rig:begin -->'
assert_contains "$codex_home/.agent-rig/codex/manifest.tsv" "$(printf 'block\tAGENTS.md\t')"
pass 'Removing a managed global override is protected until explicit replacement restores AGENTS.md'

codex_home=$TEST_ROOT/global-transition-edits
install_global "$SOURCE_ROOT" "$codex_home"
printf '# Original global conventions\n\n' > "$TEST_ROOT/global-prefix"
printf '\nKeep this global suffix without a newline' > "$TEST_ROOT/global-suffix"
sed 's/## Root ownership/## Edited root ownership/' "$codex_home/AGENTS.md" > "$TEST_ROOT/global-modified-block"
cat "$TEST_ROOT/global-prefix" "$TEST_ROOT/global-modified-block" "$TEST_ROOT/global-suffix" > "$codex_home/AGENTS.md"
cp "$codex_home/AGENTS.md" "$TEST_ROOT/global-before-move"
printf '# New active override\n' > "$codex_home/AGENTS.override.md"
fingerprint_tree "$codex_home" > "$TEST_ROOT/before"
reject_global "$SOURCE_ROOT" "$codex_home"
assert_contains "$TEST_ROOT/output" 'AGENTS.md (managed section locally modified)'
fingerprint_tree "$codex_home" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install_global "$SOURCE_ROOT" "$codex_home" --replace-modified
cat "$TEST_ROOT/global-prefix" "$TEST_ROOT/global-suffix" > "$TEST_ROOT/global-expected-outside"
assert_same "$TEST_ROOT/global-expected-outside" "$codex_home/AGENTS.md"
assert_contains "$codex_home/AGENTS.override.md" '<!-- agent-rig:begin -->'
find_backup "$codex_home"
assert_same "$TEST_ROOT/global-before-move" "$backup/AGENTS.md"
pass 'Moving global instructions protects an edited old section and preserves its surrounding bytes'

codex_home=$TEST_ROOT/global-transition-rollback
install_global "$SOURCE_ROOT" "$codex_home"
printf '# Active override\n' > "$codex_home/AGENTS.override.md"
fingerprint_tree "$codex_home" > "$TEST_ROOT/before"
if env CODEX_HOME="$codex_home" PATH="$TEST_ROOT/fake-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$codex_home/AGENTS.override.md" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/global-transition-failed-once" bash "$SOURCE_ROOT/bin/agent-rig" install --global > "$TEST_ROOT/output" 2>&1; then
    fail 'Injected override-transition write failure should fail installation'
fi
assert_contains "$TEST_ROOT/output" 'restoring changed files'
fingerprint_tree "$codex_home" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_missing "$codex_home/.agent-rig/codex/.install-lock"
pass 'A failed global instruction move restores both instruction files and the manifest'

codex_home=$TEST_ROOT/global-local-edits
install_global "$SOURCE_ROOT" "$codex_home" --preset full
printf '\n# Local global-role customization\n' >> "$codex_home/agents/agent_rig_database.toml"
sed 's/## Root ownership/## Custom root ownership/' "$codex_home/AGENTS.md" > "$TEST_ROOT/global-edited-block"
cp "$TEST_ROOT/global-edited-block" "$codex_home/AGENTS.md"
fingerprint_tree "$codex_home" > "$TEST_ROOT/before"
reject_global "$SOURCE_ROOT" "$codex_home" --preset minimal
assert_contains "$TEST_ROOT/output" 'agents/agent_rig_database.toml (locally modified; removed by preset switch)'
assert_contains "$TEST_ROOT/output" 'AGENTS.md (managed section locally modified)'
fingerprint_tree "$codex_home" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
install_global "$SOURCE_ROOT" "$codex_home" --preset minimal --replace-modified
assert_missing "$codex_home/agents/agent_rig_database.toml"
assert_missing "$codex_home/.agent-rig/codex/workflows/security.md"
find_backup "$codex_home"
assert_contains "$backup/agents/agent_rig_database.toml" 'Local global-role customization'
assert_same "$TEST_ROOT/global-edited-block" "$backup/AGENTS.md"
pass 'Global preset switching protects local edits and explicit replacement backs them up'

reject_global "$SOURCE_ROOT" "$TEST_ROOT/default"
assert_contains "$TEST_ROOT/output" 'Installation scope differs'
reject "$SOURCE_ROOT" "$TEST_ROOT/global minimal/codex home"
assert_contains "$TEST_ROOT/output" 'Installation scope differs'
reject_global "$SOURCE_ROOT" "$TEST_ROOT/unused-global-home" --target "$TEST_ROOT/default"
assert_contains "$TEST_ROOT/output" '--global and --target are mutually exclusive'
assert_missing "$TEST_ROOT/unused-global-home"
pass 'Project and global installation scopes cannot share a manifest and flags are mutually exclusive'

for location in agents config.toml AGENTS.md AGENTS.override.md; do
    codex_home=$TEST_ROOT/global-link-$location
    mkdir "$codex_home"
    ln -s "$external" "$codex_home/$location"
    reject_global "$SOURCE_ROOT" "$codex_home" --replace-modified
    assert_contains "$TEST_ROOT/output" 'symlink'
    assert_missing "$codex_home/.agent-rig"
done
codex_home=$TEST_ROOT/global-home-link
ln -s "$external" "$codex_home"
reject_global "$SOURCE_ROOT" "$codex_home"
assert_contains "$TEST_ROOT/output" 'symlink'
assert_same "$external/config.toml" "$TEST_ROOT/external-original"
pass 'Global destination and Codex-home symlinks are rejected without external writes'

codex_home=$TEST_ROOT/global-rollback
if env CODEX_HOME="$codex_home" PATH="$TEST_ROOT/fake-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$codex_home/.agent-rig/codex/manifest.tsv" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/global-failed-once" bash "$SOURCE_ROOT/bin/agent-rig" install --global > "$TEST_ROOT/output" 2>&1; then
    fail 'Injected global write failure should fail installation'
fi
assert_contains "$TEST_ROOT/output" 'restoring changed files'
[ -z "$(find "$codex_home" -type f -print)" ] || fail 'Global files remained after rollback'
assert_missing "$codex_home/.agent-rig/codex/.install-lock"
pass 'Global write failure removes newly created files and releases the lock'

if bash "$SOURCE_ROOT/bin/agent-rig" install > "$TEST_ROOT/output" 2>&1; then
    fail 'Project installation without a target should be rejected'
fi
assert_contains "$TEST_ROOT/output" '--target or --global is required'
reject "$SOURCE_ROOT" "$TEST_ROOT/default" --preset --dry-run
assert_contains "$TEST_ROOT/output" 'Missing value for --preset before --dry-run'
if bash "$SOURCE_ROOT/bin/agent-rig" install --target --dry-run > "$TEST_ROOT/output" 2>&1; then
    fail 'An option cannot supply the target value'
fi
assert_contains "$TEST_ROOT/output" 'Missing value for --target before --dry-run'
rig=$TEST_ROOT/invalid-preset-rig
fixture "$rig"
for variant in empty-agents empty-workflows duplicate-field duplicate-role undefined-role undefined-workflow; do
    project=$TEST_ROOT/invalid-preset-$variant
    mkdir "$project"
    case $variant in
        empty-agents) printf 'agents: \nworkflows: quick\n' > "$rig/providers/codex/presets/full.preset"; expected_error='Empty agents field' ;;
        empty-workflows) printf 'agents: explorer\nworkflows:   \n' > "$rig/providers/codex/presets/full.preset"; expected_error='Empty workflows field' ;;
        duplicate-field) printf 'agents: explorer\nagents: tester\nworkflows: quick\n' > "$rig/providers/codex/presets/full.preset"; expected_error='Duplicate agents field' ;;
        duplicate-role) printf 'agents: explorer explorer\nworkflows: quick\n' > "$rig/providers/codex/presets/full.preset"; expected_error='Duplicate agent: explorer' ;;
        undefined-role) printf 'agents: unknown\nworkflows: quick\n' > "$rig/providers/codex/presets/full.preset"; expected_error='Missing agent: unknown' ;;
        undefined-workflow) printf 'agents: explorer\nworkflows: unknown\n' > "$rig/providers/codex/presets/full.preset"; expected_error='Missing workflow: unknown' ;;
    esac
    reject "$rig" "$project"
    assert_contains "$TEST_ROOT/output" "$expected_error"
    [ -z "$(find "$project" -mindepth 1 -print)" ] || fail 'Invalid preset created destination objects'
done
pass 'Empty, duplicate, and undefined preset entries are rejected before destination changes'
reject "$SOURCE_ROOT" "$TEST_ROOT/does-not-exist"
assert_contains "$TEST_ROOT/output" 'does not exist'
reject "$SOURCE_ROOT" "$TEST_ROOT/default" --preset unknown
assert_contains "$TEST_ROOT/output" 'Unknown preset'
reject "$SOURCE_ROOT" "$TEST_ROOT/default" --unexpected
assert_contains "$TEST_ROOT/output" 'Unknown option'
reject "$SOURCE_ROOT" "$SOURCE_ROOT"
assert_contains "$TEST_ROOT/output" 'source checkout'
pass 'Invalid arguments and source-checkout installation are rejected'

printf '\n%s installer checks passed.\n' "$passed"
