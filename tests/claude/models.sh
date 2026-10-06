#!/usr/bin/env bash
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/../lib.sh"

project=$TEST_ROOT/defaults
mkdir "$project"
install "$SOURCE_ROOT" "$project" --provider claude
for role in explorer implementer database tester debugger reviewer security; do
    agent=$project/.claude/agents/agent-rig-$role.md
    case $role in
        explorer)
            assert_contains "$agent" 'model: claude-haiku-4-5-20251001'
            if grep -q '^effort:' "$agent"; then fail 'Haiku received unsupported effort'; fi ;;
        reviewer|security)
            assert_contains "$agent" 'model: claude-opus-5-5'
            assert_contains "$agent" 'effort: high' ;;
        *)
            assert_contains "$agent" 'model: claude-sonnet-5-5'
            assert_contains "$agent" 'effort: medium' ;;
    esac
    if grep -q '__AGENT_RIG_' "$agent"; then fail 'Native agent retains placeholders'; fi
    if grep -q '^model: claude-fable' "$agent"; then fail 'Escalation model enabled by default'; fi
done
assert_contains "$project/CLAUDE.md" 'claude-fable-5-1'
assert_contains "$project/CLAUDE.md" 'one bounded attempt at each higher tier'
assert_contains "$project/.agent-rig/claude/manifest.tsv" "$(printf 'file\t.agent-rig/claude/models/policy.tsv\t')"
pass 'Default native models, separate effort, explicit policy, and bounded escalation match role strategy'

# Adopt the earlier inherited-model format via its recorded checksums.
for role in explorer implementer database tester debugger reviewer security; do
    agent=$project/.claude/agents/agent-rig-$role.md
    sed -e 's/^model: .*/model: inherit/' -e '/^effort:/d' "$agent" > "$TEST_ROOT/old-agent"
    cp "$TEST_ROOT/old-agent" "$agent"
    read -r crc bytes < <(cksum < "$agent")
    awk -F '\t' -v role=".claude/agents/agent-rig-$role.md" -v crc="$crc" -v bytes="$bytes" 'BEGIN { OFS = "\t" } $1 == "file" && $2 == role { $3 = crc; $4 = bytes } { print }' "$project/.agent-rig/claude/manifest.tsv" > "$TEST_ROOT/old-manifest"
    cp "$TEST_ROOT/old-manifest" "$project/.agent-rig/claude/manifest.tsv"
done
install "$SOURCE_ROOT" "$project" --provider claude
assert_contains "$project/.claude/agents/agent-rig-explorer.md" 'model: claude-haiku-4-5-20251001'
old_backup=$(find "$project/.agent-rig/claude/backups" -name agent-rig-explorer.md | head -1)
assert_contains "$old_backup" 'model: inherit'
pass 'Recorded inherited-model agents update to pins with backups'

rig=$TEST_ROOT/source-upgrade
fixture "$rig"
project=$TEST_ROOT/policy-upgrade
mkdir "$project"
install "$rig" "$project"
install "$rig" "$project" --provider claude
(cd "$project" && find .codex .agent-rig/codex -type f -exec cksum {} \; && cksum AGENTS.md) | sort > "$TEST_ROOT/codex-before"
cp "$project/.claude/agents/agent-rig-explorer.md" "$TEST_ROOT/explorer-before"
cp "$project/.claude/agents/agent-rig-reviewer.md" "$TEST_ROOT/reviewer-before"
cp "$project/.agent-rig/claude/models/policy.tsv" "$TEST_ROOT/policy-before"
awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "tier" && $2 == "balanced" { $4 = "high" } { print }' "$rig/providers/claude/models/policy.tsv" > "$TEST_ROOT/new-policy"
cp "$TEST_ROOT/new-policy" "$rig/providers/claude/models/policy.tsv"
fingerprint_tree "$project" > "$TEST_ROOT/before"
install "$rig" "$project" --provider claude --dry-run
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
mkdir "$TEST_ROOT/failing-bin"
cat > "$TEST_ROOT/failing-bin/mv" <<'SH'
#!/usr/bin/env bash
last=''
for arg in "$@"; do last=$arg; done
if [ "$last" = "$AGENT_RIG_FAIL_PATH" ] && [ ! -e "$AGENT_RIG_FAIL_ONCE" ]; then
    touch "$AGENT_RIG_FAIL_ONCE"
    exit 1
fi
exec "$AGENT_RIG_REAL_MV" "$@"
SH
chmod +x "$TEST_ROOT/failing-bin/mv"
if env PATH="$TEST_ROOT/failing-bin:$PATH" AGENT_RIG_REAL_MV="$(command -v mv)" AGENT_RIG_FAIL_PATH="$project/CLAUDE.md" AGENT_RIG_FAIL_ONCE="$TEST_ROOT/failed-upgrade" bash "$rig/bin/agent-rig" install --yes --provider claude --target "$project" > "$TEST_ROOT/output" 2>&1; then fail 'Policy rollback failure was not triggered'; fi
assert_contains "$TEST_ROOT/output" 'Write failed; restoring'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
assert_same "$TEST_ROOT/policy-before" "$project/.agent-rig/claude/models/policy.tsv"
assert_missing "$project/.agent-rig/claude/.install-lock"
pass 'A failed policy upgrade restores native agents, the policy copy, and ownership state'
install "$rig" "$project" --provider claude
for role in implementer database tester debugger; do assert_contains "$project/.claude/agents/agent-rig-$role.md" 'effort: high'; done
assert_same "$TEST_ROOT/explorer-before" "$project/.claude/agents/agent-rig-explorer.md"
assert_same "$TEST_ROOT/reviewer-before" "$project/.claude/agents/agent-rig-reviewer.md"
(cd "$project" && find .codex .agent-rig/codex -type f -exec cksum {} \; && cksum AGENTS.md) | sort > "$TEST_ROOT/codex-after"
assert_same "$TEST_ROOT/codex-before" "$TEST_ROOT/codex-after"
policy_backup=$(find "$project/.agent-rig/claude/backups" -path '*/models/policy.tsv' | head -1)
assert_same "$TEST_ROOT/policy-before" "$policy_backup"
install "$rig" "$project" --provider claude
assert_contains "$TEST_ROOT/output" 'Already up to date.'
pass 'A centralized effort update refreshes only affected Claude roles and leaves Codex unchanged'

sed 's/^model: .*/model: claude-sonnet-5/' "$project/.claude/agents/agent-rig-reviewer.md" > "$TEST_ROOT/user-override"
cp "$TEST_ROOT/user-override" "$project/.claude/agents/agent-rig-reviewer.md"
fingerprint_tree "$project" > "$TEST_ROOT/before"
reject "$rig" "$project" --provider claude
assert_contains "$TEST_ROOT/output" 'locally modified'
fingerprint_tree "$project" > "$TEST_ROOT/after"
assert_same "$TEST_ROOT/before" "$TEST_ROOT/after"
pass 'A user native model override remains a protected local edit'

for variant in alias undated-haiku unsupported-effort duplicate-tier missing-role automatic-escalation unsafe-model empty-policy; do
    bad_rig=$TEST_ROOT/invalid-$variant
    fixture "$bad_rig"
    policy=$bad_rig/providers/claude/models/policy.tsv
    case $variant in
        alias) sed 's/claude-sonnet-5-5/sonnet/' "$policy" > "$TEST_ROOT/bad-policy" ;;
        undated-haiku) sed 's/claude-haiku-4-5-20251001/claude-haiku-4-5/' "$policy" > "$TEST_ROOT/bad-policy" ;;
        unsupported-effort) awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "tier" && $2 == "fast" { $4 = "low" } { print }' "$policy" > "$TEST_ROOT/bad-policy" ;;
        duplicate-tier) cat "$policy" > "$TEST_ROOT/bad-policy"; sed -n '/^tier.*fast/p' "$policy" >> "$TEST_ROOT/bad-policy" ;;
        missing-role) sed '/^role.*security/d' "$policy" > "$TEST_ROOT/bad-policy" ;;
        automatic-escalation) awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "role" && $2 == "reviewer" { $3 = "escalation" } { print }' "$policy" > "$TEST_ROOT/bad-policy" ;;
        unsafe-model) sed 's/claude-sonnet-5-5/$(touch evil)/' "$policy" > "$TEST_ROOT/bad-policy" ;;
        empty-policy) : > "$TEST_ROOT/bad-policy" ;;
    esac
    cp "$TEST_ROOT/bad-policy" "$policy"
    empty_project=$TEST_ROOT/reject-$variant
    mkdir "$empty_project"
    reject "$bad_rig" "$empty_project" --provider claude --replace-modified
    assert_contains "$TEST_ROOT/output" 'Invalid Claude model policy'
    assert_missing "$empty_project/.claude"
    assert_missing "$empty_project/.agent-rig"
    assert_missing "$empty_project/evil"
done
pass 'Malformed policies, aliases, unsupported effort, and default escalation are rejected before writes'

for variant in bypass-policy duplicate-effort missing-header; do
    bad_rig=$TEST_ROOT/invalid-agent-$variant
    fixture "$bad_rig"
    agent=$bad_rig/providers/claude/agents/explorer.md
    case $variant in
        bypass-policy) sed 's/model: __AGENT_RIG_MODEL__/model: inherit/' "$agent" > "$TEST_ROOT/bad-agent" ;;
        duplicate-effort) sed '/^effort:/a\
effort: __AGENT_RIG_EFFORT__' "$agent" > "$TEST_ROOT/bad-agent" ;;
        missing-header) sed '1d' "$agent" > "$TEST_ROOT/bad-agent" ;;
    esac
    cp "$TEST_ROOT/bad-agent" "$agent"
    empty_project=$TEST_ROOT/reject-agent-$variant
    mkdir "$empty_project"
    reject "$bad_rig" "$empty_project" --provider claude --replace-modified
    assert_contains "$TEST_ROOT/output" 'Claude agent renderer'
    assert_missing "$empty_project/.claude"
    assert_missing "$empty_project/.agent-rig"
done
pass 'Native source templates cannot bypass policy or render malformed model frontmatter'

# Uninstall must use recorded state without requiring a still-present policy.
rm -rf "$rig/providers/claude/models"
bash "$rig/bin/agent-rig" uninstall --provider claude --target "$project" --remove-modified > "$TEST_ROOT/output" 2>&1 || fail 'Source-independent policy removal failed'
assert_missing "$project/.agent-rig/claude/models/policy.tsv"
assert_missing "$project/.agent-rig/claude/manifest.tsv"
(cd "$project" && find .codex .agent-rig/codex -type f -exec cksum {} \; && cksum AGENTS.md) | sort > "$TEST_ROOT/codex-after"
assert_same "$TEST_ROOT/codex-before" "$TEST_ROOT/codex-after"
pass 'Removal follows recorded policy ownership without source policy assets and preserves Codex'
printf '\nAll %s Claude model policy checks passed.\n' "$passed"
