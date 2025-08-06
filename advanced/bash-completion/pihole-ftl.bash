#!/bin/bash
#
# Bash completion script for pihole-FTL
#
# This completion script provides tab completion for some pihole-FTL CLI flags and commands.
_pihole_ftl_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Selected commands and flags
    opts="version tag branch help dnsmasq-test regex-test lua sqlite3 --config --teleporter --gen-x509 --read-x509 gravity ntp gzip dhcp-discover arp-scan idn2 sha256sum verify --default-gateway"

    # Handle subcommands for specific commands
    case "${prev}" in
        # Gravity subcommands
        gravity)
            mapfile -t COMPREPLY < <(compgen -W "checkList" -- "${cur}")
            return 0
            ;;

        # SQLite3 special modes
        sqlite3)
            mapfile -t COMPREPLY < <(compgen -W "-h -ni" -- "${cur}")
            return 0
            ;;

        # ARP scan options
        arp-scan)
            mapfile -t COMPREPLY < <(compgen -W "-a -x" -- "${cur}")
            return 0
            ;;

        # IDN2 options
        idn2)
            mapfile -t COMPREPLY < <(compgen -W "--decode" -- "${cur}")
            return 0
            ;;

        # NTP options
        ntp)
            mapfile -t COMPREPLY < <(compgen -W "--update" -- "${cur}")
            return 0
            ;;

    esac
    # Default completion
    mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
}

# Register the completion function for pihole-FTL
complete -F _pihole_ftl_completion pihole-FTL
