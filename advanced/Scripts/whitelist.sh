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

HandleOther(){
  #check validity of domain
        validDomain=$(echo "$1" | perl -ne'print if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/')
        if [ -z "$validDomain" ]; then
                echo "::: $1 is not a valid argument or domain name"
        else
          domList=("${domList[@]}" ${validDomain})
        fi
}

helpFunc()
{
	echo "::: Immediately whitelists one or more domains in the hosts file"
	echo ":::"
	echo "::: Usage: pihole -w domain1 [domain2 ...]"
	echo ":::"
	echo "::: Options:"
	echo ":::  -d, --delmode			Remove domains from the whitelist"
	echo ":::  -nr, --noreload			Update Whitelist without refreshing dnsmasq"
	echo ":::  -f, --force				Force updating of the hosts files, even if there are no changes"
	echo ":::  -q, --quiet				output is less verbose"
	echo ":::  -h, --help				Show this help dialog"
	echo ":::  -l, --list				Display your whitelisted domains"
        echo ":::  -c:/path/to/file                     location of config file"
	exit 1
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
		modifyHost=true
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
    #Domain is in the whitelist file, add to a temporary array and remove from whitelist file
    #if $verbose; then
    #echo "::: Un-whitelisting $dom..."
    #fi
    domToRemoveList=("${domToRemoveList[@]}" $1)
    modifyHost=true
  fi
}

ModifyHostFile(){
  if ${addmode}; then
    #remove domains in  from hosts file
    if [[ -r ${whitelist} ]];then
      # Remove whitelist entries
      numberOf=$(cat ${whitelist} | sed '/^\s*$/d' | wc -l)
      plural=; [[ "$numberOf" != "1" ]] && plural=s
      echo ":::"
      echo -n "::: Modifying HOSTS file to whitelist $numberOf domain${plural}..."
      if [[ -n "${IPv6_address}" ]] ; then
        awk -F':' '{print $1}' ${whitelist} | while read -r line; do echo "${IPv6_address} $line"; done >> ${piholeDir}/whitelist.tmp
      fi
      if [[ -n "${IPv4_address}" ]] ; then
        awk -F':' '{print $1}' ${whitelist} | while read -r line; do echo "${IPv4_address} $line"; done >> ${piholeDir}/whitelist.tmp
      fi
      echo "l" >> ${piholeDir}/whitelist.tmp
      grep -F -x -v -f ${piholeDir}/whitelist.tmp ${adList} > ${piholeDir}/gravity.tmp
      rm ${adList}
      mv ${piholeDir}/gravity.tmp ${adList}
      rm ${piholeDir}/whitelist.tmp
      echo " done!"
    fi
  else
    #we need to add the removed domains to the hosts file
    echo ":::"
    echo "::: Modifying HOSTS file to un-whitelist domains..."
    for rdom in "${domToRemoveList[@]}"; do
      if grep -q "$rdom" ${piholeDir}/*.domains; then
        echo ":::    AdLists contain $rdom, re-adding block"
        echo -n ":::        Restoring block for $rdom on IPv4..."
        echo "$rdom" | awk -v ipv4addr="$piholeIP" '{sub(/\r$/,""); print ipv4addr" "$0}' >>${adList}
        echo " done!"
      fi
      echo -n ":::    Removing $rdom from $whitelist..."
      echo "$rdom" | sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /'{}'(?!.)/;' ${whitelist}
      echo " done!"
    done
  fi
}

Reload() {
	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."
    dnsmasqPid=$(pidof dnsmasq)

	if [[ ${dnsmasqPid} ]]; then
	    # service already running - reload config
	    if [ -x "$(command -v systemctl)" ]; then
            systemctl restart dnsmasq
        else
            service dnsmasq restart
        fi
	else
	    # service not running, start it up
	    if [ -x "$(command -v systemctl)" ]; then
            systemctl start dnsmasq
        else
            service dnsmasq start
        fi
	fi
	echo " done!"
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

#globals
modifyHost=false
reload=true
addmode=true
force=false
verbose=true

domList=()
domToRemoveList=()

for var in "$@"
do
  case "$var" in
    "-nr"| "--noreload"  ) reload=false;shift;;
    "-d" | "--delmode"   ) addmode=false;shift;;
    "-f" | "--force"     ) force=true;shift;;
    "-q" | "--quiet"     ) verbose=false;shift;;
    "-h" | "--help"      ) helpFunc;shift;;
    "-l" | "--list"      ) DisplayWlist;shift;;
    -c*                  ) setupVars=$(echo $var | cut -d ":" -f2);;
    *                    ) HandleOther "${var}";;
  esac
done


if [[ $# = 0 ]]; then
        helpFunc
fi
if [[ -z "${setupVars}" ]] ; then
  setupVars=/etc/pihole/setupVars.conf
fi
if [[ -f "${setupVars}" ]];then
    . "${setupVars}"
else
    echo "::: WARNING: ${setupVars} missing. Possible installation failure."
    echo ":::          Please run 'pihole -r', and choose the 'install' option to reconfigure."
    exit 1
fi

#remove CIDR from IPs
if [[ -n "${IPv6_address}" ]] ; then
  IPv6_address=$(echo "${IPv6_address}" | cut -f1 -d"/")
fi
if [[ -n "${IPv6_address}" ]] ; then
  IPv4_address=$(echo "${IPv4_address}" | cut -f1 -d"/")
fi

PopWhitelistFile

if ${modifyHost} || ${force}; then
	 ModifyHostFile
else
  if ${verbose}; then
	  echo ":::"
		echo "::: No changes need to be made"
	fi
	exit 1
fi

if ${reload}; then
	Reload
fi
