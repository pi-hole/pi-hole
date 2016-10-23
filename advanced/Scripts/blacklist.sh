#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Blacklists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

helpFunc() {
	cat << EOM
::: Immediately blacklists one or more domains in the hosts file
:::
:::
::: Usage: pihole -b domain1 [domain2 ...]
::: Options:
:::  -d, --delmode			Remove domains from the blacklist
:::  -nr, --noreload			Update blacklist without refreshing dnsmasq
:::  -q, --quiet			output is less verbose
:::  -h, --help				Show this help dialog
:::  -l, --list				Display your blacklisted domains
EOM
	exit 1
}

if [[ $# = 0 ]]; then
	helpFunc
fi

#globals
basename=pihole
piholeDir=/etc/${basename}
adList=${piholeDir}/gravity.list
blacklist=${piholeDir}/blacklist.txt
reload=false
addmode=true
verbose=true

domList=()
domToRemoveList=()

HandleOther(){
  #check validity of domain
	validDomain=$(echo "$1" | perl -ne'print if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/')
	if [ -z "$validDomain" ]; then
		echo "::: $1 is not a valid argument or domain name"
	else
	  domList=("${domList[@]}" ${validDomain})
	fi
}

PopBlacklistFile() {
	#check blacklist file exists, and if not, create it
	if [[ ! -f ${blacklist} ]];then
  	  touch ${blacklist}
	fi
	for dom in "${domList[@]}"; do
	  if "$addmode"; then
	  	AddDomain "$dom"
	  else
	    RemoveDomain "$dom"
	  fi
	done
}

AddDomain() {
#| sed 's/\./\\./g'
	bool=false
	grep -Ex -q "$1" ${blacklist} || bool=true
	if ${bool}; then
	  #domain not found in the blacklist file, add it!
	  if ${verbose}; then
	    echo -n "::: Adding $1 to blacklist file..."
	  fi
		echo "$1" >> ${blacklist}
		reload=true
		echo " done!"
	else
	if ${verbose}; then
		echo "::: $1 already exists in $blacklist! No need to add"
		fi
	fi
}

RemoveDomain() {

  bool=false
  grep -Ex -q "$1" ${blacklist} || bool=true
  if ${bool}; then
  	#Domain is not in the blacklist file, no need to Remove
  	if ${verbose}; then
  	echo "::: $1 is NOT blacklisted! No need to remove"
  	fi
  else
    #Domain is in the blacklist file,remove it
    if ${verbose}; then
    echo "::: Un-blacklisting $dom..."
    fi
   echo "$1" | sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /'{}'(?!.)/;' ${blacklist}
   reload=true
  fi
}

Reload() {
    pihole -g -sd
}

DisplayBlist() {
	verbose=false
	echo -e " Displaying Gravity Affected Domains \n"
	count=1
	while IFS= read -r AD
	do
		echo "${count}: $AD"
		count=$((count+1))
	done < "$blacklist"
}

###################################################

for var in "$@"
do
  case "$var" in
    "-nr"| "--noreload"  ) reload=false;;
    "-d" | "--delmode"   ) addmode=false;;
    "-q" | "--quiet"     ) verbose=false;;
    "-h" | "--help"	     ) helpFunc;;
    "-l" | "--list"      ) DisplayBlist;;
    *                    ) HandleOther "$var";;
  esac
done

PopBlacklistFile

if ${reload}; then
	Reload
fi
