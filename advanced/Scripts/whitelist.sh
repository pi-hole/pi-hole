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
webInterfaceEchos=/tmp/whitelistEchoFile

if [[ ! -f $whitelist ]];then
    touch $whitelist
fi

formatEchoes()
{
if [[ "$(whoami)" = "www-data" ]];then
    echo "$1" >> $webInterfaceEchos
else
    echo "$1"
fi
}

if [[ $# = 0 ]]; then
    # echoes go to a file for showing in the Web interface
    echo "Immediately whitelists one or more domains."
    echo "Usage: whitelist.sh domain1 [domain2 ...]"
    if [[ "$(whoami)" = "www-data" ]];then
        formatEchoes "Enter one or more space-separated FQDN."
        # If the user is www-data, the script is probably being called from the Web interface
        # Since the Web interface only displays the last echo in the script (I'm still a n00b with PHP)
        webInterfaceDisplay=$(cat $webInterfaceEchos)
        # The last echo needs to be delimited by a semi-colon so I translate newlines into semi-colons so it displays properly
        # Someone better in PHP might be able to come up with a better solution, but this is a highly-requested feature
        # This is also used later in the script, too
        echo "$webInterfaceDisplay" | tr "\n" ";"
    fi
fi

combopattern=""

# Overwrite any previously existing file so the output is always correct
echo "" > $webInterfaceEchos

# For each argument passed to this script
for var in "$@"
do
  # Start appending the echoes into the file for display in the Web interface later
  formatEchoes "Whitelisting $var..."

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
  formatEchoes "Modifying hosts file..."

  # Construct pattern to match entry in hosts file.
  # This consists of one or more IP addresses followed by the domain name.
  pattern=$(echo $combopattern | awk -F '[# \t]' '{printf "%s", "^(([0-9]+\.){3}[0-9]+ +)+("$1")$"}')

  # Output what will be removed and then actually remove
  sed -r -n 's/'"$pattern"'/  Removed: \3/p' $adList
  sed -r -i '/'"$pattern"'/d' $adList

  formatEchoes "** $# domain(s) whitelisted."

  # Only echo the semi-colon delimited echoes if the user running the script is www-data (meaning it is run the from Web interface)
  if [[ "$(whoami)" = "www-data" ]];then
      webInterfaceDisplay=$(cat $webInterfaceEchos)
      echo "$webInterfaceDisplay" | tr "\n" ";"
  fi
  # Force dnsmasq to reload /etc/pihole/gravity.list
  kill -HUP $(pidof dnsmasq)
fi
