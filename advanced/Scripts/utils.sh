#!/usr/bin/env sh
# shellcheck disable=SC3043 #https://github.com/koalaman/shellcheck/wiki/SC3043#exceptions

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
# Takes either
#   - Three arguments: file, key, and value.
#   - Two arguments: file, and key.
#
# Checks the target file for the existence of the key
#   - If it exists, it changes the value
#   - If it does not exist, it adds the value
#
# Example usage:
# addOrEditKeyValuePair "/etc/pihole/setupVars.conf" "BLOCKING_ENABLED" "true"
#######################
addOrEditKeyValPair() {
  local file="${1}"
  local key="${2}"
  local value="${3}"

  if [ "${value}" != "" ]; then
    # value has a value, so it is a key-value pair
    if grep -q "^${key}=" "${file}"; then
      # Key already exists in file, modify the value
      sed -i "/^${key}=/c\\${key}=${value}" "${file}"
    else
      # Key does not already exist, add it and it's value
      echo "${key}=${value}" >> "${file}"
    fi
  else
    # value has no value, so it is just a key. Add it if it does not already exist
    if ! grep -q "^${key}" "${file}"; then
      # Key does not exist, add it.
      echo "${key}" >> "${file}"
    fi
  fi
}

#######################
# Takes two arguments file, and key.
# Deletes a key from target file
#
# Example usage:
# removeKey "/etc/pihole/setupVars.conf" "PIHOLE_DNS_1"
#######################
removeKey() {
  local file="${1}"
  local key="${2}"
  sed -i "/^${key}/d" "${file}"
}

#######################
# returns FTL's current telnet API port
#######################
getFTLAPIPort(){
  local FTLCONFFILE="/etc/pihole/pihole-FTL.conf"
  local DEFAULT_PORT_FILE="/run/pihole-FTL.port"
  local DEFAULT_FTL_PORT=4711
  local PORTFILE
  local ftl_api_port

  if [ -f "$FTLCONFFILE" ]; then
    # if PORTFILE is not set in pihole-FTL.conf, use the default path
    PORTFILE="$( (grep "^PORTFILE=" $FTLCONFFILE || echo "$DEFAULT_PORT_FILE") | cut -d"=" -f2-)"
  fi

  if [ -s "$PORTFILE" ]; then
    # -s: FILE exists and has a size greater than zero
    ftl_api_port=$(cat "${PORTFILE}")
    # Exploit prevention: unset the variable if there is malicious content
    # Verify that the value read from the file is numeric    
    expr "$ftl_api_port" : "[^[:digit:]]" > /dev/null && unset ftl_api_port
  fi

  # echo the port found in the portfile or default to the default port
  echo "${ftl_api_port:=$DEFAULT_FTL_PORT}"
}
