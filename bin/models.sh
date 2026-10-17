# Shared model configuration lifecycle. Only trusted source definitions are read.
model_roles='explorer implementer database tester reviewer debugger security'
models_config=''
models_consent=ask
model_cli=''
model_resets=''

models_defaults() {
    # Isolate adapter globals when generating a file for both providers.
    (
        PROVIDER_ROOT=$RIG_ROOT/providers/$1
        source "$PROVIDER_ROOT/provider.sh"
        provider_model_defaults
    )
}

models_parse() {
    [ -f "$1" ] && [ -r "$1" ] || die "Cannot read model configuration: $1"
    awk -f "$RIG_ROOT/bin/models-parse.awk" "$1"
}

models_records() {
    printf '%s' "$1" | awk -v records=1 -f "$RIG_ROOT/bin/models-parse.awk"
}

models_confirm() {
    local answer
    while :; do
        printf '%s [y/N] ' "$1"
        if ! IFS= read -r answer; then die 'No model configuration confirmation received; no target files changed'; fi
        case $answer in
            y|Y|yes|YES|Yes) return 0 ;;
            ''|n|N|no|NO|No) return 1 ;;
            *) printf 'Please answer yes or no.\n' ;;
        esac
    done
}

models_append() {
    models_parse "$1" > "$stage/parsed-models.tsv" || die "Invalid model configuration: $1"
    awk -v origin="$2" 'BEGIN { OFS = "\t" } { print $0, origin }' "$stage/parsed-models.tsv" >> "$stage/model-events.tsv"
}

models_prepare() {
    local role candidate origin saved=$state_directory/models/overrides.ini found=0 accept=0
    models_defaults "$provider" > "$stage/model-defaults.tsv"
    : > "$stage/model-events.tsv"
    snapshot "$saved"
    if [ -f "$target/$saved" ]; then
        # Never adopt untracked data as saved installer state.
        [ -n "$(old_checksum file "$saved")" ] || die "Unmanaged model override state: $saved"
        models_append "$target/$saved" saved
    fi
    for role in $model_resets; do
        case $role in all) role=$model_roles ;; esac
        for candidate in $role; do
            case " $model_roles " in *" $candidate "*) ;; *) die "Unknown reset role: $candidate" ;; esac
            printf '%s\t%s\tmodel\tdefault\treset\n%s\t%s\teffort\tdefault\treset\n' "$provider" "$candidate" "$provider" "$candidate" >> "$stage/model-events.tsv"
        done
    done
    : > "$stage/model-inputs"
    if [ "$models_consent" != ignore ]; then
        if [ -n "$models_config" ]; then
            [ -f "$models_config" ] || die "Cannot read model configuration: $models_config"
            printf '%s\n' "$models_config" >> "$stage/model-inputs"
        else
            if [ -e "$RIG_ROOT/models.ini" ] || [ -L "$RIG_ROOT/models.ini" ]; then
                printf '%s\n' "$RIG_ROOT/models.ini" >> "$stage/model-inputs"
            fi
            check_path .agent-rig/models.ini
            snapshot .agent-rig/models.ini
            if [ -f "$target/.agent-rig/models.ini" ]; then
                printf '%s\n' "$target/.agent-rig/models.ini" >> "$stage/model-inputs"
            fi
        fi
    fi
    if [ -s "$stage/model-inputs" ]; then
        printf '\nModel configuration files (later entries take precedence):\n'
        while IFS= read -r candidate; do printf '  %s\n' "$candidate"; done < "$stage/model-inputs"
        if [ "$models_consent" = use ]; then accept=1
        elif models_confirm 'Apply these model configuration files?'; then accept=1; fi
        if [ "$accept" -eq 1 ]; then
            found=0
            while IFS= read -r candidate; do
                found=$((found + 1))
                origin=file-$found
                models_append "$candidate" "$origin"
            done < "$stage/model-inputs"
        else
            printf 'Model configuration files skipped; saved choices and CLI overrides still apply.\n'
        fi
    fi
    printf '%s' "$model_cli" | awk -v provider="$provider" '{ print provider "\t" $0 }' > "$stage/model-cli-input.tsv"
    awk -v records=1 -f "$RIG_ROOT/bin/models-parse.awk" "$stage/model-cli-input.tsv" > "$stage/model-cli.tsv" || die 'Invalid CLI model override'
    awk 'BEGIN { OFS = "\t" } { print $0, "CLI" }' "$stage/model-cli.tsv" >> "$stage/model-events.tsv"
    : > "$stage/model-overrides.ini"
    awk -v provider="$provider" -v overrides="$stage/model-overrides.ini" -f "$RIG_ROOT/bin/models-resolve.awk" "$stage/model-defaults.tsv" "$stage/model-events.tsv" > "$stage/model-effective.tsv" || die 'Invalid model/effort combination'
}

models_summary() {
    local role model effort model_source effort_source
    printf '\nEffective role models and reasoning effort:\n'
    while IFS="$(printf '\t')" read -r role model effort model_source effort_source; do
        case " $agents " in *" $role "*)
            printf '  %s: %s / %s (model: %s; effort: %s)\n' "$role" "$model" "$effort" "$model_source" "$effort_source" ;;
        esac
    done < "$stage/model-effective.tsv"
}

models_instruction_table() {
    printf '\n### Effective role model settings\n\n| Role | Model | Effort |\n| --- | --- | --- |\n'
    awk -F '\t' -v roles=" $agents " 'index(roles, " " $1 " ") { printf "| %s | `%s` | %s |\n", $1, $2, $3 }' "$stage/model-effective.tsv"
}
