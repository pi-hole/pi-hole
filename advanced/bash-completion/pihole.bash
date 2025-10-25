#!/bin/bash
#
# Bash completion script for pihole
#
_pihole() {
    local cur prev prev2 opts opts_lists opts_checkout opts_debug opts_logging opts_query opts_update opts_networkflush
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    prev2="${COMP_WORDS[COMP_CWORD-2]}"

    case "${prev}" in
        "pihole")
            opts="allow allow-regex allow-wild deny checkout debug disable enable flush help logging query repair regex reloaddns reloadlists setpassword status tail uninstall updateGravity updatePihole version wildcard networkflush api"
            mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
        ;;
        "allow"|"deny"|"wildcard"|"regex"|"allow-regex"|"allow-wild")
            opts_lists="\not \--delmode \--quiet \--list \--help"
            mapfile -t COMPREPLY < <(compgen -W "${opts_lists}" -- "${cur}")
        ;;
        "checkout")
            opts_checkout="core ftl web master dev"
            mapfile -t COMPREPLY < <(compgen -W "${opts_checkout}" -- "${cur}")
        ;;
        "debug")
            opts_debug="-a"
            mapfile -t COMPREPLY < <(compgen -W "${opts_debug}" -- "${cur}")
        ;;
        "logging")
            opts_logging="on off 'off noflush'"
            mapfile -t COMPREPLY < <(compgen -W "${opts_logging}" -- "${cur}")
        ;;
        "query")
            opts_query="--partial --all"
            mapfile -t COMPREPLY < <(compgen -W "${opts_query}" -- "${cur}")
        ;;
        "updatePihole"|"-up")
            opts_update="--check-only"
            mapfile -t COMPREPLY < <(compgen -W "${opts_update}" -- "${cur}")
        ;;
        "networkflush")
            opts_networkflush="--arp"
            mapfile -t COMPREPLY < <(compgen -W "${opts_networkflush}" -- "${cur}")
        ;;
        "core"|"web"|"ftl")
            if [[ "$prev2" == "checkout" ]]; then
                opts_checkout="master development"
                mapfile -t COMPREPLY < <(compgen -W "${opts_checkout}" -- "${cur}")
            else
                return 1
            fi
        ;;
        *)
        return 1
        ;;
    esac
    return 0
}
complete -F _pihole pihole
