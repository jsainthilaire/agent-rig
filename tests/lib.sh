#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-rig-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
passed=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { passed=$((passed + 1)); printf 'PASS: %s\n' "$*"; }
assert_file() { [ -f "$1" ] || fail "Missing file: $1"; }
assert_missing() { [ ! -e "$1" ] && [ ! -L "$1" ] || fail "Unexpected path: $1"; }
assert_same() { cmp -s "$1" "$2" || fail "Files differ: $1 and $2"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "Missing text '$2' in $1"; }

fingerprint_tree() {
    (cd -- "$1" && find . -type f ! -path './.agent-rig/*/backups/*' ! -path './.agent-rig/backups/*' -exec cksum {} \; | sort)
}

install() {
    local rig=$1 project=$2
    shift 2
    bash "$rig/bin/agent-rig" install --target "$project" "$@" > "$TEST_ROOT/output" 2>&1 || {
        cat "$TEST_ROOT/output" >&2
        fail "Installation failed: $project"
    }
}

reject() {
    local rig=$1 project=$2
    shift 2
    if bash "$rig/bin/agent-rig" install --target "$project" "$@" > "$TEST_ROOT/output" 2>&1; then
        fail "Expected rejection: $project"
    fi
}

install_global() {
    local rig=$1 codex_home=$2
    shift 2
    env CODEX_HOME="$codex_home" bash "$rig/bin/agent-rig" install --global "$@" > "$TEST_ROOT/output" 2>&1 || {
        cat "$TEST_ROOT/output" >&2
        fail "Global installation failed: $codex_home"
    }
}

reject_global() {
    local rig=$1 codex_home=$2
    shift 2
    if env CODEX_HOME="$codex_home" bash "$rig/bin/agent-rig" install --global "$@" > "$TEST_ROOT/output" 2>&1; then
        fail "Expected global rejection: $codex_home"
    fi
}

fixture() {
    local destination=$1
    mkdir -p "$destination"
    cp -R "$SOURCE_ROOT/providers" "$SOURCE_ROOT/bin" "$destination/"
}

find_backup() {
    local base=$1 candidate
    backup=''
    for candidate in "$base"/.agent-rig/codex/backups/*; do
        if [ -d "$candidate" ]; then
            [ -z "$backup" ] || fail 'Expected one backup directory'
            backup=$candidate
        fi
    done
    [ -n "$backup" ] || fail 'Expected backup directory'
}
