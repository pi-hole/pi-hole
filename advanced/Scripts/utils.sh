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
