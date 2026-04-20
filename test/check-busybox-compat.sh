#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERBOSE=0
STRICT=1
DIFF_BASE=""

# Pinned images keep checks reproducible.
IMAGES=(
    "alpine:3.21"
    "alpine:3.22"
)

FILES=()

usage() {
    cat <<'EOF'
Usage:
    check-busybox-compat.sh [options] [FILE...]

Purpose:
    Discover command switches used by repository shell scripts and probe whether
    those switches are accepted by matching BusyBox applets in container images.

Options:
    -v, --verbose       Print per-file and per-probe details
    -i, --image IMAGE   Add probe image (repeatable)
    --diff-base REF     Scan only changed *.sh files in REF...HEAD
    --no-strict         Do not fail on incompatible options
    -h, --help          Show this help text

Defaults:
    - Files: all tracked *.sh files
    - Images: alpine:3.21, alpine:3.22

Exit codes:
    0: no incompatibilities found (or --no-strict)
    1: incompatibilities found
    2: usage or environment error

Notes:
    - This is a best-effort lexical scan, not a full shell parser.
    - Variable-expanded options (example: ${opt}) are intentionally ignored.
EOF
}

log_verbose() {
    if [[ ${VERBOSE} -eq 1 ]]; then
        echo "$*"
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --no-strict)
            STRICT=0
            shift
            ;;
        -i|--image)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for $1" >&2
                usage
                exit 2
            fi
            IMAGES+=("$2")
            shift 2
            ;;
        --diff-base)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --diff-base" >&2
                usage
                exit 2
            fi
            DIFF_BASE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -gt 0 ]]; then
    FILES=("$@")
elif [[ -n "${DIFF_BASE}" ]]; then
    if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "--diff-base requires running inside a git work tree." >&2
        exit 2
    fi

    mapfile -t FILES < <(git diff --name-only --diff-filter=ACMR "${DIFF_BASE}...HEAD" -- '*.sh' | tr -d '\r')
    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "No changed shell files detected in ${DIFF_BASE}...HEAD."
        exit 0
    fi
else
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        mapfile -t FILES < <(git ls-files '*.sh')
    else
        mapfile -t FILES < <(find . -type f -name '*.sh' -not -path './.git/*' -print | sed 's|^\./||')
    fi
fi

# De-duplicate image list while preserving first-seen order.
declare -A seen_images=()
deduped_images=()
for image in "${IMAGES[@]}"; do
    if [[ -z "${seen_images[${image}]:-}" ]]; then
        deduped_images+=("${image}")
        seen_images["${image}"]=1
    fi
done
IMAGES=("${deduped_images[@]}")

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No shell files found to scan." >&2
    exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for BusyBox compatibility probing." >&2
    exit 2
fi

is_assignment_token() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]
}

is_separator_token() {
    case "$1" in
        "|"|"||"|";"|"&&"|"{"|"}"|"then"|"do"|"done"|"fi"|"elif"|"else"|"in")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_non_command_token() {
    case "$1" in
        "["|"[["|"]"|"]]"|"test"|"if"|"for"|"while"|"until"|"case"|"then"|"do"|"done"|"fi"|"elif"|"else"|"esac"|"function"|"select"|"time"|"coproc"|"(("|"))")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_token() {
    REPLY="$1"
    local last_char

    while :; do
        last_char="${REPLY: -1}"
        case "${last_char}" in
            '"'|"'"|')'|']'|'}'|';'|',')
                REPLY="${REPLY%?}"
                ;;
            *)
                break
                ;;
        esac
    done
}

record_option() {
    local cmd="$1"
    local opt="$2"
    local key

    case "${opt}" in
        --[A-Za-z0-9][A-Za-z0-9-]*)
            ;;
        -[A-Za-z])
            ;;
        *)
            return
            ;;
    esac

    key="${cmd}|${opt}"
    CMD_OPTION_SET["${key}"]=1
    CMD_OPTION_HITS["${key}"]=$(( ${CMD_OPTION_HITS[${key}]:-0} + 1 ))
}

declare -A CMD_OPTION_SET=()
declare -A CMD_OPTION_HITS=()
files_scanned=0
lines_scanned=0
options_collected=0
raw_option_sightings=0

echo "Scanning shell scripts for command switches..."

for file in "${FILES[@]}"; do
    if [[ ! -f "${file}" ]]; then
        log_verbose "Skipping missing file: ${file}"
        continue
    fi

    files_scanned=$((files_scanned + 1))
    log_verbose "Scanning file: ${file}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        lines_scanned=$((lines_scanned + 1))

        if [[ "${line}" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        code="${line%%#*}"
        if [[ -z "${code//[[:space:]]/}" ]]; then
            continue
        fi

        read -r -a tok <<< "${code}"
        if [[ ${#tok[@]} -eq 0 ]]; then
            continue
        fi

        # Best-effort parser guard: skip quoted assignment payloads, which often
        # contain command-like text not executed on this line (example: install -y).
        if is_assignment_token "${tok[0]}" && [[ "${code}" == *'"'* || "${code}" == *"'"* ]]; then
            continue
        fi

        current_cmd=""
        expect_command=1
        accept_options=1

        for raw in "${tok[@]}"; do
            normalize_token "${raw}"
            t="${REPLY}"
            [[ -z "${t}" ]] && continue

            if is_separator_token "${t}"; then
                current_cmd=""
                expect_command=1
                accept_options=1
                continue
            fi

            if [[ ${expect_command} -eq 1 ]]; then
                if is_assignment_token "${t}" || [[ "${t}" == "!" ]]; then
                    continue
                fi
                if [[ "${t}" == -* ]]; then
                    continue
                fi
                if is_non_command_token "${t}"; then
                    continue
                fi
                if [[ "${t}" == *'$'* || "${t}" == *'{'* || "${t}" == *'}'* ]]; then
                    continue
                fi

                current_cmd="${t##*/}"
                expect_command=0
                accept_options=1
                continue
            fi

            [[ -n "${current_cmd}" ]] || continue

            if [[ ${accept_options} -eq 0 ]]; then
                continue
            fi

            if [[ "${t}" == "--" ]]; then
                accept_options=0
                continue
            fi

            if [[ "${t}" == --* ]]; then
                long_opt="${t%%=*}"
                raw_option_sightings=$((raw_option_sightings + 1))
                before=${#CMD_OPTION_SET[@]}
                record_option "${current_cmd}" "${long_opt}"
                after=${#CMD_OPTION_SET[@]}
                if [[ ${after} -gt ${before} ]]; then
                    options_collected=$((options_collected + 1))
                fi
                continue
            fi

            if [[ "${t}" == -* && "${t}" != "-" ]]; then
                cluster="${t#-}"
                for ((idx=0; idx<${#cluster}; idx++)); do
                    ch="${cluster:$idx:1}"
                    if [[ ! "${ch}" =~ [A-Za-z] ]]; then
                        break
                    fi
                    raw_option_sightings=$((raw_option_sightings + 1))
                    before=${#CMD_OPTION_SET[@]}
                    record_option "${current_cmd}" "-${ch}"
                    after=${#CMD_OPTION_SET[@]}
                    if [[ ${after} -gt ${before} ]]; then
                        options_collected=$((options_collected + 1))
                    fi
                done
                continue
            fi

            # Option collection is limited to the leading option block.
            accept_options=0
        done
    done < "${file}"
done

echo "Grouped ${raw_option_sightings} option sighting(s) into ${#CMD_OPTION_SET[@]} unique command option shape(s) from ${files_scanned} file(s)."
log_verbose "Scan stats: lines=${lines_scanned}, newly-collected-options=${options_collected}"

if [[ ${#CMD_OPTION_SET[@]} -eq 0 ]]; then
    echo "No literal command options found to probe."
    exit 0
fi

declare -A APPLET_PRESENT=()

echo "Collecting BusyBox applet inventories..."
for image in "${IMAGES[@]}"; do
    log_verbose "Listing applets from image: ${image}"
    if ! mapfile -t applets < <(docker run --rm "${image}" sh -c 'busybox --list' 2>/dev/null); then
        echo "Failed to list applets from image '${image}'." >&2
        exit 2
    fi

    if [[ ${#applets[@]} -eq 0 ]]; then
        echo "No applets detected in image '${image}'." >&2
        exit 2
    fi

    for applet in "${applets[@]}"; do
        APPLET_PRESENT["${image}|${applet}"]=1
    done

    log_verbose "  applets=${#applets[@]}"
done

tested=0
passed=0
failed=0
skipped_non_applet=0

declare -A FAIL_BY_PROBE=()

probe_option() {
    local image="$1"
    local cmd="$2"
    local opt="$3"

    local output
    output="$(docker run --rm "${image}" sh -c "busybox \"${cmd}\" \"${opt}\" </dev/null >/dev/null" 2>&1 || true)"

    if [[ "${output}" =~ [Uu]nrecognized\ option|[Ii]nvalid\ option|[Ii]llegal\ option|[Uu]nknown\ option ]]; then
        return 1
    fi
    return 0
}

echo "Probing BusyBox applet option compatibility..."

for key in "${!CMD_OPTION_SET[@]}"; do
    cmd="${key%%|*}"
    opt="${key#*|}"

    for image in "${IMAGES[@]}"; do
        if [[ -z "${APPLET_PRESENT[${image}|${cmd}]:-}" ]]; then
            skipped_non_applet=$((skipped_non_applet + 1))
            continue
        fi

        tested=$((tested + 1))
        if probe_option "${image}" "${cmd}" "${opt}"; then
            passed=$((passed + 1))
            log_verbose "PASS ${image}: ${cmd} ${opt}"
        else
            failed=$((failed + 1))
            probe_key="${cmd}|${opt}"
            if [[ -n "${FAIL_BY_PROBE[${probe_key}]:-}" ]]; then
                FAIL_BY_PROBE["${probe_key}"]+=" ${image}"
            else
                FAIL_BY_PROBE["${probe_key}"]="${image}"
            fi
            log_verbose "FAIL ${image}: ${cmd} ${opt}"
        fi
    done
done

echo
echo "BusyBox compatibility summary"
echo "  images: ${#IMAGES[@]}"
echo "  tested applet option probes: ${tested}"
echo "  compatible: ${passed}"
echo "  incompatible: ${failed}"
echo "  skipped (command not an applet in image): ${skipped_non_applet}"

if [[ ${failed} -gt 0 ]]; then
    echo
    echo "Incompatible unique probes"
    for probe_key in "${!FAIL_BY_PROBE[@]}"; do
        cmd="${probe_key%%|*}"
        opt="${probe_key#*|}"
        echo "  - ${cmd} ${opt} (failed in: ${FAIL_BY_PROBE[${probe_key}]})"
    done
fi

if [[ ${failed} -gt 0 && ${STRICT} -eq 1 ]]; then
    exit 1
fi

exit 0
