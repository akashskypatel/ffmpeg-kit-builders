#!/usr/bin/env bash

if (( BASH_VERSINFO[0] < 4 )); then
    for bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$bash" ]]; then
            exec "$bash" "$0" "$@"
        fi
    done

    echo "GNU Bash 4+ is required." >&2
    exit 1
fi

find_build_dependents() {
    local root="$1"
    local target dep
    local changed progress ready
    local -a result=()
    local -A selected=()
    local -A emitted=()

    if [[ -z ${SUB_DEPENDENCIES[$root]+_} ]]; then
        echo "Unknown build target: $root" >&2
        return 1
    fi

    # Compute the transitive reverse-dependency closure.
    selected["$root"]=1
    changed=1
    while (( changed )); do
        changed=0

        while IFS= read -r target; do
            [[ -n ${selected[$target]+_} ]] && continue

            for dep in ${SUB_DEPENDENCIES[$target]}; do
                if [[ -n ${selected[$dep]+_} ]]; then
                    selected["$target"]=1
                    changed=1
                    break
                fi
            done
        done < <(printf '%s\n' "${!SUB_DEPENDENCIES[@]}" | LC_ALL=C sort)
    done

    # Emit in dependency-safe order. Alphabetical order breaks ties so output
    # remains deterministic even though SUB_DEPENDENCIES is associative.
    while (( ${#result[@]} < ${#selected[@]} )); do
        progress=0

        while IFS= read -r target; do
            [[ -z ${selected[$target]+_} ]] && continue
            [[ -n ${emitted[$target]+_} ]] && continue

            ready=1
            for dep in ${SUB_DEPENDENCIES[$target]}; do
                if [[ -n ${selected[$dep]+_} && -z ${emitted[$dep]+_} ]]; then
                    ready=0
                    break
                fi
            done

            if (( ready )); then
                result+=("$target")
                emitted["$target"]=1
                progress=1
            fi
        done < <(printf '%s\n' "${!selected[@]}" | LC_ALL=C sort)

        if (( ! progress )); then
            echo "Dependency cycle detected in selected build targets." >&2
            return 2
        fi
    done

    local IFS=,
    printf '%s\n' "${result[*]}"
}

if (( $# != 2 )); then
    echo "Usage: $0 deps-*.sh build_target" >&2
    exit 64
fi

deps_file="$1"
build_target="$2"

if [[ ! -f "$deps_file" ]]; then
    echo "Dependency file not found: $deps_file" >&2
    exit 66
fi

# Ensure a simple filename such as deps-wasm.sh is sourced from the current
# directory rather than searched through PATH.
if [[ "$deps_file" != */* ]]; then
    deps_file="./$deps_file"
fi

# shellcheck source=/dev/null
source "$deps_file"

if ! declare -p SUB_DEPENDENCIES 2>/dev/null | grep -q '^declare -A '; then
    echo "Dependency file must define associative array SUB_DEPENDENCIES." >&2
    exit 65
fi

find_build_dependents "$build_target"
