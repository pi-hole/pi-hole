#!/usr/bin/env sh

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
#  - Functions should be grouped with other similar functions
#  - Functions must be documented
#  - New functions must have a test added for them in test/test_any_utils.py

#######################
# Takes Three arguments: file, key, and value.
#
# Checks the target file for the existence of the key
#   - If it exists, it changes the value
#   - If it does not exist, it adds the value
#
# Example usage:
# addOrEditKeyValPair "/etc/pihole/setupVars.conf" "BLOCKING_ENABLED" "true"
#######################
addOrEditKeyValPair() {
  local file="${1}"
  local key="${2}"
  local value="${3}"

  # touch file to prevent grep error if file does not exist yet
  touch "${file}"

  if grep -q "^${key}=" "${file}"; then
    # Key already exists in file, modify the value
    sed -i "/^${key}=/c\\${key}=${value}" "${file}"
  else
    # Key does not already exist, add it and it's value
    echo "${key}=${value}" >> "${file}"
  fi
}

#######################
# Safely loads key=value pairs from the Pi-hole versions cache file.
# Unlike `source`, this function never executes file content as shell code.
# Only known keys are assigned, and values are validated against a strict
# character allowlist to prevent shell injection.
#
# Takes one argument: path to the versions file
# Returns 0 in all cases (compatible with set -e)
# Example loadVersionFile "/etc/pihole/versions"
#######################
loadVersionFile() {
  local file="${1}"
  local line key value

  [ -f "${file}" ] || return 0

  while IFS= read -r line || [ -n "${line}" ]; do
    # Skip blank lines and comments
    case "${line}" in
      ''|\#*) continue ;;
    esac

    # Require KEY=VALUE format (key must be non-empty)
    key="${line%%=*}"
    value="${line#*=}"
    [ -z "${key}" ] && continue
    [ "${key}" = "${line}" ] && continue  # no '=' found

    # Allowlist: only assign known version-file keys
    case "${key}" in
      CORE_VERSION|CORE_BRANCH|CORE_HASH|\
      GITHUB_CORE_VERSION|GITHUB_CORE_HASH|\
      WEB_VERSION|WEB_BRANCH|WEB_HASH|\
      GITHUB_WEB_VERSION|GITHUB_WEB_HASH|\
      FTL_VERSION|FTL_BRANCH|FTL_HASH|\
      GITHUB_FTL_VERSION|GITHUB_FTL_HASH|\
      DOCKER_VERSION|GITHUB_DOCKER_VERSION) ;;
      *) continue ;;
    esac

    # Validate value: allow only characters safe in version strings and branch names.
    # Permits: letters, digits, dot, hyphen, underscore, slash, plus sign, and empty string.
    case "${value}" in
      *[!a-zA-Z0-9._/+\-]*) continue ;;
    esac

    # Safe to assign: key is from the allowlist, value contains no shell metacharacters
    eval "${key}=\${value}"
  done < "${file}"
}

#######################
# returns FTL's PID based on the content of the pihole-FTL.pid file
#
# Takes one argument: path to pihole-FTL.pid
# Example getFTLPID "/run/pihole-FTL.pid"
#######################
getFTLPID() {
    local FTL_PID_FILE="${1}"
    local FTL_PID

    if [ -s "${FTL_PID_FILE}" ]; then
        # -s: FILE exists and has a size greater than zero
        FTL_PID="$(cat "${FTL_PID_FILE}")"
        # Exploit prevention: unset the variable if there is malicious content
        # Verify that the value read from the file is numeric
        expr "${FTL_PID}" : "[^[:digit:]]" > /dev/null && unset FTL_PID
    fi

    # If FTL is not running, or the PID file contains malicious stuff, substitute
    # negative PID to signal this
    FTL_PID=${FTL_PID:=-1}
    echo  "${FTL_PID}"
}

#######################
# returns value from FTLs config file using pihole-FTL --config
#
# Takes one argument: key
# Example getFTLConfigValue dns.piholePTR
#######################
getFTLConfigValue(){
  # Pipe to cat to avoid pihole-FTL assuming this is an interactive command
  # returning colored output.
  pihole-FTL --config -q "${1}" | cat
}

#######################
# sets value in FTLs config file using pihole-FTL --config
#
# Takes two arguments: key and value
# Example setFTLConfigValue dns.piholePTR PI.HOLE
#
# Note, for complex values such as dns.upstreams, you should wrap the value in single quotes:
# setFTLConfigValue dns.upstreams '[ "8.8.8.8" , "8.8.4.4" ]'
#######################
setFTLConfigValue(){
    local err
    { pihole-FTL --config "${1}" "${2}" >/dev/null; err="$?"; } || true

    case $err in
    0) ;;
    5)
        # FTL returns 5 if the value was set by an environment variable and is therefore read-only
        printf "  %s %s set by environment variable. Please unset it to use this function\n" "${CROSS}" "${1}";
        exit 5;;
    *)
        printf "  %s Failed to set %s. Try with sudo power\n" "${CROSS}" "${1}"
        exit 1
    esac
}
