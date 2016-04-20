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

if [[ $# = 0 ]]; then
	helpFunc
fi

#globals
basename=pihole
piholeDir=/etc/$basename
adList=$piholeDir/gravity.list
blacklist=$piholeDir/blacklist.txt
reload=true
addmode=true
force=false
versbose=true

domList=()
domToRemoveList=()

piholeIP="0.0.0.0"
piholeIPv6="::"

modifyHost=false

# After setting defaults, check if there's local overrides
if [[ -r $piholeDir/pihole.conf ]];then
    echo "::: Local calibration requested..."
        . $piholeDir/pihole.conf
fi

function helpFunc()
{
	  echo "::: Immediately blacklists one or more domains in the hosts file"
    echo ":::"
    echo "::: Usage: sudo pihole.sh -b domain1 [domain2 ...]"
    echo ":::"
    echo "::: Options:"
    echo ":::  -d, --delmode		Remove domains from the blacklist"
    echo ":::  -nr, --noreload		Update blacklist without refreshing dnsmasq"
    echo ":::  -f, --force			Force updating of the hosts files, even if there are no changes"
    echo ":::  -q, --quiet			output is less verbose"
    echo ":::  -h, --help			Show this help dialog"
    exit 1
}

function HandleOther(){
  #check validity of domain
	validDomain=$(echo "$1" | perl -ne'print if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/')
	if [ -z "$validDomain" ]; then
		echo "::: $1 is not a valid argument or domain name"
	else	  
	  domList=("${domList[@]}" $validDomain)
	fi
}

function PopBlacklistFile(){
	#check blacklist file exists, and if not, create it
	if [[ ! -f $blacklist ]];then
  	  touch $blacklist
	fi
	for dom in "${domList[@]}"; do
	  if "$addmode"; then
	  	AddDomain "$dom"
	  else
	    RemoveDomain "$dom"
	  fi
	done
}

function AddDomain(){
#| sed 's/\./\\./g'
	bool=false
	grep -Ex -q "$1" $blacklist || bool=true
	if $bool; then
	  #domain not found in the blacklist file, add it!
	  if $versbose; then
	  echo -n "::: Adding $1 to blacklist file..."
	  fi
		echo "$1" >> $blacklist
		modifyHost=true
		echo " done!"
	else
	if $versbose; then
		echo "::: $1 already exists in $blacklist! No need to add"
		fi
	fi
}

function RemoveDomain(){

  bool=false
  grep -Ex -q "$1" $blacklist || bool=true
  if $bool; then
  	#Domain is not in the blacklist file, no need to Remove
  	if $versbose; then
  	echo "::: $1 is NOT blacklisted! No need to remove"
  	fi
  else
    #Domain is in the blacklist file, add to a temporary array
    if $versbose; then
    echo "::: Un-blacklisting $dom..."
    fi
    domToRemoveList=("${domToRemoveList[@]}" $1)
    modifyHost=true
  fi
}

function ModifyHostFile(){
	 if $addmode; then
	    #add domains to the hosts file
	    if [[ -r $blacklist ]];then
	      numberOf=$(cat $blacklist | sed '/^\s*$/d' | wc -l)
        plural=; [[ "$numberOf" != "1" ]] && plural=s
        echo ":::"
        echo -n "::: Modifying HOSTS file to blacklist $numberOf domain${plural}..."	   		    
	    	if [[ -n $piholeIPv6 ]];then	    	  
				cat $blacklist | awk -v ipv4addr="$piholeIP" -v ipv6addr="$piholeIPv6" '{sub(/\r$/,""); print ipv4addr" "$0"\n"ipv6addr" "$0}' >> $adList
	      	else	        
				cat $blacklist | awk -v ipv4addr="$piholeIP" '{sub(/\r$/,""); print ipv4addr" "$0}' >>$adList
	      	fi		    
	  	fi
	  else
		echo ":::"
	  	for dom in "${domToRemoveList[@]}"
		do
	      #we need to remove the domains from the blacklist file and the host file
			echo "::: $dom"
			echo -n ":::    removing from HOSTS file..."
	      	echo "$dom" | sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /[^.]'{}'(?!.)/;' $adList  
	      	echo " done!"
	      	echo -n ":::    removing from blackist.txt..."
	      	echo "$dom" | sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /'{}'(?!.)/;' $blacklist
	      	echo " done!"
		done
	fi
}

function Reload() {
	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."

	dnsmasqPid=$(pidof dnsmasq)

	if [[ $dnsmasqPid ]]; then
		# service already running - reload config
		sudo kill -HUP "$dnsmasqPid"
	else
		# service not running, start it up
		sudo service dnsmasq start
	fi
	echo " done!"
}

###################################################

for var in "$@"
do
  case "$var" in
    "-nr"| "--noreload"  ) reload=false;;
    "-d" | "--delmode"   ) addmode=false;;
    "-f" | "--force"     ) force=true;;
    "-q" | "--quiet"     ) versbose=false;;
    "-h" | "--help"			 ) helpFunc;;
    *                    ) HandleOther "$var";;
  esac
done

PopBlacklistFile

if $modifyHost || $force; then
	ModifyHostFile
else
  if $versbose; then
	echo "::: No changes need to be made"
	fi
	exit 1
fi

if $reload; then
	Reload
fi
