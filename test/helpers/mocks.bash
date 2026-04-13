#!/usr/bin/env bash
# Mock command helpers for BATS tests.
#
# Each function writes a bash case-statement script to /usr/local/bin/<name>
# in the current environment, allowing tests to intercept command invocations.
#
# Usage:
#   mock_command             SCRIPT ARG1 OUTPUT1 RC1 [ARG2 OUTPUT2 RC2 ...]
#   mock_command_2           SCRIPT ARG1 OUTPUT1 RC1 [ARG2 OUTPUT2 RC2 ...]
#   mock_command_passthrough SCRIPT ARG1 OUTPUT1 RC1 [...]
#
# mock_command:         matches on $1 (first argument); unquoted case pattern
# mock_command_2:       matches on "$1 $2" (first two args joined); quoted pattern
# mock_command_passthrough: like mock_command but falls through to real binary
#
# Use '*' as ARG for a catch-all case (only works in mock_command and
# mock_command_passthrough; in mock_command_2 it matches the literal string '*').
#
# Write a generated script to /usr/local/bin and clear its log file.
_write_mock_local() {
    local script_name="$1" script_content="$2"
    printf '%s' "$script_content" > "/usr/local/bin/${script_name}"
    chmod +x "/usr/local/bin/${script_name}"
    rm -f "/var/log/${script_name}"
}

# mock_command — matches on $1
mock_command() {
    local script_name="$1"
    shift

    local script
    script='#!/bin/bash -e'$'\n'
    script+="echo \"\$0 \$@\" >> /var/log/${script_name}"$'\n'
    script+='case "$1" in'$'\n'

    while (( $# >= 3 )); do
        local arg="$1" output="$2" rc="$3"
        shift 3
        script+="    ${arg})"$'\n'
        script+="    echo ${output}"$'\n'
        script+="    exit ${rc}"$'\n'
        script+="    ;;"$'\n'
    done
    script+='esac'$'\n'

    _write_mock_local "$script_name" "$script"
}

# mock_command_2 — matches on "$1 $2" (quoted pattern, quoted echo output)
mock_command_2() {
    local script_name="$1"
    shift

    local script
    script='#!/bin/bash -e'$'\n'
    script+="echo \"\$0 \$@\" >> /var/log/${script_name}"$'\n'
    script+='case "$1 $2" in'$'\n'

    while (( $# >= 3 )); do
        local arg="$1" output="$2" rc="$3"
        shift 3
        script+="    \"${arg}\")"$'\n'
        script+="    echo \"${output}\""$'\n'
        script+="    exit ${rc}"$'\n'
        script+="    ;;"$'\n'
    done
    script+='esac'$'\n'

    _write_mock_local "$script_name" "$script"
}

# mock_command_passthrough — matches on $1; falls through to real binary for
# unmatched arguments
mock_command_passthrough() {
    local script_name="$1"
    shift

    # Find the real binary path before we shadow it
    local orig_path
    orig_path=$(command -v "$script_name")

    local script
    script='#!/bin/bash -e'$'\n'
    script+="echo \"\$0 \$@\" >> /var/log/${script_name}"$'\n'
    script+='case "$1" in'$'\n'

    while (( $# >= 3 )); do
        local arg="$1" output="$2" rc="$3"
        shift 3
        script+="    ${arg})"$'\n'
        script+="    echo ${output}"$'\n'
        script+="    exit ${rc}"$'\n'
        script+="    ;;"$'\n'
    done
    script+='    *)'$'\n'
    script+="    ${orig_path} \"\$@\""$'\n'
    script+='    ;;'$'\n'
    script+='esac'$'\n'

    _write_mock_local "$script_name" "$script"
}
