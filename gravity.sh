#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Compiles a list of ad-serving domains by downloading them from multiple sources
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Run this script as root or under sudo
echo ":::"

helpFunc() {
	cat << EOM
::: Pull in domains from adlists
:::
::: Usage: pihole -g
:::
::: Options:
:::  -f, --force			Force lists to be downloaded, even if they don't need updating.
:::  -h, --help				Show this help dialog
EOM
	exit 0
}


adListFile=/etc/pihole/adlists.list
adListDefault=/etc/pihole/adlists.default
whitelistScript="pihole -w"
whitelistFile=/etc/pihole/whitelist.txt
blacklistFile=/etc/pihole/blacklist.txt
readonly wildcardlist="/etc/dnsmasq.d/03-pihole-wildcard.conf"

#Source the setupVars from install script for the IP
setupVars=/etc/pihole/setupVars.conf
if [[ -f ${setupVars} ]];then
	. /etc/pihole/setupVars.conf
else
	echo "::: WARNING: /etc/pihole/setupVars.conf missing. Possible installation failure."
	echo ":::          Please run 'pihole -r', and choose the 'reconfigure' option to reconfigure."
	exit 1
fi

#Remove the /* from the end of the IPv4addr.
IPV4_ADDRESS=${IPV4_ADDRESS%/*}
IPV6_ADDRESS=${IPV6_ADDRESS}

# Variables for various stages of downloading and formatting the list
basename=pihole
piholeDir=/etc/${basename}
adList=${piholeDir}/gravity.list
localList=${piholeDir}/local.list
justDomainsExtension=domains
matterAndLight=${basename}.0.matterandlight.txt
supernova=${basename}.1.supernova.txt
preEventHorizon=list.preEventHorizon
eventHorizon=${basename}.2.supernova.txt
accretionDisc=${basename}.3.accretionDisc.txt

skipDownload=false

# Warn users still using pihole.conf that it no longer has any effect (I imagine about 2 people use it)
if [[ -r ${piholeDir}/pihole.conf ]]; then
	echo "::: pihole.conf file no longer supported. Over-rides in this file are ignored."
fi

###########################
# collapse - begin formation of pihole
gravity_collapse() {
	echo "::: Neutrino emissions detected..."
	echo ":::"
	#Decide if we're using a custom ad block list, or defaults.
	if [ -f ${adListFile} ]; then
		#custom file found, use this instead of default
		echo -n "::: Custom adList file detected. Reading..."
		sources=()
		while IFS= read -r line || [[ -n "$line" ]]; do
			#Do not read commented out or blank lines
			if [[ ${line} = \#* ]] || [[ ! ${line} ]]; then
				echo "" > /dev/null
			else
				sources+=(${line})
			fi
		done < ${adListFile}
		echo " done!"
	else
		#no custom file found, use defaults!
		echo -n "::: No custom adlist file detected, reading from default file..."
		sources=()
		while IFS= read -r line || [[ -n "$line" ]]; do
			#Do not read commented out or blank lines
			if [[ ${line} = \#* ]] || [[ ! ${line} ]]; then
				echo "" > /dev/null
			else
				sources+=(${line})
			fi
		done < ${adListDefault}
		echo " done!"
	fi
}

# patternCheck - check to see if curl downloaded any new files.
gravity_patternCheck() {
	patternBuffer=$1
	success=$2
	error=$3
	if [ $success = true ]; then
		# check if download was successful but list has not been modified
		if [ "${error}" == "304" ]; then
			echo ":::   No changes detected, transport skipped!"
		# check if the patternbuffer is a non-zero length file
		elif [[ -s "${patternBuffer}" ]]; then
			# Some of the blocklists are copyright, they need to be downloaded
			# and stored as is. They can be processed for content after they
			# have been saved.
			mv "${patternBuffer}" "${saveLocation}"
			echo ":::   List updated, transport successful!"
		else
			# Empty file -> use previously downloaded list
			echo ":::   Received empty file, using cached one (list not updated!)"
		fi
	else
		# check if cached list exists
		if [[ -r "${saveLocation}" ]]; then
			echo ":::   List download failed, using cached list (list not updated!)"
		else
			echo ":::   Download failed and no cached list available (list will not be considered)"
		fi
	fi
}

# transport - curl the specified url with any needed command extentions
gravity_transport() {
	url=$1
	cmd_ext=$2
	agent=$3

	# tmp file, so we don't have to store the (long!) lists in RAM
	patternBuffer=$(mktemp)
	heisenbergCompensator=""
	if [[ -r ${saveLocation} ]]; then
		# if domain has been saved, add file for date check to only download newer
		heisenbergCompensator="-z ${saveLocation}"
	fi

	# Silently curl url
	err=$(curl -s -L ${cmd_ext} ${heisenbergCompensator} -w %{http_code} -A "${agent}" ${url} -o ${patternBuffer})

	echo " done"
	# Analyze http response
	echo -n ":::   Status: "
	case "$err" in
		"200"  ) echo "Success (OK)"; success=true;;
		"304"  ) echo "Not modified"; success=true;;
		"403"  ) echo "Forbidden"; success=false;;
		"404"  ) echo "Not found"; success=false;;
		"408"  ) echo "Time-out"; success=false;;
		"451"  ) echo "Unavailable For Legal Reasons"; success=false;;
		"521"  ) echo "Web Server Is Down (Cloudflare)"; success=false;;
		"522"  ) echo "Connection Timed Out (Cloudflare)"; success=false;;
		"500"  ) echo "Internal Server Error"; success=false;;
		*      ) echo "Status $err"; success=false;;
	esac

	# Process result
	gravity_patternCheck "${patternBuffer}" ${success} "${err}"

}

# spinup - main gravity function
gravity_spinup() {
	echo ":::"
	# Loop through domain list.  Download each one and remove commented lines (lines beginning with '# 'or '/') and	 		# blank lines
	for ((i = 0; i < "${#sources[@]}"; i++)); do
		url=${sources[$i]}
		# Get just the domain from the URL
		domain=$(echo "${url}" | cut -d'/' -f3)

		# Save the file as list.#.domain
		saveLocation=${piholeDir}/list.${i}.${domain}.${justDomainsExtension}
		activeDomains[$i]=${saveLocation}

		agent="Mozilla/10.0"

		# Use a case statement to download lists that need special cURL commands
		# to complete properly and reset the user agent when required
		case "${domain}" in
			"adblock.mahakala.is")
			agent='Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2228.0 Safari/537.36'
			cmd_ext="-e http://forum.xda-developers.com/"
		    ;;

		    "pgl.yoyo.org")
			cmd_ext="-d mimetype=plaintext -d hostformat=hosts"
		    ;;

            # Default is a simple request
            *) cmd_ext=""
        esac
        if [[ "${skipDownload}" == false ]]; then
            echo -n "::: Getting $domain list..."
            gravity_transport "$url" "$cmd_ext" "$agent"
        fi
	done
}

# Schwarzchild - aggregate domains to one list and add blacklisted domains
gravity_Schwarzchild() {
	echo "::: "
	# Find all active domains and compile them into one file and remove CRs
	echo -n "::: Aggregating list of domains..."
	truncate -s 0 ${piholeDir}/${matterAndLight}
	for i in "${activeDomains[@]}"; do
		# Only assimilate list if it is available (download might have faild permanently)
		if [[ -r "${i}" ]]; then
			cat "${i}" | tr -d '\r' >> ${piholeDir}/${matterAndLight}
		fi
	done
	echo " done!"
}

gravity_Blacklist() {
	# Append blacklist entries to eventHorizon if they exist
	if [[ -f "${blacklistFile}" ]]; then
	    numBlacklisted=$(wc -l < "${blacklistFile}")
	    plural=; [[ "$numBlacklisted" != "1" ]] && plural=s
	    echo -n "::: Blacklisting $numBlacklisted domain${plural}..."
	    cat ${blacklistFile} >> ${piholeDir}/${eventHorizon}
	    echo " done!"
	else
	    echo "::: Nothing to blacklist!"
	fi

}

gravity_Wildcard() {
	# Return number of wildcards in output - don't actually handle wildcards
	if [[ -f "${wildcardlist}" ]]; then
	    num=$(grep -c ^ "${wildcardlist}")
	    if [[ -n "${IPV4_ADDRESS}" && -n "${IPV6_ADDRESS}" ]];then
	        let num/=2
	    fi
	    plural=; [[ "$num" != "1" ]] && plural=s
	    echo "::: Wildcard blocked domain${plural}: $numBlacklisted"
	else
	    echo "::: No wildcards used!"
	fi

}

gravity_Whitelist() {
    #${piholeDir}/${eventHorizon})
	echo ":::"
	# Prevent our sources from being pulled into the hole
	plural=; [[ "${sources[@]}" != "1" ]] && plural=s
	echo -n "::: Adding adlist source${plural} to the whitelist..."

	urls=()
	for url in "${sources[@]}"; do
		tmp=$(echo "${url}" | awk -F '/' '{print $3}')
		urls=("${urls[@]}" ${tmp})
	done
	echo " done!"

	# Ensure adlist domains are in whitelist.txt
	${whitelistScript} -nr -q "${urls[@]}" > /dev/null

    # Check whitelist.txt exists.
	if [[ -f "${whitelistFile}" ]]; then
        # Remove anything in whitelist.txt from the Event Horizon
        numWhitelisted=$(wc -l < "${whitelistFile}")
        plural=; [[ "$numWhitelisted" != "1" ]] && plural=s
        echo -n "::: Whitelisting $numWhitelisted domain${plural}..."
        #print everything from preEventHorizon into eventHorizon EXCEPT domains in whitelist.txt
        grep -F -x -v -f ${whitelistFile} ${piholeDir}/${preEventHorizon} > ${piholeDir}/${eventHorizon}
        echo " done!"
	else
	    echo "::: Nothing to whitelist!"
	fi
}

gravity_unique() {
	# Sort and remove duplicates
	echo -n "::: Removing duplicate domains...."
	sort -u  ${piholeDir}/${supernova} > ${piholeDir}/${preEventHorizon}
	echo " done!"
	numberOf=$(wc -l < ${piholeDir}/${preEventHorizon})
	echo "::: $numberOf unique domains trapped in the event horizon."
}

gravity_hostFormat() {
	# Format domain list as "192.168.x.x domain.com"
	echo -n "::: Formatting domains into a HOSTS file..."

	if [[ -f /etc/hostname ]]; then
		hostname=$(</etc/hostname)
	elif [ -x "$(command -v hostname)" ]; then
		hostname=$(hostname -f)
	else
		echo "::: Error: Unable to determine fully qualified domain name of host"
	fi
  # Check vars from setupVars.conf to see if we're using IPv4, IPv6, Or both.
  if [[ -n "${IPV4_ADDRESS}" && -n "${IPV6_ADDRESS}" ]];then

      echo -e "${IPV4_ADDRESS} ${hostname}\n${IPV6_ADDRESS} ${hostname}\n${IPV4_ADDRESS} pi.hole\n${IPV6_ADDRESS} pi.hole" > ${localList}
      # Both IPv4 and IPv6
      cat ${piholeDir}/${eventHorizon} | awk -v ipv4addr="$IPV4_ADDRESS" -v ipv6addr="$IPV6_ADDRESS" '{sub(/\r$/,""); print ipv4addr" "$0"\n"ipv6addr" "$0}' >> ${piholeDir}/${accretionDisc}

  elif [[ -n "${IPV4_ADDRESS}" && -z "${IPV6_ADDRESS}" ]];then

      echo -e "${IPV4_ADDRESS} ${hostname}\n${IPV4_ADDRESS} pi.hole" > ${localList}
      # Only IPv4
      cat ${piholeDir}/${eventHorizon} | awk -v ipv4addr="$IPV4_ADDRESS" '{sub(/\r$/,""); print ipv4addr" "$0}' >> ${piholeDir}/${accretionDisc}

  elif [[ -z "${IPV4_ADDRESS}" && -n "${IPV6_ADDRESS}" ]];then

      echo -e "${IPV6_ADDRESS} ${hostname}\n${IPV6_ADDRESS} pi.hole" > ${localList}
      # Only IPv6
      cat ${piholeDir}/${eventHorizon} | awk -v ipv6addr="$IPV6_ADDRESS" '{sub(/\r$/,""); print ipv6addr" "$0}' >> ${piholeDir}/${accretionDisc}

  elif [[ -z "${IPV4_ADDRESS}" && -z "${IPV6_ADDRESS}" ]];then
      echo "::: No IP Values found! Please run 'pihole -r' and choose reconfigure to restore values"
      exit 1
  fi

	# Copy the file over as /etc/pihole/gravity.list so dnsmasq can use it
	cp ${piholeDir}/${accretionDisc} ${adList}
	echo " done!"
}

# blackbody - remove any remnant files from script processes
gravity_blackbody() {
	# Loop through list files
	for file in ${piholeDir}/*.${justDomainsExtension}; do
		# If list is in active array then leave it (noop) else rm the list
		if [[ " ${activeDomains[@]} " =~ ${file} ]]; then
			:
		else
			rm -f "${file}"
		fi
	done
}

gravity_advanced() {
	# Remove comments and print only the domain name
	# Most of the lists downloaded are already in hosts file format but the spacing/formating is not contigious
	# This helps with that and makes it easier to read
	# It also helps with debugging so each stage of the script can be researched more in depth
	echo -n "::: Formatting list of domains to remove comments...."
	#awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' ${piholeDir}/${matterAndLight} | sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  ${piholeDir}/${supernova}
	#Above line does not correctly grab domains where comment is on the same line (e.g 'addomain.com #comment')
	#Awk -F splits on given IFS, we grab the right hand side (chops trailing #coments and /'s to grab the domain only.
	#Last awk command takes non-commented lines and if they have 2 fields, take the left field (the domain) and leave
	#+ the right (IP address), otherwise grab the single field.
	cat ${piholeDir}/${matterAndLight} | \
	    awk -F '#' '{print $1}' | \
	    awk -F '/' '{print $1}' | \
	    awk '($1 !~ /^#/) { if (NF>1) {print $2} else {print $1}}' | \
	    sed -nr -e 's/\.{2,}/./g' -e '/\./p' >  ${piholeDir}/${supernova}
	echo " done!"

	numberOf=$(wc -l < ${piholeDir}/${supernova})
	echo "::: ${numberOf} domains being pulled in by gravity..."

	gravity_unique
}

gravity_reload() {
	#Clear no longer needed files...
	echo ":::"
	echo -n "::: Cleaning up un-needed files..."
	rm ${piholeDir}/pihole.*.txt
	echo " done!"

	# Reload hosts file
	echo ":::"
	echo -n "::: Refresh lists in dnsmasq..."

	#ensure /etc/dnsmasq.d/01-pihole.conf is pointing at the correct list!
	#First escape forward slashes in the path:
	adList=${adList//\//\\\/}
	#Now replace the line in dnsmasq file
#	sed -i "s/^addn-hosts.*/addn-hosts=$adList/" /etc/dnsmasq.d/01-pihole.conf

	pihole restartdns
	echo " done!"
}

for var in "$@"; do
	case "${var}" in
		"-f" | "--force"     ) forceGrav=true;;
		"-h" | "--help"      ) helpFunc;;
		"-sd" | "--skip-download"    ) skipDownload=true;;
	esac
done

if [[ "${forceGrav}" == true ]]; then
	echo -n "::: Deleting exising list cache..."
	rm /etc/pihole/list.*
	echo " done!"
fi

#Overwrite adlists.default from /etc/.pihole in case any changes have been made. Changes should be saved in /etc/adlists.list
cp /etc/.pihole/adlists.default /etc/pihole/adlists.default
gravity_collapse
gravity_spinup
if [[ "${skipDownload}" == false ]]; then
    gravity_Schwarzchild
    gravity_advanced
else
    echo "::: Using cached Event Horizon list..."
    numberOf=$(wc -l < ${piholeDir}/${preEventHorizon})
	echo "::: $numberOf unique domains trapped in the event horizon."
fi
gravity_Whitelist
gravity_Blacklist
gravity_Wildcard

gravity_hostFormat
gravity_blackbody

gravity_reload
pihole status
