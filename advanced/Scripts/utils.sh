#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Script to hold utility functions for use in other scripts
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Basic Housekeeping rules
#  - Functions must be self contained
#  - Functions must be added in alphabetical order
#  - Functions must be documented
#  - New functions must have a test added for them in test/test_any_utils.py

#######################
# Takes three arguments key, value, and file.
# Checks the target file for the existence of the key
#   - If it exists, it changes the value
#   - If it does not exist, it adds the value
#
# Example usage:
# addOrEditKeyValuePair "BLOCKING_ENABLED" "true" "/etc/pihole/setupVars.conf"
#######################
addOrEditKeyValPair() {
  local key="${1}"
  local value="${2}"
  local file="${3}"
  if grep -q "^${key}=" "${file}"; then
    sed -i "/^${key}=/c\\${key}=${value}" "${file}"
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

#######################
# returns FTL's current telnet API port
#######################
getFTLAPIPort(){
  local -r FTLCONFFILE="/etc/pihole/pihole-FTL.conf"
  local -r DEFAULT_PORT_FILE="/run/pihole-FTL.port"
  local -r DEFAULT_FTL_PORT=4711
  local PORTFILE
  local ftl_api_port

  if [[ -f "$FTLCONFFILE" ]]; then
    # if PORTFILE is not set in pihole-FTL.conf, use the default path
    PORTFILE="$( (grep "^PORTFILE=" $FTLCONFFILE || echo "$DEFAULT_PORT_FILE") | cut -d"=" -f2-)"
  fi

  if [[ -s "$PORTFILE" ]]; then
    # -s: FILE exists and has a size greater than zero
    ftl_api_port=$(<"$PORTFILE")
    # Exploit prevention: unset the variable if there is malicious content
    # Verify that the value read from the file is numeric
    [[ "$ftl_api_port" =~ [^[:digit:]] ]] && unset ftl_api_port
  fi

  # echo the port found in the portfile or default to the default port
  echo "${ftl_api_port:=$DEFAULT_FTL_PORT}"
}
