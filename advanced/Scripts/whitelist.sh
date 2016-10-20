#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Whitelists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.


helpFunc()
{
	echo "::: Immediately whitelists one or more domains in the hosts file"
	echo ":::"
	echo "::: Usage: pihole -w domain1 [domain2 ...]"
	echo ":::"
	echo "::: Options:"
	echo ":::  -d, --delmode			Remove domains from the whitelist"
	echo ":::  -nr, --noreload			Update Whitelist without refreshing dnsmasq"
	echo ":::  -q, --quiet				output is less verbose"
	echo ":::  -h, --help				Show this help dialog"
	echo ":::  -l, --list				Display your whitelisted domains"
	exit 1
}

if [[ $# = 0 ]]; then
	helpFunc
fi

#globals
basename=pihole
piholeDir=/etc/${basename}
blacklistScript=/opt/pihole/blacklist.sh
adList=${piholeDir}/gravity.list
whitelist=${piholeDir}/whitelist.txt
reload=true
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

PopWhitelistFile(){
	#check whitelist file exists, and if not, create it
	if [[ ! -f ${whitelist} ]];then
  	  touch ${whitelist}
	fi
	for dom in "${domList[@]}"
	do
	  if ${addmode}; then
	  	AddDomain "$dom"
	  else
	    RemoveDomain "$dom"
	  fi
	done
}

AddDomain(){
#| sed 's/\./\\./g'
	bool=false

	grep -Ex -q "$1" ${whitelist} || bool=true
	if ${bool}; then
	  #domain not found in the whitelist file, add it!
	  if ${verbose}; then
		echo -n "::: Adding $1 to $whitelist..."
	  fi
	  echo "$1" >> ${whitelist}
      if ${verbose}; then
	  	echo " done!"
	  fi
	else
		if ${verbose}; then
			echo "::: $1 already exists in $whitelist, no need to add!"
		fi
	fi
}

RemoveDomain(){

  bool=false
  grep -Ex -q "$1" ${whitelist} || bool=true
  if ${bool}; then
  	#Domain is not in the whitelist file, no need to Remove
  	if ${verbose}; then
  	echo "::: $1 is NOT whitelisted! No need to remove"
  	fi
  else
    echo "$1" | sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /'{}'(?!.)/;' ${whitelist}
    #Blacklist unwhitelisted
    ${blacklistScript} $1
  fi
}

Reload() {
	# Reload hosts file
	pihole -g -sd
}

DisplayWlist() {
	verbose=false
	echo -e " Displaying Gravity Resistant Domains \n"
	count=1
	while IFS= read -r RD
	do
		echo "${count}: $RD"
		count=$((count+1))
	done < "$whitelist"
}

###################################################

for var in "$@"
do
  case "$var" in
    "-nr"| "--noreload"  ) reload=false;;
    "-d" | "--delmode"   ) addmode=false;;
    "-q" | "--quiet"     ) verbose=false;;
    "-h" | "--help"      ) helpFunc;;
    "-l" | "--list"      ) DisplayWlist;;
    *                    ) HandleOther "$var";;
  esac
done

PopWhitelistFile

if ${reload}; then
	Reload
fi


