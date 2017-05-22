#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Calculates stats and displays to an LCD
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Retrieve stats from FTL engine
pihole-FTL() {
  ftl_port=$(cat /var/run/pihole-FTL.port 2> /dev/null)
  if [[ -n "$ftl_port" ]]; then
    # Open connection to FTL
    exec 3<>"/dev/tcp/localhost/$ftl_port"

    # Test if connection is open
    if { "true" >&3; } 2> /dev/null; then
      # Send command to FTL
      echo -e ">$1" >&3

      # Read input
      read -r -t 1 LINE <&3
      until [[ ! $? ]] || [[ "$LINE" == *"EOM"* ]]; do
         echo "$LINE" >&1
         read -r -t 1 LINE <&3
      done

      # Close connection
      exec 3>&-
      exec 3<&-
   fi
  else
    echo -e "${COL_LIGHT_RED}FTL offline${COL_NC}"
  fi
}

# Print spaces to align right-side content
printFunc() {
  txt_len="${#2}"
  
  # Reduce string length when using colour code
  [ "${2:0:1}" == "" ] && txt_len=$((txt_len-7))
  
  if [[ "$3" == "last" ]]; then
    # Prevent final line from printing trailing newline
    scr_size=( $(stty size 2>/dev/null || echo 24 80) )
    scr_width="${scr_size[1]}"
    
    title_len="${#1}"
    spc_num=$(( (scr_width - title_len) - txt_len ))
    [[ "$spc_num" -lt 0 ]] && spc_num="0"
    spc=$(printf "%${spc_num}s")
    
    printf "%s%s$spc" "$1" "$2"
  else
    # Determine number of spaces for padding
    spc_num=$(( 20 - txt_len ))
    [[ "$spc_num" -lt 0 ]] && spc_num="0"
    spc=$(printf "%${spc_num}s")

    # Print string (Max 20 characters, prevents overflow)
    printf "%s%s$spc" "$1" "${2:0:20}"
  fi
}

# Perform on first Chrono run (not for JSON formatted string)
get_init_stats() {
  LC_NUMERIC=C
  calcFunc(){ awk "BEGIN {print $*}"; }

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
    day=$(( $1/60/60/24 )); hrs=$(( $1/3600%24 )); mins=$(( ($1%3600)/60 )); secs=$(( $1%60 ))
    [[ "$day" -ge "2" ]] && plu="s"
    [[ "$day" -ge "1" ]] && days="$day day${plu}, " || days=""
    printf "%s%02d:%02d:%02d\n" "$days" "$hrs" "$mins" "$secs"
  }

  # Set Colour Codes
  coltable="/opt/pihole/COL_TABLE"
  if [[ -f "${coltable}" ]]; then
    source ${coltable}
  else
    COL_NC='[0m'
    COL_DARK_GRAY='[1;30m'
    COL_LIGHT_GREEN='[1;32m'
    COL_LIGHT_BLUE='[1;34m'
    COL_LIGHT_RED='[1;31m'
    COL_YELLOW='[1;33m'
    COL_LIGHT_RED='[1;31m'
    COL_URG_RED='[39;41m'
  fi

  # Get RPi model number, or OS distro info
  if command -v vcgencmd &> /dev/null; then
    sys_rev=$(awk '/Revision/ {print $3}' < /proc/cpuinfo)
    case "$sys_rev" in
      000[2-6]) sys_model=" 1, Model B";; # 256MB
      000[7-9]) sys_model=" 1, Model A" ;; # 256MB
      000d|000e|000f) sys_model=" 1, Model B";; # 512MB
      0010|0013) sys_model=" 1, Model B+";; # 512MB
      0012|0015) sys_model=" 1, Model A+";; # 256MB
      a0104[0-1]|a21041|a22042) sys_model=" 2, Model B";; # 1GB
      900021) sys_model=" 1, Model A+";; # 512MB
      900032) sys_model=" 1, Model B+";; # 512MB
      90009[2-3]|920093) sys_model=" Zero";; # 512MB
      9000c1) sys_model=" Zero W";; # 512MB
      a02082|a[2-3]2082) sys_model=" 3, Model B";; # 1GB
      *) sys_model="" ;;
    esac
    sys_type="Raspberry Pi$sys_model"
  else
    source "/etc/os-release"
    CODENAME=$(sed 's/[()]//g' <<< "${VERSION/* /}")
    sys_type="${NAME/ */} ${CODENAME^} $VERSION_ID"
  fi

  # Get core count
  sys_cores=$(grep -c "^processor" /proc/cpuinfo)
  [[ "$sys_cores" -ne 1 ]] && sys_cores_plu="cores" || sys_cores_plu="core"

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
    [[ -n "$setupVars" ]] && source "$setupVars"
    
    
    ph_ver_raw=($(pihole -v -c 2> /dev/null | sed -n 's/^.* v/v/p'))
    if [[ -n "${ph_ver_raw[0]}" ]]; then
      ph_core_ver="${ph_ver_raw[0]}"
      ph_lte_ver="${ph_ver_raw[1]}"
      ph_ftl_ver="${ph_ver_raw[2]}"
    else
      ph_core_ver="${COL_LIGHT_RED}API unavailable${COL_NC}"
    fi
    
    sys_name=$(hostname)
    
    [[ -n "$TEMPERATUREUNIT" ]] && temp_unit="$TEMPERATUREUNIT" || temp_unit="c"
    
    # Get storage stats for partition mounted on /
    disk_raw=($(df -B1 / 2> /dev/null | awk 'END{ print $3,$2,$5 }'))
    disk_used="${disk_raw[0]}"
    disk_total="${disk_raw[1]}"
    disk_perc="${disk_raw[2]}"
    
    net_gateway=$(route -n | awk '$4 == "UG" {print $2;exit}')
    
    # Get DHCP stats, if feature is enabled
    if [[ "$DHCP_ACTIVE" == "true" ]]; then
      ph_dhcp_eip="${DHCP_END##*.}"
      ph_dhcp_max=$(( ${DHCP_END##*.} - ${DHCP_START##*.} + 1 ))
    fi
    
    # Get alt DNS server, or print total count of alt DNS servers
    if [[ -z "${PIHOLE_DNS_3}" ]]; then
      ph_alts="${PIHOLE_DNS_2}"
    else
      dns_count="0"
      [[ -n "${PIHOLE_DNS_2}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_3}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_4}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_5}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_6}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_7}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_8}" ]] && dns_count=$((dns_count+1))
      [[ -n "${PIHOLE_DNS_9}" ]] && dns_count="$dns_count+"
      ph_alts="${dns_count} others"
    fi
  fi
  
  sys_uptime=$(hrSecs "$(cut -d. -f1 /proc/uptime)")
  sys_loadavg=$(cut -d " " -f1,2,3 /proc/loadavg)
  
  # Get CPU usage, only counting processes over 1% CPU as active
  cpu_raw=$(ps -eo pcpu,rss --no-headers | grep -E -v "    0")
  cpu_tasks=$(wc -l <<< "$cpu_raw")
  cpu_taskact=$(sed -r "/(^ 0.)/d" <<< "$cpu_raw" | wc -l)
  cpu_perc=$(awk '{sum+=$1} END {printf "%.0f\n", sum/'"$sys_cores"'}' <<< "$cpu_raw")
  
  # Get CPU clock speed
  if [[ -n "$scaling_freq_file" ]]; then
    cpu_mhz=$(( $(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) / 1000 ))
  else
    cpu_mhz=$(lscpu | awk -F "[ .]+" '/MHz/ {print $4;exit}')
  fi
  
  # Determine correct string format for CPU clock speed
  if [[ -n "$cpu_mhz" ]]; then
    [[ "$cpu_mhz" -le "999" ]] && cpu_freq="$cpu_mhz MHz" || cpu_freq="$(calcFunc "$cpu_mhz"/1000) Ghz"
    [[ -n "$cpu_freq" ]] && cpu_freq_str=" @ $cpu_freq" || cpu_freq_str=""
  fi
  
  # Determine colour for temperature
  if [[ -n "$temp_file" ]]; then
    if [[ "$temp_unit" == "C" ]]; then
      cpu_temp=$(printf "%'.0fc\n" "$(calcFunc "$(< $temp_file) / 1000")")
      
      case "${cpu_temp::-1}" in
        -*|[0-9]|[1-3][0-9]) cpu_col="$COL_LIGHT_BLUE";;
        4[0-9]) cpu_col="";;
        5[0-9]) cpu_col="$COL_YELLOW";;
        6[0-9]) cpu_col="$COL_LIGHT_RED";;
        *) cpu_col="$COL_URG_RED";;
      esac
      
      # $COL_NC$COL_DARK_GRAY is needed for $COL_URG_RED
      cpu_temp_str=", $cpu_col$cpu_temp$COL_NC$COL_DARK_GRAY"
      
    elif [[ "$temp_unit" == "F" ]]; then
      cpu_temp=$(printf "%'.0ff\n" "$(calcFunc "($(< $temp_file) / 1000) * 9 / 5 + 32")")
      
      case "${cpu_temp::-1}" in
        -*|[0-9]|[0-9][0-9]) cpu_col="$COL_LIGHT_BLUE";;
        1[0-1][0-9]) cpu_col="";;
        1[2-3][0-9]) cpu_col="$COL_YELLOW";;
        1[4-5][0-9]) cpu_col="$COL_LIGHT_RED";;
        *) cpu_col="$COL_URG_RED";;
      esac
      
      cpu_temp_str=", $cpu_col$cpu_temp$COL_NC$COL_DARK_GRAY"
      
    else
      cpu_temp_str=$(printf ", %'.0fk\n" "$(calcFunc "($(< $temp_file) / 1000) + 273.15")")
    fi
  else
    cpu_temp_str=""
  fi
  
  ram_raw=($(awk '/MemTotal:/{total=$2} /MemFree:/{free=$2} /Buffers:/{buffers=$2} /^Cached:/{cached=$2} END {printf "%.0f %.0f %.0f", (total-free-buffers-cached)*100/total, (total-free-buffers-cached)*1024, total*1024}' /proc/meminfo))
  ram_perc="${ram_raw[0]}"
  ram_used="${ram_raw[1]}"
  ram_total="${ram_raw[2]}"
  
  if [[ "$(pihole status web 2> /dev/null)" == "1" ]]; then
    ph_status="${COL_LIGHT_GREEN}Active"
  else
    ph_status="${COL_LIGHT_RED}Inactive"
  fi
  
  if [[ "$DHCP_ACTIVE" == "true" ]]; then
    ph_dhcp_num=$(wc -l 2> /dev/null < "/etc/pihole/dhcp.leases")
  fi
}

get_ftl_stats() {
  local stats_raw
  
  stats_raw=($(pihole-FTL "stats"))
  domains_being_blocked_raw="${stats_raw[1]}"
  dns_queries_today_raw="${stats_raw[3]}"
  ads_blocked_today_raw="${stats_raw[5]}"
  ads_percentage_today_raw="${stats_raw[7]}"

  # Only retrieve these stats when not called from jsonFunc
  if [[ -z "$1" ]]; then
    local recent_blocked_raw
    local top_ad_raw
    local top_domain_raw
    local top_client_raw
  
    domains_being_blocked=$(printf "%'.0f\n" "${domains_being_blocked_raw}")
    dns_queries_today=$(printf "%'.0f\n" "${dns_queries_today_raw}")
    ads_blocked_today=$(printf "%'.0f\n" "${ads_blocked_today_raw}")
    ads_percentage_today=$(printf "%'.0f\n" "${ads_percentage_today_raw}")
    
    recent_blocked_raw=$(pihole-FTL recentBlocked)
    top_ad_raw=($(pihole-FTL "top-ads (1)"))
    top_domain_raw=($(pihole-FTL "top-domains (1)"))
    top_client_raw=($(pihole-FTL "top-clients (1)"))
    
    # Limit strings to 40 characters to prevent overflow
    recent_blocked="${recent_blocked_raw:0:40}"
    top_ad="${top_ad_raw[2]:0:40}"
    top_domain="${top_domain_raw[2]:0:40}"
    [[ "${top_client_raw[3]}" ]] && top_client="${top_client_raw[3]:0:40}" || top_client="${top_client_raw[2]:0:40}"
  fi
}

chronoFunc() {
  get_init_stats
  
  for (( ; ; )); do
    get_sys_stats
    get_ftl_stats
    
    # Do not print LTE/FTL strings if API is unavailable
    ph_core_str="        ${COL_DARK_GRAY}Pi-hole: $ph_core_ver${COL_NC}"
    if [[ -n "$ph_lte_ver" ]]; then
      ph_lte_str="      ${COL_DARK_GRAY}AdminLTE: $ph_lte_ver${COL_NC}"
      ph_ftl_str="           ${COL_DARK_GRAY}FTL: $ph_ftl_ver${COL_NC}"
    fi
    
    clear
    
  	echo -e "[0;1;31;91m|¯[0;1;33;93m¯[0;1;32;92m¯[0;1;32;92m(¯[0;1;36;96m)_[0;1;34;94m_[0;1;35;95m|[0;1;33;93m¯[0;1;31;91m|_  [0;1;32;92m__[0;1;36;96m_|[0;1;31;91m¯[0;1;34;94m|[0;1;35;95m__[0;1;31;91m_[0m$ph_core_str
[0;1;33;93m| ¯[0;1;32;92m_[0;1;36;96m/¯[0;1;34;94m|_[0;1;35;95m_[0;1;31;91m| [0;1;33;93m' [0;1;32;92m\/ [0;1;36;96m_ [0;1;34;94m\ [0;1;35;95m/ [0;1;31;91m-[0;1;33;93m_)[0m$ph_lte_str
[0;1;32;92m|_[0;1;36;96m| [0;1;34;94m|_[0;1;35;95m|  [0;1;33;93m|_[0;1;32;92m||[0;1;36;96m_\[0;1;34;94m__[0;1;35;95m_/[0;1;31;91m_\[0;1;33;93m__[0;1;32;92m_|[0m$ph_ftl_str
 ${COL_DARK_GRAY}——————————————————————————————————————————————————————————${COL_NC}"

    printFunc "  Hostname: " "$sys_name"
    [ -n "$sys_type" ] && printf "%s(%s)%s\n"  "$COL_DARK_GRAY" "$sys_type" "$COL_NC" || printf "\n"
    
    printf "%s\n" "    Uptime: $sys_uptime"
    
    printFunc " Task Load: " "$sys_loadavg"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Active: $cpu_taskact of $cpu_tasks tasks" "$COL_NC"
    
    printFunc " CPU usage: " "$cpu_perc%"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "$sys_cores $sys_cores_plu$cpu_freq_str$cpu_temp_str" "$COL_NC"
    
    printFunc " RAM usage: " "$ram_perc%"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Used: $(hrBytes "$ram_used") of $(hrBytes "$ram_total")" "$COL_NC"
    
    printFunc " HDD usage: " "$disk_perc"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Used: $(hrBytes "$disk_used") of $(hrBytes "$disk_total")" "$COL_NC"
    
    printFunc "  LAN addr: " "${IPV4_ADDRESS:0:-3}"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Gateway: $net_gateway" "$COL_NC"
    
    if [[ "$DHCP_ACTIVE" == "true" ]]; then
      printFunc "      DHCP: " "$DHCP_START to $ph_dhcp_eip"
      printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Leased: $ph_dhcp_num of $ph_dhcp_max" "$COL_NC"
    fi
    
    printFunc "   Pi-hole: " "$ph_status"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Blocking: $domains_being_blocked sites" "$COL_NC"
    
    printFunc " Ads Today: " "$ads_percentage_today%"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "$ads_blocked_today of $dns_queries_today queries" "$COL_NC"
    
    printFunc "   Fwd DNS: " "$PIHOLE_DNS_1"
    printf "%s(%s)%s\n" "$COL_DARK_GRAY" "Alt DNS: $ph_alts" "$COL_NC"
    
    echo -e " ${COL_DARK_GRAY}——————————————————————————————————————————————————————————${COL_NC}"
    echo " Recently blocked: $recent_blocked"
    echo "   Top Advertiser: $top_ad"
    echo "       Top Domain: $top_domain"
    printFunc "       Top Client: " "$top_client" "last"
    
    if [[ "$1" == "exit" ]]; then
      exit 0
    else
      if [[ -n "$1" ]]; then
        sleep "${1}"
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

for var in "$@"; do
  case "$var" in
    "-j" | "--json"    ) jsonFunc;;
    "-h" | "--help"    ) helpFunc;;
    "-r" | "--refresh" ) chronoFunc "$2";;
    "-e" | "--exit"    ) chronoFunc "exit";;
    *                  ) helpFunc "?";;
  esac
done
