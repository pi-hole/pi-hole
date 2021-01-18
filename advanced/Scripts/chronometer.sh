#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Calculates stats and displays to an LCD
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.
LC_ALL=C
LC_NUMERIC=C

# Retrieve stats from FTL engine
pihole-FTL() {
    local ftl_port LINE
    ftl_port=$(cat /run/pihole-FTL.port 2> /dev/null)
    if [[ -n "$ftl_port" ]]; then
        # Open connection to FTL
        exec 3<>"/dev/tcp/127.0.0.1/$ftl_port"

        # Test if connection is open
        if { "true" >&3; } 2> /dev/null; then
            # Send command to FTL and ask to quit when finished
            echo -e ">$1 >quit" >&3

            # Read input until we received an empty string and the connection is
            # closed
            read -r -t 1 LINE <&3
            until [[ -z "${LINE}" ]] && [[ ! -t 3 ]]; do
                echo "$LINE" >&1
                read -r -t 1 LINE <&3
            done

            # Close connection
            exec 3>&-
            exec 3<&-
        fi
    else
        echo "0"
    fi
}

# Print spaces to align right-side additional text
printFunc() {
    local text_last

    title="$1"
    title_len="${#title}"

    text_main="$2"
    text_main_nocol="$text_main"
    if [[ "${text_main:0:1}" == "" ]]; then
        text_main_nocol=$(sed 's/\[[0-9;]\{1,5\}m//g' <<< "$text_main")
    fi
    text_main_len="${#text_main_nocol}"

    text_addn="$3"
    if [[ "$text_addn" == "last" ]]; then
        text_addn=""
        text_last="true"
    fi

    # If there is additional text, define max length of text_main
    if [[ -n "$text_addn" ]]; then
        case "$scr_cols" in
            [0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-4]) text_main_max_len="9";;
            4[5-9]) text_main_max_len="14";;
            *) text_main_max_len="19";;
        esac
    fi

    [[ -z "$text_addn" ]] && text_main_max_len="$(( scr_cols - title_len ))"

    # Remove excess characters from main text
    if [[ "$text_main_len" -gt "$text_main_max_len" ]]; then
        # Trim text without colors
        text_main_trim="${text_main_nocol:0:$text_main_max_len}"
        # Replace with trimmed text
        text_main="${text_main/$text_main_nocol/$text_main_trim}"
    fi

    # Determine amount of spaces for each line
    if [[ -n "$text_last" ]]; then
        # Move cursor to end of screen
        spc_num=$(( scr_cols - ( title_len + text_main_len ) ))
    else
        spc_num=$(( text_main_max_len - text_main_len ))
    fi

    [[ "$spc_num" -le 0 ]] && spc_num="0"
    spc=$(printf "%${spc_num}s")
    #spc="${spc// /.}" # Debug: Visualize spaces

    printf "%s%s$spc" "$title" "$text_main"

    if [[ -n "$text_addn" ]]; then
        printf "%s(%s)%s\\n" "$COL_NC$COL_DARK_GRAY" "$text_addn" "$COL_NC"
    else
        # Do not print trailing newline on final line
        [[ -z "$text_last" ]] && printf "%s\\n" "$COL_NC"
    fi
}

# Perform on first Chrono run (not for JSON formatted string)
get_init_stats() {
    calcFunc(){ awk "BEGIN {print $*}" 2> /dev/null; }

    # Convert bytes to human-readable format
    hrBytes() {
        awk '{
            num=$1;
            if(num==0) {
                print "0 B"
            } else {
                xxx=(num<0?-num:num)
                sss=(num<0?-1:1)
                split("B KB MB GB TB PB",type)
                for(i=5;yyy < 1;i--) {
                    yyy=xxx / (2^(10*i))
                }
            printf "%.0f " type[i+2], yyy*sss
            }
        }' <<< "$1";
    }

    # Convert seconds to human-readable format
    hrSecs() {
        day=$(( $1/60/60/24 )); hrs=$(( $1/3600%24 ))
        mins=$(( ($1%3600)/60 )); secs=$(( $1%60 ))
        [[ "$day" -ge "2" ]] && plu="s"
        [[ "$day" -ge "1" ]] && days="$day day${plu}, " || days=""
        printf "%s%02d:%02d:%02d\\n" "$days" "$hrs" "$mins" "$secs"
    }

    # Set Color Codes
    coltable="/opt/pihole/COL_TABLE"
    if [[ -f "${coltable}" ]]; then
        source ${coltable}
    else
        COL_NC="[0m"
        COL_DARK_GRAY="[1;30m"
        COL_LIGHT_GREEN="[1;32m"
        COL_LIGHT_BLUE="[1;34m"
        COL_LIGHT_RED="[1;31m"
        COL_YELLOW="[1;33m"
        COL_LIGHT_RED="[1;31m"
        COL_URG_RED="[39;41m"
    fi

    # Get RPi throttle state (RPi 3B only) & model number, or OS distro info
    if command -v vcgencmd &> /dev/null; then
        local sys_throttle_raw
        local sys_rev_raw

        sys_throttle_raw=$(vgt=$(sudo vcgencmd get_throttled); echo "${vgt##*x}")

        # Active Throttle Notice: https://bit.ly/2gnunOo
        if [[ "$sys_throttle_raw" != "0" ]]; then
            case "$sys_throttle_raw" in
                *0001) thr_type="${COL_YELLOW}Under Voltage";;
                *0002) thr_type="${COL_LIGHT_BLUE}Arm Freq Cap";;
                *0003) thr_type="${COL_YELLOW}UV${COL_DARK_GRAY},${COL_NC} ${COL_LIGHT_BLUE}AFC";;
                *0004) thr_type="${COL_LIGHT_RED}Throttled";;
                *0005) thr_type="${COL_YELLOW}UV${COL_DARK_GRAY},${COL_NC} ${COL_LIGHT_RED}TT";;
                *0006) thr_type="${COL_LIGHT_BLUE}AFC${COL_DARK_GRAY},${COL_NC} ${COL_LIGHT_RED}TT";;
                *0007) thr_type="${COL_YELLOW}UV${COL_DARK_GRAY},${COL_NC} ${COL_LIGHT_BLUE}AFC${COL_DARK_GRAY},${COL_NC} ${COL_LIGHT_RED}TT";;
            esac
        [[ -n "$thr_type" ]] && sys_throttle="$thr_type${COL_DARK_GRAY}"
        fi

        sys_rev_raw=$(awk '/Revision/ {print $3}' < /proc/cpuinfo)
        case "$sys_rev_raw" in
            000[2-6]) sys_model=" 1, Model B";; # 256MB
            000[7-9]) sys_model=" 1, Model A";; # 256MB
            000d|000e|000f) sys_model=" 1, Model B";; # 512MB
            0010|0013) sys_model=" 1, Model B+";; # 512MB
            0012|0015) sys_model=" 1, Model A+";; # 256MB
            a0104[0-1]|a21041|a22042) sys_model=" 2, Model B";; # 1GB
            900021) sys_model=" 1, Model A+";; # 512MB
            900032) sys_model=" 1, Model B+";; # 512MB
            90009[2-3]|920093) sys_model=" Zero";; # 512MB
            9000c1) sys_model=" Zero W";; # 512MB
            a02082|a[2-3]2082) sys_model=" 3, Model B";; # 1GB
            a020d3) sys_model=" 3, Model B+";; # 1GB
            *) sys_model="";;
        esac
        sys_type="Raspberry Pi$sys_model"
    else
        source "/etc/os-release"
        CODENAME=$(sed 's/[()]//g' <<< "${VERSION/* /}")
        sys_type="${NAME/ */} ${CODENAME^} $VERSION_ID"
    fi

    # Get core count
    sys_cores=$(grep -c "^processor" /proc/cpuinfo)

    # Test existence of clock speed file for ARM CPU
    if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" ]]; then
        scaling_freq_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    fi

    # Test existence of temperature file
    if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
        temp_file="/sys/class/thermal/thermal_zone0/temp"
    elif [[ -f "/sys/class/hwmon/hwmon0/temp1_input" ]]; then
        temp_file="/sys/class/hwmon/hwmon0/temp1_input"
    else
        temp_file=""
    fi

    # Test existence of setupVars config
    if [[ -f "/etc/pihole/setupVars.conf" ]]; then
        setupVars="/etc/pihole/setupVars.conf"
    fi
}

get_sys_stats() {
    local ph_ver_raw
    local cpu_raw
    local ram_raw
    local disk_raw

    # Update every 12 refreshes (Def: every 60s)
    count=$((count+1))
    if [[ "$count" == "1" ]] || (( "$count" % 12 == 0 )); then
        # Do not source setupVars if file does not exist
        [[ -n "$setupVars" ]] && source "$setupVars"

        mapfile -t ph_ver_raw < <(pihole -v -c 2> /dev/null | sed -n 's/^.* v/v/p')
        if [[ -n "${ph_ver_raw[0]}" ]]; then
            ph_core_ver="${ph_ver_raw[0]}"
            if [[ ${#ph_ver_raw[@]} -eq 2 ]]; then
                # AdminLTE not installed
                ph_lte_ver="(not installed)"
                ph_ftl_ver="${ph_ver_raw[1]}"
            else
                ph_lte_ver="${ph_ver_raw[1]}"
                ph_ftl_ver="${ph_ver_raw[2]}"
            fi
        else
            ph_core_ver="-1"
        fi

        sys_name=$(hostname)

        [[ -n "$TEMPERATUREUNIT" ]] && temp_unit="${TEMPERATUREUNIT^^}" || temp_unit="C"

        # Get storage stats for partition mounted on /
        read -r -a disk_raw <<< "$(df -B1 / 2> /dev/null | awk 'END{ print $3,$2,$5 }')"
        disk_used="${disk_raw[0]}"
        disk_total="${disk_raw[1]}"
        disk_perc="${disk_raw[2]}"

        net_gateway=$(ip route | grep default | cut -d ' ' -f 3 | head -n 1)

        # Get DHCP stats, if feature is enabled
        if [[ "$DHCP_ACTIVE" == "true" ]]; then
            ph_dhcp_max=$(( ${DHCP_END##*.} - ${DHCP_START##*.} + 1 ))
        fi

        # Get DNS server count
        dns_count="0"
        [[ -n "${PIHOLE_DNS_1}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_2}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_3}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_4}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_5}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_6}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_7}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_8}" ]] && dns_count=$((dns_count+1))
        [[ -n "${PIHOLE_DNS_9}" ]] && dns_count="$dns_count+"
    fi

    # Get screen size
    read -r -a scr_size <<< "$(stty size 2>/dev/null || echo 24 80)"
    scr_lines="${scr_size[0]}"
    scr_cols="${scr_size[1]}"

    # Determine Chronometer size behavior
    if [[ "$scr_cols" -ge 58 ]]; then
        chrono_width="large"
    elif [[ "$scr_cols" -gt 40 ]]; then
        chrono_width="medium"
    else
        chrono_width="small"
    fi

    # Determine max length of divider string
    scr_line_len=$(( scr_cols - 2 ))
    [[ "$scr_line_len" -ge 58 ]] && scr_line_len="58"
    scr_line_str=$(printf "%${scr_line_len}s")
    scr_line_str="${scr_line_str// /—}"

    sys_uptime=$(hrSecs "$(cut -d. -f1 /proc/uptime)")
    sys_loadavg=$(cut -d " " -f1,2,3 /proc/loadavg)

    # Get CPU usage, only counting processes over 1% as active
    # shellcheck disable=SC2009
    cpu_raw=$(ps -eo pcpu,rss --no-headers | grep -E -v "    0")
    cpu_tasks=$(wc -l <<< "$cpu_raw")
    cpu_taskact=$(sed -r "/(^ 0.)/d" <<< "$cpu_raw" | wc -l)
    cpu_perc=$(awk '{sum+=$1} END {printf "%.0f\n", sum/'"$sys_cores"'}' <<< "$cpu_raw")

    # Get CPU clock speed
    if [[ -n "$scaling_freq_file" ]]; then
        cpu_mhz=$(( $(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) / 1000 ))
    else
        cpu_mhz=$(lscpu | awk -F ":" '/MHz/ {print $2;exit}')
        cpu_mhz=$(printf "%.0f" "${cpu_mhz//[[:space:]]/}")
    fi

    # Determine whether to display CPU clock speed as MHz or GHz
    if [[ -n "$cpu_mhz" ]]; then
        [[ "$cpu_mhz" -le "999" ]] && cpu_freq="$cpu_mhz MHz" || cpu_freq="$(printf "%.1f" $(calcFunc "$cpu_mhz"/1000)) GHz"
        [[ "${cpu_freq}" == *".0"* ]] && cpu_freq="${cpu_freq/.0/}"
    fi

    # Determine color for temperature
    if [[ -n "$temp_file" ]]; then
        if [[ "$temp_unit" == "C" ]]; then
            cpu_temp=$(printf "%.0fc\\n" "$(calcFunc "$(< $temp_file) / 1000")")

            case "${cpu_temp::-1}" in
                -*|[0-9]|[1-3][0-9]) cpu_col="$COL_LIGHT_BLUE";;
                4[0-9]) cpu_col="";;
                5[0-9]) cpu_col="$COL_YELLOW";;
                6[0-9]) cpu_col="$COL_LIGHT_RED";;
                *) cpu_col="$COL_URG_RED";;
            esac

        # $COL_NC$COL_DARK_GRAY is needed for $COL_URG_RED
        cpu_temp_str=" @ $cpu_col$cpu_temp$COL_NC$COL_DARK_GRAY"

        elif [[ "$temp_unit" == "F" ]]; then
            cpu_temp=$(printf "%.0ff\\n" "$(calcFunc "($(< $temp_file) / 1000) * 9 / 5 + 32")")

            case "${cpu_temp::-1}" in
                -*|[0-9]|[0-9][0-9]) cpu_col="$COL_LIGHT_BLUE";;
                1[0-1][0-9]) cpu_col="";;
                1[2-3][0-9]) cpu_col="$COL_YELLOW";;
                1[4-5][0-9]) cpu_col="$COL_LIGHT_RED";;
                *) cpu_col="$COL_URG_RED";;
            esac

            cpu_temp_str=" @ $cpu_col$cpu_temp$COL_NC$COL_DARK_GRAY"

        else
            cpu_temp_str=$(printf " @ %.0fk\\n" "$(calcFunc "($(< $temp_file) / 1000) + 273.15")")
        fi
    else
        cpu_temp_str=""
    fi

    read -r -a ram_raw <<< "$(awk '/MemTotal:/{total=$2} /MemFree:/{free=$2} /Buffers:/{buffers=$2} /^Cached:/{cached=$2} END {printf "%.0f %.0f %.0f", (total-free-buffers-cached)*100/total, (total-free-buffers-cached)*1024, total*1024}' /proc/meminfo)"
    ram_perc="${ram_raw[0]}"
    ram_used="${ram_raw[1]}"
    ram_total="${ram_raw[2]}"

    if [[ "$(pihole status web 2> /dev/null)" == "1" ]]; then
        ph_status="${COL_LIGHT_GREEN}Active"
    else
        ph_status="${COL_LIGHT_RED}Offline"
    fi

    if [[ "$DHCP_ACTIVE" == "true" ]]; then
        local ph_dhcp_range

        ph_dhcp_range=$(seq -s "|" -f "${DHCP_START%.*}.%g" "${DHCP_START##*.}" "${DHCP_END##*.}")

        # Count dynamic leases from available range, and not static leases
        ph_dhcp_num=$(grep -cE "$ph_dhcp_range" "/etc/pihole/dhcp.leases")
        ph_dhcp_percent=$(( ph_dhcp_num * 100 / ph_dhcp_max ))
    fi
}

get_ftl_stats() {
    local stats_raw

    mapfile -t stats_raw < <(pihole-FTL "stats")
    domains_being_blocked_raw="${stats_raw[0]#* }"
    dns_queries_today_raw="${stats_raw[1]#* }"
    ads_blocked_today_raw="${stats_raw[2]#* }"
    ads_percentage_today_raw="${stats_raw[3]#* }"
    queries_forwarded_raw="${stats_raw[5]#* }"
    queries_cached_raw="${stats_raw[6]#* }"

    # Only retrieve these stats when not called from jsonFunc
    if [[ -z "$1" ]]; then
        local top_ad_raw
        local top_domain_raw
        local top_client_raw

        domains_being_blocked=$(printf "%.0f\\n" "${domains_being_blocked_raw}" 2> /dev/null)
        dns_queries_today=$(printf "%.0f\\n" "${dns_queries_today_raw}")
        ads_blocked_today=$(printf "%.0f\\n" "${ads_blocked_today_raw}")
        ads_percentage_today=$(printf "%'.0f\\n" "${ads_percentage_today_raw}")
        queries_cached_percentage=$(printf "%.0f\\n" "$(calcFunc "$queries_cached_raw * 100 / ( $queries_forwarded_raw + $queries_cached_raw )")")
        recent_blocked=$(pihole-FTL recentBlocked)
        read -r -a top_ad_raw <<< "$(pihole-FTL "top-ads (1)")"
        read -r -a top_domain_raw <<< "$(pihole-FTL "top-domains (1)")"
        read -r -a top_client_raw <<< "$(pihole-FTL "top-clients (1)")"

        top_ad="${top_ad_raw[2]}"
        top_domain="${top_domain_raw[2]}"
        if [[ "${top_client_raw[3]}" ]]; then
            top_client="${top_client_raw[3]}"
        else
            top_client="${top_client_raw[2]}"
        fi
    fi
}

get_strings() {
    # Expand or contract strings depending on screen size
    if [[ "$chrono_width" == "large" ]]; then
        phc_str="        ${COL_DARK_GRAY}Core"
        lte_str="        ${COL_DARK_GRAY}Web"
        ftl_str="        ${COL_DARK_GRAY}FTL"
        api_str="${COL_LIGHT_RED}API Offline"

        host_info="$sys_type"
        sys_info="$sys_throttle"
        sys_info2="Active: $cpu_taskact of $cpu_tasks tasks"
        used_str="Used: "
        leased_str="Leased: "
        domains_being_blocked=$(printf "%'.0f" "$domains_being_blocked")
        ads_blocked_today=$(printf "%'.0f" "$ads_blocked_today")
        dns_queries_today=$(printf "%'.0f" "$dns_queries_today")
        ph_info="Blocking: $domains_being_blocked sites"
        total_str="Total: "
    else
        phc_str=" ${COL_DARK_GRAY}Core"
        lte_str=" ${COL_DARK_GRAY}Web"
        ftl_str=" ${COL_DARK_GRAY}FTL"
        api_str="${COL_LIGHT_RED}API Down"
        ph_info="$domains_being_blocked blocked"
    fi

    [[ "$sys_cores" -ne 1 ]] && sys_cores_txt="${sys_cores}x "
    cpu_info="$sys_cores_txt$cpu_freq$cpu_temp_str"
    ram_info="$used_str$(hrBytes "$ram_used") of $(hrBytes "$ram_total")"
    disk_info="$used_str$(hrBytes "$disk_used") of $(hrBytes "$disk_total")"

    lan_info="Gateway: $net_gateway"
    dhcp_info="$leased_str$ph_dhcp_num of $ph_dhcp_max"

      ads_info="$total_str$ads_blocked_today of $dns_queries_today"
    dns_info="$dns_count DNS servers"

    [[ "$recent_blocked" == "0" ]] && recent_blocked="${COL_LIGHT_RED}FTL offline${COL_NC}"
}

chronoFunc() {
    local extra_arg="$1"
    local extra_value="$2"

    get_init_stats

    for (( ; ; )); do
        get_sys_stats
        get_ftl_stats
        get_strings

        # Strip excess development version numbers
        if [[ "$ph_core_ver" != "-1" ]]; then
            phc_ver_str="$phc_str: ${ph_core_ver%-*}${COL_NC}"
            lte_ver_str="$lte_str: ${ph_lte_ver%-*}${COL_NC}"
            ftl_ver_str="$ftl_str: ${ph_ftl_ver%-*}${COL_NC}"
        else
            phc_ver_str="$phc_str: $api_str${COL_NC}"
        fi

        # Get refresh number
        if [[ "${extra_arg}" = "refresh" ]]; then
            num="${extra_value}"
            num_str="Refresh set for every $num seconds"
        else
            num_str=""
        fi

        clear

        # Remove exit message heading on third refresh
        if [[ "$count" -le 2 ]] && [[ "${extra_arg}" != "exit" ]]; then
            echo -e " ${COL_LIGHT_GREEN}Pi-hole Chronometer${COL_NC}
            $num_str
            ${COL_LIGHT_RED}Press Ctrl-C to exit${COL_NC}
            ${COL_DARK_GRAY}$scr_line_str${COL_NC}"
        else
        echo -e "[0;1;31;91m|¯[0;1;33;93m¯[0;1;32;92m¯[0;1;32;92m(¯[0;1;36;96m)[0;1;34;94m_[0;1;35;95m|[0;1;33;93m¯[0;1;31;91m|_  [0;1;32;92m__[0;1;36;96m_|[0;1;31;91m¯[0;1;34;94m|[0;1;35;95m__[0;1;31;91m_[0m$phc_ver_str\\n[0;1;33;93m| ¯[0;1;32;92m_[0;1;36;96m/¯[0;1;34;94m|[0;1;35;95m_[0;1;31;91m| [0;1;33;93m' [0;1;32;92m\\/ [0;1;36;96m_ [0;1;34;94m\\ [0;1;35;95m/ [0;1;31;91m-[0;1;33;93m_)[0m$lte_ver_str\\n[0;1;32;92m|_[0;1;36;96m| [0;1;34;94m|_[0;1;35;95m| [0;1;33;93m|_[0;1;32;92m||[0;1;36;96m_\\[0;1;34;94m__[0;1;35;95m_/[0;1;31;91m_\\[0;1;33;93m__[0;1;32;92m_|[0m$ftl_ver_str\\n ${COL_DARK_GRAY}$scr_line_str${COL_NC}"
        fi

        printFunc "  Hostname: " "$sys_name" "$host_info"
        printFunc "    Uptime: " "$sys_uptime" "$sys_info"
        printFunc " Task Load: " "$sys_loadavg" "$sys_info2"
        printFunc " CPU usage: " "$cpu_perc%" "$cpu_info"
        printFunc " RAM usage: " "$ram_perc%" "$ram_info"
        printFunc " HDD usage: " "$disk_perc" "$disk_info"

        if [[ "$scr_lines" -gt 17 ]] && [[ "$chrono_width" != "small" ]]; then
            printFunc "  LAN addr: " "${IPV4_ADDRESS/\/*/}" "$lan_info"
        fi

        if [[ "$DHCP_ACTIVE" == "true" ]]; then
            printFunc "DHCP usage: " "$ph_dhcp_percent%" "$dhcp_info"
        fi

        printFunc "   Pi-hole: " "$ph_status" "$ph_info"
        printFunc " Ads Today: " "$ads_percentage_today%" "$ads_info"
        printFunc "Local Qrys: " "$queries_cached_percentage%" "$dns_info"

        printFunc "   Blocked: " "$recent_blocked"
        printFunc "Top Advert: " "$top_ad"

        # Provide more stats on screens with more lines
        if [[ "$scr_lines" -eq 17 ]]; then
            if [[ "$DHCP_ACTIVE" == "true" ]]; then
                printFunc "Top Domain: " "$top_domain" "last"
            else
                print_client="true"
            fi
        else
            print_client="true"
        fi

        if [[ -n "$print_client" ]]; then
            printFunc "Top Domain: " "$top_domain"
            printFunc "Top Client: " "$top_client" "last"
        fi

        # Handle exit/refresh options
        if [[ "${extra_arg}" == "exit" ]]; then
            exit 0
        else
            if [[ "${extra_arg}" == "refresh" ]]; then
                sleep "$num"
            else
                sleep 5
            fi
        fi

    done
}

jsonFunc() {
    get_ftl_stats "json"
    echo "{\"domains_being_blocked\":${domains_being_blocked_raw},\"dns_queries_today\":${dns_queries_today_raw},\"ads_blocked_today\":${ads_blocked_today_raw},\"ads_percentage_today\":${ads_percentage_today_raw}}"
}

helpFunc() {
    if [[ "$1" == "?" ]]; then
        echo "Unknown option. Please view 'pihole -c --help' for more information"
    else
        echo "Usage: pihole -c [options]
Example: 'pihole -c -j'
Calculates stats and displays to an LCD

Options:
  -j, --json          Output stats as JSON formatted string
  -r, --refresh       Set update frequency (in seconds)
  -e, --exit          Output stats and exit witout refreshing
  -h, --help          Display this help text"
  fi

  exit 0
}

if [[ $# = 0 ]]; then
    chronoFunc
fi

case "$1" in
    "-j" | "--json"    ) jsonFunc;;
    "-h" | "--help"    ) helpFunc;;
    "-r" | "--refresh" ) chronoFunc refresh "$2";;
    "-e" | "--exit"    ) chronoFunc exit;;
    *                  ) helpFunc "?";;
esac
