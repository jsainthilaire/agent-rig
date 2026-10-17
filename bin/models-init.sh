# Standalone config creation; never installs or edits provider configuration.
models_init() {
    local selected=both destination='' location='' interactive=0 overwrite=0
    local arg role model effort value setting p result tmp fingerprint=missing
    shift
    [ "${1:-}" = init ] || die 'Usage: agent-rig config init (--rig | --target DIRECTORY | --global) [--provider codex|claude|both] [--interactive] [--overwrite]'
    shift
    while [ "$#" -gt 0 ]; do
        case $1 in
            --rig|--global)
                [ -z "$location" ] || die 'Choose exactly one config destination'
                location=$1; shift ;;
            --target|--provider)
                [ "$#" -ge 2 ] && [ -n "$2" ] || die "Missing value for $1"
                case $2 in --*) die "Missing value for $1" ;; esac
                if [ "$1" = --target ]; then
                    [ -z "$location" ] || die 'Choose exactly one config destination'
                    location=--target; destination=$2
                else selected=$2; fi
                shift 2 ;;
            --interactive) interactive=1; shift ;;
            --overwrite) overwrite=1; shift ;;
            *) die "Unknown config option: $1" ;;
        esac
    done
    case $selected in codex|claude|both) ;; *) die "Unknown provider: $selected" ;; esac
    case $location in
        --rig) destination=$RIG_ROOT ;;
        --target) [ -d "$destination" ] || die "Target directory does not exist: $destination" ;;
        --global)
            case $selected in
                codex) destination=${CODEX_HOME:-${HOME:?HOME required}/.codex} ;;
                claude) destination=${CLAUDE_CONFIG_DIR:-${HOME:?HOME required}/.claude} ;;
                *) die '--global requires --provider codex or claude' ;;
            esac ;;
        *) die 'Choose --rig, --target DIRECTORY, or --global' ;;
    esac
    case $destination in *"$(printf '\t')"*|*$'\n'*) die 'Config paths cannot contain tabs or newlines' ;; esac
    target=$destination
    if [ "$location" = --rig ]; then result=models.ini; else result=.agent-rig/models.ini; fi
    check_path "$result"
    if [ -f "$target/$result" ]; then
        [ "$overwrite" -eq 1 ] || die "Config already exists: $target/$result; edit it manually or use --overwrite"
        fingerprint=$(checksum "$target/$result")
    fi
    stage=$(mktemp -d "${TMPDIR:-/tmp}/agent-rig.XXXXXX")
    : > "$stage/temp-paths"
    : > "$stage/config.ini"
    printf '# Agent Rig model overrides. Use default to follow shipped defaults.\n# Model and effort are independent; Claude supports effort = omit.\n\n' >> "$stage/config.ini"
    if [ "$selected" = both ]; then selected='codex claude'; fi
    for p in $selected; do
        models_defaults "$p" > "$stage/defaults-$p.tsv"
        # Use a dedicated descriptor: prompts must read the user's stdin.
        while IFS="$(printf '\t')" read -r role model effort <&3; do
            printf '[%s.%s]\n' "$p" "$role" >> "$stage/config.ini"
            for setting in model effort; do
                if [ "$setting" = model ]; then arg=$model; else arg=$effort; fi
                value=default
                if [ "$interactive" -eq 1 ]; then
                    while :; do
                        printf '%s.%s %s [default: %s]: ' "$p" "$role" "$setting" "$arg"
                        IFS= read -r value || die 'Config creation cancelled before saving (EOF)'
                        value=${value:-default}
                        if models_records "$(printf '%s\t%s\t%s\t%s' "$p" "$role" "$setting" "$value")"$'\n' > /dev/null; then break; fi
                    done
                fi
                printf '# Current default %s: %s\n%s = %s\n' "$setting" "$arg" "$setting" "$value" >> "$stage/config.ini"
            done
            printf '\n' >> "$stage/config.ini"
        done 3< "$stage/defaults-$p.tsv"
    done
    # Validate model/effort combinations after all answers; let the user correct
    # a mismatched pair without discarding the rest of an interactive session.
    while :; do
        models_parse "$stage/config.ini" > "$stage/config-records.tsv"
        value=0
        for p in $selected; do
            : > "$stage/check-overrides.ini"
            if ! awk -v provider="$p" -v overrides="$stage/check-overrides.ini" -f "$RIG_ROOT/bin/models-resolve.awk" "$stage/defaults-$p.tsv" "$stage/config-records.tsv" > "$stage/effective-$p.tsv"; then value=1; fi
        done
        [ "$value" -eq 1 ] || break
        [ "$interactive" -eq 1 ] || die 'Invalid generated model settings'
        printf 'Correct a role setting (provider.role.setting=value), or Ctrl-D to cancel: '
        IFS= read -r arg || die 'Config creation cancelled before saving (EOF)'
        if ! printf '%s\n' "$arg" | awk '
            { n = split($0, a, "="); m = split(a[1], b, "."); if (n != 2 || m != 3) exit 1; printf "%s\t%s\t%s\t%s\n", b[1], b[2], b[3], a[2] }
        ' > "$stage/correction.tsv"; then printf 'Invalid correction.\n'; continue; fi
        if ! models_records "$(cat "$stage/correction.tsv")"$'\n' > /dev/null; then continue; fi
        # Only a selected section may be corrected.
        if ! awk -F '\t' -v selected=" $selected " 'index(selected, " " $1 " ") { ok = 1 } END { exit !ok }' "$stage/correction.tsv"; then
            printf 'Provider was not selected.\n'; continue
        fi
        awk -F '\t' '
            FNR == NR { section = "[" $1 "." $2 "]"; key = $3; value = $4; next }
            /^\[/ { active = ($0 == section) }
            active && index($0, key " = ") == 1 { print key " = " value; next }
            { print }
        ' "$stage/correction.tsv" "$stage/config.ini" > "$stage/corrected.ini"
        mv "$stage/corrected.ini" "$stage/config.ini"
    done
    if [ "$interactive" -eq 1 ]; then
        printf '\nConfiguration to save at %s/%s:\n' "$target" "$result"
        cat "$stage/config.ini"
        if ! models_confirm 'Save this model configuration?'; then printf 'Config creation cancelled.\n'; return; fi
    fi
    check_path "$result"
    if [ -f "$target/$result" ]; then value=$(checksum "$target/$result"); else value=missing; fi
    [ "$value" = "$fingerprint" ] || die 'Config changed during creation; rerun config init'
    mkdir -p "$target/$(dirname -- "$result")"
    tmp=$(mktemp "$target/$(dirname -- "$result")/.agent-rig-config.XXXXXX")
    printf '%s\n' "$tmp" >> "$stage/temp-paths"
    cat "$stage/config.ini" > "$tmp"
    chmod 644 "$tmp"
    if [ "$overwrite" -eq 1 ]; then mv -f "$tmp" "$target/$result"
    else
        # A hard link publishes the complete file without overwriting a file
        # created concurrently after the initial existence check.
        ln "$tmp" "$target/$result" || die 'Config appeared during creation; no existing file replaced'
        rm "$tmp"
    fi
    printf 'Created model configuration: %s/%s\n' "$target" "$result"
}
