#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Whitelists and blacklists domains
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.



#globals
basename=pihole
piholeDir=/etc/${basename}
whitelist=${piholeDir}/whitelist.txt
blacklist=${piholeDir}/blacklist.txt
readonly wildcardlist="/etc/dnsmasq.d/03-pihole-wildcard.conf"
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
    elif [[ ${listMain} == ${wildcardlist} ]]; then
        letter="wild"
        word="wildcard"
    else
        letter="b"
        word="black"
    fi

	cat << EOM
::: Immediately add one or more domains to the ${word}list
:::
::: Usage: pihole -${letter} domain1 [domain2 ...]
:::
::: Options:
:::  -d, --delmode            Remove domains from the ${word}list
:::  -nr, --noreload          Update ${word}list without refreshing dnsmasq
:::  -q, --quiet              Output is less verbose
:::  -h, --help               Show this help dialog
:::  -l, --list               Display your ${word}listed domains
EOM
if [[ "${letter}" == "-wild" ]]; then
	echo ":::  -wild, --wildcard        Add wildcard entry (only blacklist)"
fi
	exit 0
}

EscapeRegexp() {
    # This way we may safely insert an arbitrary
    # string in our regular expressions
    # Also remove leading "." if present
    echo $* | sed 's/^\.*//' | sed "s/[]\.|$(){}?+*^]/\\\\&/g" | sed "s/\\//\\\\\//g"
}

HandleOther(){
	# First, convert everything to lowercase
	domain=$(sed -e "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/" <<< "$1")

	#check validity of domain
	validDomain=$(echo "${domain}" | perl -lne 'print if /(?!.*[^a-z0-9-\.].*)^((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9-]+\.)*[a-z]{2,63}/')
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
			RemoveDomain "${dom}" "${wildcardlist}"
		else
			RemoveDomain "${dom}" "${listMain}"
		fi
	done
}

AddDomain() {
	list="$2"
    domain=$(EscapeRegexp "$1")

    if [[ "${list}" == "${whitelist}" || "${list}" == "${blacklist}" ]]; then

		bool=true
		#Is the domain in the list we want to add it to?
		grep -Ex -q "${domain}" "${list}" > /dev/null 2>&1 || bool=false

		if [[ "${bool}" == false ]]; then
		  #domain not found in the whitelist file, add it!
		  if [[ "${verbose}" == true ]]; then
			echo "::: Adding $1 to $list..."
		  fi
		  reload=true
		  # Add it to the list we want to add it to
		  echo "$1" >> "${list}"
		else
	        if [[ "${verbose}" == true ]]; then
	            echo "::: ${1} already exists in ${list}, no need to add!"
	        fi
		fi

	elif [[ "${list}" == "${wildcardlist}" ]]; then

		source "${piholeDir}/setupVars.conf"
		#Remove the /* from the end of the IPv4addr.
		IPV4_ADDRESS=${IPV4_ADDRESS%/*}
		IPV6_ADDRESS=${IPV6_ADDRESS}

		bool=true
		#Is the domain in the list?
		grep -e "address=\/${domain}\/" "${wildcardlist}" > /dev/null 2>&1 || bool=false

		if [[ "${bool}" == false ]]; then
		  if [[ "${verbose}" == true ]]; then
			echo "::: Adding $1 to wildcard blacklist..."
		  fi
		  reload=true
		  echo "address=/$1/${IPV4_ADDRESS}" >> "${wildcardlist}"
		  if [[ ${#IPV6_ADDRESS} > 0 ]] ; then
		    echo "address=/$1/${IPV6_ADDRESS}" >> "${wildcardlist}"
		  fi
		else
	        if [[ "${verbose}" == true ]]; then
	            echo "::: ${1} already exists in wildcard blacklist, no need to add!"
	        fi
		fi
	fi
}

RemoveDomain() {
    list="$2"
    domain=$(EscapeRegexp "$1")

    if [[ "${list}" == "${whitelist}" || "${list}" == "${blacklist}" ]]; then

        bool=true
        #Is it in the list? Logic follows that if its whitelisted it should not be blacklisted and vice versa
        grep -Ex -q "${domain}" "${list}" > /dev/null 2>&1 || bool=false
        if [[ "${bool}" == true ]]; then
            # Remove it from the other one
            echo "::: Removing $1 from $list..."
            # /I flag: search case-insensitive
            sed -i "/${domain}/Id" "${list}"
            reload=true
        else
            if [[ "${verbose}" == true ]]; then
                echo "::: ${1} does not exist in ${list}, no need to remove!"
            fi
        fi

    elif [[ "${list}" == "${wildcardlist}" ]]; then

        bool=true
        #Is it in the list?
        grep -e "address=\/${domain}\/" "${wildcardlist}" > /dev/null 2>&1 || bool=false
        if [[ "${bool}" == true ]]; then
            # Remove it from the other one
            echo "::: Removing $1 from $list..."
            # /I flag: search case-insensitive
            sed -i "/address=\/${domain}/Id" "${list}"
            reload=true
        else
            if [[ "${verbose}" == true ]]; then
                echo "::: ${1} does not exist in ${list}, no need to remove!"
            fi
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
		"-wild" | "wildcard" ) listMain="${wildcardlist}";;
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
