#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Whitelists and blacklists domains
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

#globals
basename=pihole
piholeDir=/etc/${basename}
whitelist=${piholeDir}/whitelist.txt
blacklist=${piholeDir}/blacklist.txt
reload=false
addmode=true
verbose=true

domList=()
domToRemoveList=()

listMain=""
listAlt=""

helpFunc() {

    if [[ ${listMain} == ${whitelist} ]]; then
        letter="w"
        word="white"
    else
        letter="b"
        word="black"
    fi

	cat << EOM
::: Immediately ${word}lists one or more domains in the hosts file
:::
::: Usage: pihole -${letter} domain1 [domain2 ...]
:::
::: Options:
:::  -d, --delmode			Remove domains from the ${word}list
:::  -nr, --noreload		Update ${word}list without refreshing dnsmasq
:::  -q, --quiet			output is less verbose
:::  -h, --help				Show this help dialog
:::  -l, --list				Display your ${word}listed domains
EOM
	exit 1
}

HandleOther(){
  #check validity of domain
	validDomain=$(echo "$1" | perl -ne'print if /\b((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}\b/')
	if [ -z "${validDomain}" ]; then
		echo "::: $1 is not a valid argument or domain name"
	else
		domList=("${domList[@]}" ${validDomain})
	fi
}

PoplistFile() {
	#check whitelist file exists, and if not, create it
	if [[ ! -f ${whitelist} ]]; then
		touch ${whitelist}
	fi
	for dom in "${domList[@]}"; do
	    # Logic : If addmode then add to desired list and remove from the other; if delmode then remove from desired list but do not add to the other
		if ${addmode}; then
			AddDomain "${dom}" "${listMain}"
			RemoveDomain "${dom}" "${listAlt}"
		else
			RemoveDomain "${dom}" "${listMain}"
		fi
	done
}

AddDomain() {

	list="$2"

	bool=true
	#Is the domain in the list we want to add it to?
	grep -Ex -q "$1" ${list} || bool=false

	if [[ "${bool}" == false ]]; then
	  #domain not found in the whitelist file, add it!
	  if [[ "${verbose}" == true ]]; then
		echo "::: Adding $1 to $list..."
	  fi
	  reload=true
	  # Add it to the list we want to add it to
	  echo "$1" >> ${list}
	else
        if [[ "${verbose}" == true ]]; then
            echo "::: ${1} already exists in ${list}, no need to add!"
        fi
	fi
}

RemoveDomain() {
    list="$2"

    bool=true
    #Is it in the other list? Logic follows that if its whitelisted it should not be blacklisted and vice versa
    grep -Ex -q "$1" ${list} || bool=false
    if [[ "${bool}" == true ]]; then
        # Remove it from the other one
        echo "::: Removing $1 from $list..."
        echo "$1" | sed 's/\./\\./g' | xargs -I {} perl -i -ne'print unless /'{}'(?!.)/;' ${list}
        reload=true
    else
        if [[ "${verbose}" == true ]]; then
            echo "::: ${1} does not exist in ${list}, no need to remove!"
        fi
    fi
}

Reload() {
	# Reload hosts file
	pihole -g -sd
}

Displaylist() {
    if [[ ${listMain} == ${whitelist} ]]; then
        string="gravity resistant domains"
    else
        string="domains caught in the sinkhole"
    fi
	verbose=false
	echo -e " Displaying $string \n"
	count=1
	while IFS= read -r RD; do
		echo "${count}: ${RD}"
		count=$((count+1))
	done < "${listMain}"
	exit 0;
}

for var in "$@"; do
	case "${var}" in
	    "-w" | "whitelist"   ) listMain="${whitelist}"; listAlt="${blacklist}";;
	    "-b" | "blacklist"   ) listMain="${blacklist}"; listAlt="${whitelist}";;
		"-nr"| "--noreload"  ) reload=false;;
		"-d" | "--delmode"   ) addmode=false;;
		"-f" | "--force"     ) force=true;;
		"-q" | "--quiet"     ) verbose=false;;
		"-h" | "--help"      ) helpFunc;;
		"-l" | "--list"      ) Displaylist;;
		*                    ) HandleOther "${var}";;
	esac
done

shift

if [[ $# = 0 ]]; then
	helpFunc
fi

PoplistFile

if ${reload}; then
	Reload
fi

