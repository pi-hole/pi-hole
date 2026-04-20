#!/usr/bin/env bash
set -euo pipefail

# Lint rule:
# - prefer long form when explicitly marked long in rules
# - prefer short form when explicitly marked short in rules
#
# Rules format (inline arrays in this file):
# - PREFER_LONG_RULES entries:  command:short=long
# - PREFER_SHORT_RULES entries: command:long=short
VERBOSE=0
FIX_MODE=0
SCRIPT_NAME="$(basename "$0")"

PREFER_LONG_RULES=(
    # BusyBox applets where long form is known/supported
    "mkdir:p=parents"
    "sed:i=in-place"
    "sed:e=expression"
    "sed:E=regexp-extended"
    "install:m=mode"
    "install:o=owner"
    "install:g=group"
    "install:t=target-directory"
    "install:d=directory"

    # Non-BusyBox commands where long form is preferred
    "curl:s=silent"
    "curl:S=show-error"
    "curl:L=location"
    "curl:f=fail"
    "curl:H=header"
    "jq:r=raw-output"
    "jq:R=raw-input"
    "jq:s=slurp"
    "git:q=quiet"
    "usermod:g=gid"
    "useradd:r=system"
    "useradd:g=gid"
    "useradd:s=shell"
)

PREFER_SHORT_RULES=(
    # BusyBox applets where long form is unavailable or unreliable
    "cut:delimiter=d"
    "cut:fields=f"
    "grep:quiet=q"
    "grep:count=c"
    "grep:invert-match=v"
    "grep:extended-regexp=E"
    "grep:after-context=A"
    "cp:preserve=p"
    "chmod:recursive=R"
    "rm:force=f"
    "rm:recursive=r"
    "head:lines=n"
    "tail:lines=n"
    "tail:bytes=c"
    "sha1sum:check=c"
    "sha1sum:status=s"
    "sha1sum:strict=w"
    "truncate:size=s"
)

usage() {
    cat <<'EOF'
Usage:
    lint-switch-style.sh [--verbose] [--fix] [FILE...]

Purpose:
    Enforce Pi-hole shell switch style for readability and compatibility:
    use long options where safe, keep short options where BusyBox requires them.

Options:
    -v, --verbose   Print rule loading and per-file check details
    --fix           Apply safe, token-level autofixes in place

If no FILE is provided, lints all tracked .sh files in the repository.
Exit code is non-zero when violations are found.
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
        --fix)
            FIX_MODE=1
            shift
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

declare -A KNOWN_COMMANDS=()
declare -A EXPECT_LONG=()   # key: cmd:short -> long name
declare -A EXPECT_SHORT=()  # key: cmd:long -> short name

rules_loaded=0

load_rules() {
    local rule cmd short long

    if [[ ${#PREFER_LONG_RULES[@]} -eq 0 && ${#PREFER_SHORT_RULES[@]} -eq 0 ]]; then
        echo "No inline rules configured in ${SCRIPT_NAME}" >&2
        exit 2
    fi

    for rule in "${PREFER_LONG_RULES[@]}"; do
        if [[ ! "${rule}" =~ ^([^:[:space:]]+):([A-Za-z])=([^[:space:]]+)$ ]]; then
            echo "Invalid long-rule format '${rule}' in ${SCRIPT_NAME}" >&2
            exit 2
        fi

        cmd="${BASH_REMATCH[1]}"
        short="${BASH_REMATCH[2]}"
        long="${BASH_REMATCH[3]}"

        KNOWN_COMMANDS["${cmd}"]=1
        EXPECT_LONG["${cmd}:${short}"]="${long}"
        rules_loaded=$((rules_loaded + 1))
    done

    for rule in "${PREFER_SHORT_RULES[@]}"; do
        if [[ ! "${rule}" =~ ^([^:[:space:]]+):([^=[:space:]]+)=([A-Za-z])$ ]]; then
            echo "Invalid short-rule format '${rule}' in ${SCRIPT_NAME}" >&2
            exit 2
        fi

        cmd="${BASH_REMATCH[1]}"
        long="${BASH_REMATCH[2]}"
        short="${BASH_REMATCH[3]}"

        KNOWN_COMMANDS["${cmd}"]=1
        EXPECT_SHORT["${cmd}:${long}"]="${short}"
        rules_loaded=$((rules_loaded + 1))
    done
}

load_rules

log_verbose "Loaded ${rules_loaded} inline rules from ${SCRIPT_NAME}"

if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    # Default to all shell scripts in the repository.
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        mapfile -t FILES < <(git ls-files '*.sh')
    else
        mapfile -t FILES < <(find . -type f -name '*.sh' -not -path './.git/*' -print | sed 's|^\./||')
    fi
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

normalize_option_token() {
    REPLY="$1"
    local last_char

    # Trim punctuation commonly attached by naive tokenization.
    # Example: --tags)" -> --tags
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

report_violation() {
    local file="$1"
    local line_no="$2"
    local cmd="$3"
    local got="$4"
    local expected="$5"

    printf '%s:%s: %s option style mismatch: found %s, expected %s (policy: long where safe, short where BusyBox requires)\n' "${file}" "${line_no}" "${cmd}" "${got}" "${expected}"
}

extract_token_parts() {
    local token="$1"
    local trailing=""
    local last_char

    while :; do
        last_char="${token: -1}"
        case "${last_char}" in
            '"'|"'"|')'|']'|'}'|';'|',')
                trailing="${last_char}${trailing}"
                token="${token%?}"
                ;;
            *)
                break
                ;;
        esac
    done

    REPLY="${token}"
    TOKEN_TRAILING="${trailing}"
}

convert_short_token_mixed() {
    local cmd="$1"
    local opt_base="$2"
    local body letters rest
    local idx c key mapped changed is_last
    local expanded=()

    [[ "${opt_base}" == -* && "${opt_base}" != --* ]] || return 1

    body="${opt_base#-}"
    letters=""
    rest=""

    # Split token body into a leading short-option cluster and optional attached value.
    for ((idx=0; idx<${#body}; idx++)); do
        c="${body:$idx:1}"
        if [[ "${c}" =~ [A-Za-z] ]] && [[ -z "${rest}" ]]; then
            letters+="${c}"
        else
            rest="${body:$idx}"
            break
        fi
    done

    [[ -n "${letters}" ]] || return 1

    changed=0
    for ((idx=0; idx<${#letters}; idx++)); do
        c="${letters:$idx:1}"
        key="${cmd}:${c}"
        mapped="${EXPECT_LONG[${key}]:-}"
        is_last=0
        if [[ $idx -eq $((${#letters} - 1)) ]]; then
            is_last=1
        fi

        if [[ -n "${mapped}" ]]; then
            changed=1
            if [[ ${is_last} -eq 1 && -n "${rest}" ]]; then
                expanded+=("--${mapped}=${rest}")
            else
                expanded+=("--${mapped}")
            fi
        else
            if [[ ${is_last} -eq 1 && -n "${rest}" ]]; then
                expanded+=("-${c}${rest}")
            else
                expanded+=("-${c}")
            fi
        fi
    done

    [[ ${changed} -eq 1 ]] || return 1
    REPLY="${expanded[*]}"
    return 0
}

violations=0
files_scanned=0
lines_scanned=0
option_checks=0
match_events=0
fixed_violations=0
files_modified=0
tmp_file=""

echo "Checking shell option style (readability + BusyBox compatibility)..."

for file in "${FILES[@]}"; do
    if [[ ! -f "${file}" ]]; then
        log_verbose "Skipping missing file: ${file}"
        continue
    fi

    files_scanned=$((files_scanned + 1))
    log_verbose "Scanning file: ${file}"

    file_modified=0
    if [[ ${FIX_MODE} -eq 1 ]]; then
        tmp_file="$(mktemp)"
    fi

    line_no=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line_modified=0
        comment=""

        line_no=$((line_no + 1))
        lines_scanned=$((lines_scanned + 1))

        # Ignore full-line comments and explicit ignore marker.
        if [[ "${line}" =~ ^[[:space:]]*# ]] || [[ "${line}" == *"lint-switch: ignore"* ]]; then
            if [[ ${FIX_MODE} -eq 1 ]]; then
                printf '%s\n' "${line}" >> "${tmp_file}"
            fi
            continue
        fi

        # Trim trailing comment for simple tokenization.
        code="${line%%#*}"
        if [[ "${line}" == *#* ]]; then
            comment="${line#"${code}"}"
        fi

        if [[ -z "${code//[[:space:]]/}" ]]; then
            if [[ ${FIX_MODE} -eq 1 ]]; then
                printf '%s\n' "${line}" >> "${tmp_file}"
            fi
            continue
        fi

        leading_ws="${code%%[![:space:]]*}"

        read -r -a tok <<< "${code}"
        if [[ ${#tok[@]} -eq 0 ]]; then
            if [[ ${FIX_MODE} -eq 1 ]]; then
                printf '%s\n' "${line}" >> "${tmp_file}"
            fi
            continue
        fi

        # Find all known commands on the line and check options after each.
        for ((i=0; i<${#tok[@]}; i++)); do
            t="${tok[$i]}"

            # Skip env assignments and unary !
            if is_assignment_token "${t}"; then
                continue
            fi
            [[ "${t}" == "!" ]] && continue

            cmd="${t}"
            [[ -n "${KNOWN_COMMANDS[${cmd}]:-}" ]] || continue

            log_verbose "  line ${line_no}: command '${cmd}'"

            for ((j=i+1; j<${#tok[@]}; j++)); do
                opt="${tok[$j]}"
                normalize_option_token "${opt}"
                opt="${REPLY}"

                is_separator_token "${opt}" && break

                [[ "${opt}" == "--" ]] && break
                [[ "${opt}" == "-" ]] && continue
                [[ "${opt}" == -* ]] || continue

                option_checks=$((option_checks + 1))

                if [[ "${opt}" == --* ]]; then
                    long_name="${opt#--}"
                    long_name="${long_name%%=*}"
                    log_verbose "    check long option --${long_name}"
                    key="${cmd}:${long_name}"
                    if [[ -n "${EXPECT_SHORT[${key}]:-}" ]]; then
                        short_name="${EXPECT_SHORT[${key}]}"
                        match_events=$((match_events + 1))
                        extract_token_parts "${tok[$j]}"
                        opt_base="${REPLY}"

                        if [[ ${FIX_MODE} -eq 1 && "${opt_base}" == "--${long_name}" ]]; then
                            tok[$j]="-${short_name}${TOKEN_TRAILING}"
                            fixed_violations=$((fixed_violations + 1))
                            line_modified=1
                            log_verbose "      fixed -> -${short_name}"
                        else
                            report_violation "${file}" "${line_no}" "${cmd}" "--${long_name}" "-${short_name}"
                            violations=$((violations + 1))
                        fi
                    else
                        log_verbose "      ok"
                    fi
                    continue
                fi

                short_cluster="${opt#-}"

                # Process bundled short opts like -cs, and short opts with attached value like -n1.
                for ((k=0; k<${#short_cluster}; k++)); do
                    ch="${short_cluster:$k:1}"
                    [[ "${ch}" =~ [A-Za-z] ]] || break

                    log_verbose "    check short option -${ch}"

                    key="${cmd}:${ch}"
                    if [[ -n "${EXPECT_LONG[${key}]:-}" ]]; then
                        long_name="${EXPECT_LONG[${key}]}"
                        match_events=$((match_events + 1))
                        extract_token_parts "${tok[$j]}"
                        opt_base="${REPLY}"
                        cluster="${opt_base#-}"

                        if [[ ${FIX_MODE} -eq 1 ]]; then
                            if [[ ${#cluster} -eq 1 && "${cluster}" == "${ch}" ]]; then
                                tok[$j]="--${long_name}${TOKEN_TRAILING}"
                                fixed_violations=$((fixed_violations + 1))
                                line_modified=1
                                log_verbose "      fixed -> --${long_name}"
                                break
                            elif convert_short_token_mixed "${cmd}" "${opt_base}"; then
                                tok[$j]="${REPLY}${TOKEN_TRAILING}"
                                fixed_violations=$((fixed_violations + 1))
                                line_modified=1
                                log_verbose "      fixed token -> ${REPLY}"
                                break
                            fi
                        fi

                        report_violation "${file}" "${line_no}" "${cmd}" "-${ch}" "--${long_name}"
                        violations=$((violations + 1))
                    else
                        log_verbose "      ok"
                    fi
                done
            done
        done

        if [[ ${FIX_MODE} -eq 1 ]]; then
            if [[ ${line_modified} -eq 1 ]]; then
                new_code="${tok[*]}"
                line="${leading_ws}${new_code}"
                if [[ -n "${comment}" ]]; then
                    line="${line} ${comment}"
                fi
                file_modified=1
            fi

            printf '%s\n' "${line}" >> "${tmp_file}"
        fi
    done < "${file}"

    if [[ ${FIX_MODE} -eq 1 ]]; then
        if [[ ${file_modified} -eq 1 ]] && ! cmp -s "${file}" "${tmp_file}"; then
            mv "${tmp_file}" "${file}"
            files_modified=$((files_modified + 1))
            log_verbose "Updated file: ${file}"
        else
            rm -f "${tmp_file}"
        fi
    fi
done

log_verbose "Summary: files=${files_scanned}, lines=${lines_scanned}, option-checks=${option_checks}, rule-matches=${match_events}, violations=${violations}"

if [[ ${FIX_MODE} -eq 1 ]]; then
    echo "Applied ${fixed_violations} auto-fix(es) across ${files_modified} file(s)."
fi

if [[ ${violations} -gt 0 ]]; then
    echo "Found ${violations} switch style issue(s)." >&2
    echo "Run with --fix to apply safe automatic fixes where possible." >&2
    exit 1
fi

echo "Switch style check passed: option usage matches project policy."
