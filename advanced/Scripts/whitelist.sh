#!/usr/bin/env bash
# (c) 2015 by Jacob Salmela
# This file is part of Pi-hole.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

whitelist=/etc/pihole/whitelist.txt
adList=/etc/pihole/gravity.list
if [[ ! -f $whitelist ]];then
    touch $whitelist
fi

if [[ $# = 0 ]]; then
    echo "Immediately whitelists one or more domains."
    echo "Usage: whitelist.sh domain1 [domain2 ...]"
fi

combopattern=""

# For each argument passed to this script
for var in "$@"
do
  echo "Whitelisting $var..."

  # Construct basic pattern to match domain name.
  basicpattern=$(echo $var | awk -F '[# \t]' 'NF>0&&$1!="" {print ""$1""}' | sed 's/\./\\./g')

  if [[ "$basicpattern" != "" ]]; then
    # Add to the combination pattern that will be used below
    if [[ "$combopattern" != "" ]]; then combopattern="$combopattern|"; fi
    combopattern="$combopattern$basicpattern"

    # Also add the domain to the whitelist but only if it's not already present
    grep -E -q "^$basicpattern$" $whitelist \
    || echo "$var" >> $whitelist
  fi
done

# Now report on and remove matched domains
if [[ "$combopattern" != "" ]]; then
  echo "Modifying hosts file..."

  # Construct pattern to match entry in hosts file.
  # This consists of one or more IP addresses followed by the domain name.
  pattern=$(echo $combopattern | awk -F '[# \t]' '{printf "%s", "^(([0-9]+\.){3}[0-9]+ +)+("$1")$"}')

  # Output what will be removed and then actually remove
  sed -r -n 's/'"$pattern"'/  Removed: \3/p' $adList
  sed -r -i '/'"$pattern"'/d' $adList

  echo "** $# domain(s) whitelisted."
  # Force dnsmasq to reload /etc/pihole/gravity.list
  kill -HUP $(pidof dnsmasq)
fi
