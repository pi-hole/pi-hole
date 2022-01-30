# Basic Housekeeping rules
#  - Functions must be self contained
#  - Functions must be added in alphabetical order

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
