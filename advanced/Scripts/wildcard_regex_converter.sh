#!/bin/bash

wildcardFile="/etc/dnsmasq.d/03-pihole-wildcard.conf"

convert_wildcard_to_regex() {
  if [ ! -f "${wildcardFile}" ]; then
    return
  fi
  local addrlines domains uniquedomains
  # Obtain wildcard domains from old file
  addrlines="$(grep -oE "/.*/" ${wildcardFile})"
  # Strip "/" from domain names
  domains="$(sed 's/\///g;' <<< "${addrlines}")"
  # Remove repeated domains (may have been inserted two times due to A and AAAA blocking)
  uniquedomains="$(uniq <<< "${domains}")"
  # Automatically generate regex filters and remove old wildcards file
  awk '{print "(^)|(\\.)"$0"$"}' <<< "${uniquedomains}" >> "${regexFile}" && rm "${wildcardFile}"
}
