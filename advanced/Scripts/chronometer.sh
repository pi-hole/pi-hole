#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Calculates stats and displays to an LCD
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Functions
LC_NUMERIC=C
calcFunc(){ awk "BEGIN {print $*}"; }

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

hrSecs() { 
  day=$(( $1/60/60/24 )); hrs=$(( $1/3600%24 )); mins=$(( ($1%3600)/60 )); secs=$(( $1%60 ))
  [[ "$day" -ge "2" ]] && plu="s"
  [[ "$day" -ge "1" ]] && days="$day day${plu}, " || days=""
  printf "%s%02d:%02d:%02d\n" "$days" "$hrs" "$mins" "$secs"
}

# Colour Codes
if [[ -t 1 ]] && [[ "$(tput colors)" -ge "8" ]]; then
  def="[0m"
  gry="[1;30m"
  grn="[1;32m"
  blu="[94m"
  ylw="[93m"
  red="[1;31m"
  red_urg="[39;41m"
else
  gry=""
  def=""
  grn=""
  blu=""
  ylw=""
  red=""
  red_urg=""
fi

# Variables to retrieve once-only
if [[ -n "$(which vcgencmd)" ]]; then
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
  sys_sbc="Raspberry Pi$sys_model"
fi

if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
  temp_file="/sys/class/thermal/thermal_zone0/temp"
elif [[ -f "/sys/class/hwmon/hwmon0/temp1_input" ]]; then 
  temp_file="/sys/class/hwmon/hwmon0/temp1_input"
else
  temp_file=""
fi

sys_cores=$(grep -c "^processor" /proc/cpuinfo)
[[ "$sys_cores" -ne 1 ]] && sys_cores_plu="cores" || sys_cores_plu="core"

get_sys_stats() {
  local ph_version
  local cpu_raw
  local ram_raw

  count=$((count+1))
  
  # Update every 12 refreshes (Def: every 60s)
  if [[ "$count" == "1" ]] || (( "$count" % 12 == 0 )); then
    source /etc/pihole/setupVars.conf

    ph_version=$(pihole -v -c | sed -n 's/^.* v/v/p')
    ph_core_ver=$(sed "1q;d" <<< "$ph_version")
    ph_lte_ver=$(sed "2q;d" <<< "$ph_version")
    ph_ftl_ver=$(sed "3q;d" <<< "$ph_version")
    
    sys_name=$(hostname)
    
    if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" ]]; then
      cpu_mhz=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    else
      cpu_mhz=$(lscpu | awk -F "[ .]+" '/MHz/ {print $4*1000;exit}')
    fi
    
    if [[ -n "$cpu_mhz" ]]; then
      [[ "$cpu_mhz" -le "999999" ]] && cpu_freq="$((cpu_mhz/1000)) MHz" || cpu_freq="$(calcFunc "$cpu_mhz"/1000000) Ghz"
      [[ -n "$cpu_freq" ]] && cpu_freq_txt=" @ $cpu_freq" || cpu_freq_txt=""
    fi
    
    [[ -n "$TEMPERATUREUNIT" ]] && temp_unit="$TEMPERATUREUNIT" || temp_unit="c"
    
    net_gateway=$(route -n | awk '$4 == "UG" {print $2;exit}')
    
    if [[ "$DHCP_ACTIVE" == "true" ]]; then
      ph_dhcp_eip="${DHCP_END##*.}"
      ph_dhcp_max=$(( ${DHCP_END##*.} - ${DHCP_START##*.} + 1 ))
    fi
    
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
  
  cpu_raw=$(ps -eo pcpu,rss --no-headers | /bin/grep -E -v "    0")
  cpu_tasks=$(wc -l <<< "$cpu_raw")
  cpu_taskact=$(sed -r '/(^ 0.)/d' <<< "$cpu_raw" | wc -l) # Remove processes using <1% CPU
  cpu_perc=$(awk '{sum+=$1} END {printf "%.0f\n", sum/'"$sys_cores"'}' <<< "$cpu_raw")
  
  if [[ -n "$temp_file" ]]; then
    if [[ "$temp_unit" == "C" ]]; then
      cpu_temp=$(printf "%'.0fc\n" "$(calcFunc "$(< $temp_file) / 1000")")
      case "${cpu_temp::-1}" in
        -*|[0-9]|[1-3][0-9]) cpu_tcol="$blu";;
        4[0-9]) cpu_tcol="";;
        5[0-9]) cpu_tcol="$ylw";;
        6[0-9]) cpu_tcol="$red";;
        *) cpu_tcol="$red_urg";;
      esac
      cpu_temp=", $cpu_tcol$cpu_temp$def$gry" # $def$gry is needed for $red_urg
    elif [[ "$temp_unit" == "F" ]]; then
      cpu_temp=$(printf "%'.0ff\n" "$(calcFunc "($(< $temp_file) / 1000) * 9 / 5 + 32")")
      case "${cpu_temp::-1}" in
        -*|[0-9]|[0-9][0-9]) cpu_tcol="$blu";;
        1[0-1][0-9]) cpu_tcol="";;
        1[2-3][0-9]) cpu_tcol="$ylw";;
        1[4-5][0-9]) cpu_tcol="$red";;
        *) cpu_tcol="$red_urg";;
      esac
      cpu_temp=", $cpu_tcol$cpu_temp$def$gry"
    else
      cpu_temp=$(printf ", %'.0fk\n" "$(calcFunc "($(< $temp_file) / 1000) + 273.15")")
    fi
  else
    cpu_temp=""
  fi
  
  ram_raw=$(awk '/MemTotal:/{total=$2} /MemFree:/{free=$2} /Buffers:/{buffers=$2} /^Cached:/{cached=$2} END { printf "%.0f %.0f %.0f", (total-free-buffers-cached)*100/total, (total-free-buffers-cached)*1024, total*1024}' /proc/meminfo)
  ram_perc=$(cut -d " " -f1 <<< "$ram_raw")
  ram_used=$(cut -d " " -f2 <<< "$ram_raw")
  ram_total=$(cut -d " " -f3 <<< "$ram_raw")
  
  if [[ "$(pihole status web)" == "1" ]]; then
    ph_status="${grn}Active"
  else
    ph_status="${red}Inactive"
  fi
  
  if [[ "$DHCP_ACTIVE" == "true" ]]; then
    ph_dhcp_num=$(wc -l 2> /dev/null < "/etc/pihole/dhcp.leases")
  fi
}

# Based on the length of $2, determine number of tabs placed after text
printFunc() {
  num="${#2}"
  
  # Do not count length of colour code
  [ "${2:0:1}" == "" ] && num=$((num-7))
  
  if [ "$num" -le "3" ]; then
    tab="\t\t\t"
  elif [ "$num" -le "11" ]; then
    tab="\t\t"
  elif [ "$num" -le "19" ]; then
    tab="\t"
  else
    tab=""
  fi

  # Limit string to first 20 chars to prevent overflow
  printf "%s%s$tab" "$1" "${2:0:20}"
}

function GetFTLData {
  # Open connection to FTL
  exec 3<>/dev/tcp/localhost/"$(cat /var/run/pihole-FTL.port)"

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
}

get_ftl_stats() {
  local stats_raw
  
  stats_raw=$(GetFTLData "stats")
  domains_being_blocked_raw=$(awk '/domains_being_blocked/ {print $2}' <<< "${stats_raw}")
  dns_queries_today_raw=$(awk '/dns_queries_today/ {print $2}' <<< "${stats_raw}")
  ads_blocked_today_raw=$(awk '/ads_blocked_today/ {print $2}' <<< "${stats_raw}")
  ads_percentage_today_raw=$(awk '/ads_percentage_today/ {print $2}' <<< "${stats_raw}")

  if [[ -z "$1" ]]; then
    domains_being_blocked=$(printf "%'.0f\n" "${domains_being_blocked_raw}")
    dns_queries_today=$(printf "%'.0f\n" "${dns_queries_today_raw}")
    ads_blocked_today=$(printf "%'.0f\n" "${ads_blocked_today_raw}")
    ads_percentage_today=$(printf "%'.0f\n" "${ads_percentage_today_raw}")
    
    recent_blocked=$(GetFTLData recentBlocked)
    [[ "${#recent_blocked}" -gt "41" ]] && recent_blocked="${recent_blocked:0:41}"
    top_domain=$(GetFTLData "top-domains (1)" | cut -d " " -f3)
    [[ "${#top_domain}" -gt "41" ]] && top_domain="${top_domain:0:41}"
    top_ad=$(GetFTLData "top-ads (1)" | cut -d " " -f3)
    [[ "${#top_ad}" -gt "41" ]] && top_ad="${top_ad:0:41}"
    top_client_raw=$(GetFTLData "top-clients (1)")
    top_client=$(awk '{print $4}' <<< "$top_client_raw")
    [[ -z "$top_client" ]] && top_client=$(cut -d " " -f3 <<< "$top_client_raw")
    [[ "${#top_client}" -gt "41" ]] && top_client="${top_client:0:40}" # Allows TC hostname of at least 23 chars
  fi
}


jsonFunc() {
  get_ftl_stats "1"
  echo "{\"domains_being_blocked\":${domains_being_blocked_raw},\"dns_queries_today\":${dns_queries_today_raw},\"ads_blocked_today\":${ads_blocked_today_raw},\"ads_percentage_today\":${ads_percentage_today_raw}}"
}

chronoFunc() {
  tabs -8
  for (( ; ; )); do
    get_sys_stats
    get_ftl_stats
    phc="   ${gry}Pi-hole Core: $ph_core_ver${def}"
    lte="      ${gry}AdminLTE: $ph_lte_ver${def}"
    ftl="           ${gry}FTL: $ph_ftl_ver${def}"
    clear
		echo -e " [0;1;35;95m_[0;1;31;91m__[0m [0;1;33;93m_[0m     [0;1;34;94m_[0m        [0;1;36;96m_[0m
[0;1;31;91m|[0m [0;1;33;93m_[0m [0;1;32;92m(_[0;1;36;96m)_[0;1;34;94m__[0;1;35;95m|[0m [0;1;31;91m|_[0m  [0;1;32;92m__[0;1;36;96m_|[0m [0;1;34;94m|[0;1;35;95m__[0;1;31;91m_[0m$phc
[0;1;33;93m|[0m  [0;1;32;92m_[0;1;36;96m/[0m [0;1;34;94m|_[0;1;35;95m__[0;1;31;91m|[0m [0;1;33;93m'[0m [0;1;32;92m\/[0m [0;1;36;96m_[0m [0;1;34;94m\[0m [0;1;35;95m/[0m [0;1;31;91m-[0;1;33;93m_)[0m$lte
[0;1;32;92m|_[0;1;36;96m|[0m [0;1;34;94m|_[0;1;35;95m|[0m   [0;1;33;93m|_[0;1;32;92m||[0;1;36;96m_\[0;1;34;94m__[0;1;35;95m_/[0;1;31;91m_\[0;1;33;93m__[0;1;32;92m_|[0m$ftl
 ${gry}——————————————————————————————————————————————————————————${def}"
    
    printFunc "  Hostname: " "$sys_name"
    [ -n "$sys_sbc" ] && printf "%s(%s)%s\n"  "$gry" "$sys_sbc" "$def" || printf "\n"
    printf "%s\n" "    Uptime: $sys_uptime"
    printFunc " Task Load: " "$sys_loadavg"
    printf "%s(%s)%s\n" "$gry" "Active: $cpu_taskact of $cpu_tasks tasks" "$def"
    printFunc " CPU usage: " "$cpu_perc%"
    printf "%s(%s)%s\n" "$gry" "$sys_cores $sys_cores_plu$cpu_freq_txt$cpu_temp" "$def"
    printFunc " RAM usage: " "$ram_perc%"
    printf "%s(%s)%s\n" "$gry" "Used $(hrBytes "$ram_used") of $(hrBytes "$ram_total")" "$def"
    printFunc "  LAN addr: " "${IPV4_ADDRESS:0:-3}"
    printf "%s(%s)%s\n" "$gry" "Gateway: $net_gateway" "$def"
    if [[ "$DHCP_ACTIVE" == "true" ]]; then
      printFunc "      DHCP: " "$DHCP_START to $ph_dhcp_eip"
      printf "%s(%s)%s\n" "$gry" "Leased: $ph_dhcp_num of $ph_dhcp_max" "$def"
    fi
    printFunc "   Pi-hole: " "$ph_status"
    printf "%s(%s)%s\n" "$gry" "Blocking: $domains_being_blocked sites" "$def"
    printFunc " Ads Today: " "$ads_percentage_today%"
    printf "%s(%s)%s\n" "$gry" "$ads_blocked_today of $dns_queries_today queries" "$def"
    printFunc "   Fwd DNS: " "$PIHOLE_DNS_1"
    printf "%s(%s)%s\n" "$gry" "Alt DNS: $ph_alts" "$def"
    
    echo -e " ${gry}——————————————————————————————————————————————————————————${def}"
    echo " Recently blocked: $recent_blocked"
    echo "   Top Advertiser: $top_ad"
    echo "       Top Domain: $top_domain"
    echo "       Top Client: $top_client"
    
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
