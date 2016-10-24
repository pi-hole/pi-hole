#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Calculates stats and displays to an LCD
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.


#Functions##############################################################################################################
statsUpdateJSON() {
  local x=$(curl -s http://127.0.0.1/admin/api.php?summaryRaw)
  #check if json is valid
  if echo "${x}" | python -m json.tool > /dev/null ; then
    echo "${x}"
  fi
}

statsBlockedDomains() {
  if [[ -n $1 ]] ; then
    local x=$(echo "$1" | python -c "import sys, json; print json.load(sys.stdin)['domains_being_blocked']")
    echo ${x}
  else
    echo "Error"
  fi
}

statsQueriesToday() {
  if [[ -n $1 ]] ; then
    local x=$(echo "$1" | python -c "import sys, json; print json.load(sys.stdin)['dns_queries_today']")
    echo ${x}
  else
    echo "Error"
  fi

}

statsBlockedToday() {
  if [[ -n $1 ]] ; then
    local x=$(echo "$1" | python -c "import sys, json; print json.load(sys.stdin)['ads_blocked_today']")
    echo ${x}
  else
    echo "Error"
  fi

}

statsPercentBlockedToday() {
  if [[ -n $1 ]] ; then
    local x=$(echo "$1" | python -c "import sys, json; print round(float(json.load(sys.stdin)['ads_percentage_today']), 2)")
    echo ${x}
  else
    echo "Error"
  fi

}

setupVars="/etc/pihole/setupVars.conf"
if [[ -f "${setupVars}" ]] ; then
  . "${setupVars}"
else
  echo "::: WARNING: /etc/pihole/setupVars.conf missing. Possible installation failure."
  echo ":::          Please run 'pihole -r', and choose the 'reconfigure' option to reconfigure."
  exit 1
fi

IPv4_address=${IPv4_address%/*}

center(){
  cols=$(tput cols)
  length=${#1}
  center=$(expr $cols / 2)
  halfstring=$(expr $length / 2 )
  pad=$(expr $center + $halfstring)
  printf "%${pad}s\n" "$1"
}



normalChrono() {
  for (( ; ; ))
  do
    cols=$(tput cols)
    ## prepare all lines before clear to remove flashing
    json=$(statsUpdateJSON)
    load=$(uptime | cut -d' ' -f11-)
    uptime=$(uptime | awk -F'( |,|:)+' '{if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0,"days,",h+0,"hours,",m+0,"minutes."}')
    list=$(statsBlockedDomains $json)
    hits=$(statsQueriesToday $json)
    blocked=$(statsBlockedToday $json)
    percent=$(statsPercentBlockedToday $json)
    clear
    # Displays a colorful Pi-hole logo
    echo " [0;1;35;95m_[0;1;31;91m__[0m [0;1;33;93m_[0m     [0;1;34;94m_[0m        [0;1;36;96m_[0m"
    echo "[0;1;31;91m|[0m [0;1;33;93m_[0m [0;1;32;92m(_[0;1;36;96m)_[0;1;34;94m__[0;1;35;95m|[0m [0;1;31;91m|_[0m  [0;1;32;92m__[0;1;36;96m_|[0m [0;1;34;94m|[0;1;35;95m__[0;1;31;91m_[0m"
    echo "[0;1;33;93m|[0m  [0;1;32;92m_[0;1;36;96m/[0m [0;1;34;94m|_[0;1;35;95m__[0;1;31;91m|[0m [0;1;33;93m'[0m [0;1;32;92m\/[0m [0;1;36;96m_[0m [0;1;34;94m\[0m [0;1;35;95m/[0m [0;1;31;91m-[0;1;33;93m_)[0m"
    echo "[0;1;32;92m|_[0;1;36;96m|[0m [0;1;34;94m|_[0;1;35;95m|[0m   [0;1;33;93m|_[0;1;32;92m||[0;1;36;96m_\[0;1;34;94m__[0;1;35;95m_/[0;1;31;91m_\[0;1;33;93m__[0;1;32;92m_|[0m"
    echo ""
    center ${IPv4_address}
    center ${IPv6_address}
    echo "${load}"
    echo "${uptime}"
    echo "-------------------------------"
    echo "Blocking:      ${list}"
    echo "Queries:       ${hits}"
    echo "Pi-holed:      ${blocked} (${percent})%)"
    sleep 5
  done
}


function displayHelp(){
  echo "::: Displays stats about your piHole!"
  echo ":::"
  echo "::: Usage: sudo pihole -c [optional:-j]"
  echo "::: Note: If no option is passed, then stats are displayed on screen, updated every 5 seconds"
  echo ":::"
  echo "::: Options:"
  echo ":::  -j, --json		output stats as JSON formatted string"
  echo ":::  -h, --help		display this help text"
  exit 1
}

if [[ $# = 0 ]]; then
  normalChrono
fi

for var in "$@"
do
  case "$var" in
    "-j" | "--json"  ) statsUpdateJSON;;
    "-h" | "--help"  ) displayHelp;;
    *                ) exit 1;;
  esac
done
