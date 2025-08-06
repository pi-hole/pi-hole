#!/bin/bash
#
# Bash completion script for pihole-FTL
#
# This completion script provides tab completion for pihole-FTL CLI flags and commands.
# It uses the `pihole-FTL --complete` command to generate the completion options.
_complete_FTL() { mapfile -t COMPREPLY < <(pihole-FTL --complete "${COMP_WORDS[@]}"); }

complete -F _complete_FTL pihole-FTL
