#!/usr/bin/env bash
# shellcheck disable=SC1090

# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Web interface settings
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly dnsmasqconfig="/etc/dnsmasq.d/01-pihole.conf"
readonly dhcpconfig="/etc/dnsmasq.d/02-pihole-dhcp.conf"
readonly FTLconf="/etc/pihole/pihole-FTL.conf"
# 03 -> wildcards
readonly dhcpstaticconfig="/etc/dnsmasq.d/04-pihole-static-dhcp.conf"
readonly dnscustomfile="/etc/pihole/custom.list"
readonly dnscustomcnamefile="/etc/dnsmasq.d/05-pihole-custom-cname.conf"

readonly gravityDBfile="/etc/pihole/gravity.db"

# Source install script for ${setupVars}, ${PI_HOLE_BIN_DIR} and valid_ip()
readonly PI_HOLE_FILES_DIR="/etc/.pihole"
# shellcheck disable=SC2034  # used in basic-install
PH_TEST="true"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"

coltable="/opt/pihole/COL_TABLE"
if [[ -f ${coltable} ]]; then
    source ${coltable}
fi

helpFunc() {
    echo "Usage: pihole -a [options]
Example: pihole -a -p password
Set options for the Admin Console

Options:
  -p, password        Set Admin Console password
  -c, celsius         Set Celsius as preferred temperature unit
  -f, fahrenheit      Set Fahrenheit as preferred temperature unit
  -k, kelvin          Set Kelvin as preferred temperature unit
  -e, email           Set an administrative contact address for the Block Page
  -h, --help          Show this help dialog
  -i, interface       Specify dnsmasq's interface listening behavior
  -l, privacylevel    Set privacy level (0 = lowest, 3 = highest)"
    exit 0
}

add_setting() {
    echo "${1}=${2}" >> "${setupVars}"
}

delete_setting() {
    sed -i "/${1}/d" "${setupVars}"
}

change_setting() {
    delete_setting "${1}"
    add_setting "${1}" "${2}"
}

addFTLsetting() {
    echo "${1}=${2}" >> "${FTLconf}"
}

deleteFTLsetting() {
    sed -i "/${1}/d" "${FTLconf}"
}

changeFTLsetting() {
    deleteFTLsetting "${1}"
    addFTLsetting "${1}" "${2}"
}

add_dnsmasq_setting() {
    if [[ "${2}" != "" ]]; then
        echo "${1}=${2}" >> "${dnsmasqconfig}"
    else
        echo "${1}" >> "${dnsmasqconfig}"
    fi
}

delete_dnsmasq_setting() {
    sed -i "/${1}/d" "${dnsmasqconfig}"
}

SetTemperatureUnit() {
    change_setting "TEMPERATUREUNIT" "${unit}"
    echo -e "  ${TICK} Set temperature unit to ${unit}"
}

HashPassword() {
    # Compute password hash twice to avoid rainbow table vulnerability
    return=$(echo -n "${1}" | sha256sum | sed 's/\s.*$//')
    return=$(echo -n "${return}" | sha256sum | sed 's/\s.*$//')
    echo "${return}"
}

SetWebPassword() {
    if [ "${SUDO_USER}" == "www-data" ]; then
        echo "Security measure: user www-data is not allowed to change webUI password!"
        echo "Exiting"
        exit 1
    fi

    if [ "${SUDO_USER}" == "lighttpd" ]; then
        echo "Security measure: user lighttpd is not allowed to change webUI password!"
        echo "Exiting"
        exit 1
    fi

    if (( ${#args[2]} > 0 )) ; then
        readonly PASSWORD="${args[2]}"
        readonly CONFIRM="${PASSWORD}"
    else
        # Prevents a bug if the user presses Ctrl+C and it continues to hide the text typed.
        # So we reset the terminal via stty if the user does press Ctrl+C
        trap '{ echo -e "\nNo password will be set" ; stty sane ; exit 1; }' INT
        read -s -r -p "Enter New Password (Blank for no password): " PASSWORD
        echo ""

    if [ "${PASSWORD}" == "" ]; then
        change_setting "WEBPASSWORD" ""
        echo -e "  ${TICK} Password Removed"
        exit 0
    fi

    read -s -r -p "Confirm Password: " CONFIRM
    echo ""
    fi

    if [ "${PASSWORD}" == "${CONFIRM}" ] ; then
        # We do not wrap this in brackets, otherwise BASH will expand any appropriate syntax
        hash=$(HashPassword "$PASSWORD")
        # Save hash to file
        change_setting "WEBPASSWORD" "${hash}"
        echo -e "  ${TICK} New password set"
    else
        echo -e "  ${CROSS} Passwords don't match. Your password has not been changed"
        exit 1
    fi
}

ProcessDNSSettings() {
    source "${setupVars}"

    delete_dnsmasq_setting "server"

    COUNTER=1
    while true ; do
        var=PIHOLE_DNS_${COUNTER}
        if [ -z "${!var}" ]; then
            break;
        fi
        add_dnsmasq_setting "server" "${!var}"
        (( COUNTER++ ))
    done

    # The option LOCAL_DNS_PORT is deprecated
    # We apply it once more, and then convert it into the current format
    if [ -n "${LOCAL_DNS_PORT}" ]; then
        add_dnsmasq_setting "server" "127.0.0.1#${LOCAL_DNS_PORT}"
        add_setting "PIHOLE_DNS_${COUNTER}" "127.0.0.1#${LOCAL_DNS_PORT}"
        delete_setting "LOCAL_DNS_PORT"
    fi

    delete_dnsmasq_setting "domain-needed"
    delete_dnsmasq_setting "expand-hosts"

    if [[ "${DNS_FQDN_REQUIRED}" == true ]]; then
        add_dnsmasq_setting "domain-needed"
        add_dnsmasq_setting "expand-hosts"
    fi

    delete_dnsmasq_setting "bogus-priv"

    if [[ "${DNS_BOGUS_PRIV}" == true ]]; then
        add_dnsmasq_setting "bogus-priv"
    fi

    delete_dnsmasq_setting "dnssec"
    delete_dnsmasq_setting "trust-anchor="

    if [[ "${DNSSEC}" == true ]]; then
        echo "dnssec
trust-anchor=.,20326,8,2,E06D44B80B8F1D39A95C0B0D7C65D08458E880409BBC683457104237C7F8EC8D
" >> "${dnsmasqconfig}"
    fi

    delete_dnsmasq_setting "host-record"

    if [ -n "${HOSTRECORD}" ]; then
        add_dnsmasq_setting "host-record" "${HOSTRECORD}"
    fi

    # Setup interface listening behavior of dnsmasq
    delete_dnsmasq_setting "interface"
    delete_dnsmasq_setting "local-service"

    if [[ "${DNSMASQ_LISTENING}" == "all" ]]; then
        # Listen on all interfaces, permit all origins
        add_dnsmasq_setting "except-interface" "nonexisting"
    elif [[ "${DNSMASQ_LISTENING}" == "local" ]]; then
        # Listen only on all interfaces, but only local subnets
        add_dnsmasq_setting "local-service"
    else
        # Listen only on one interface
        # Use eth0 as fallback interface if interface is missing in setupVars.conf
        if [ -z "${PIHOLE_INTERFACE}" ]; then
            PIHOLE_INTERFACE="eth0"
        fi

        add_dnsmasq_setting "interface" "${PIHOLE_INTERFACE}"
    fi

    if [[ "${CONDITIONAL_FORWARDING}" == true ]]; then
        # Convert legacy "conditional forwarding" to rev-server configuration
        # Remove any existing REV_SERVER settings
        delete_setting "REV_SERVER"
        delete_setting "REV_SERVER_DOMAIN"
        delete_setting "REV_SERVER_TARGET"
        delete_setting "REV_SERVER_CIDR"

        REV_SERVER=true
        add_setting "REV_SERVER" "true"

        REV_SERVER_DOMAIN="${CONDITIONAL_FORWARDING_DOMAIN}"
        add_setting "REV_SERVER_DOMAIN" "${REV_SERVER_DOMAIN}"

        REV_SERVER_TARGET="${CONDITIONAL_FORWARDING_IP}"
        add_setting "REV_SERVER_TARGET" "${REV_SERVER_TARGET}"

        #Convert CONDITIONAL_FORWARDING_REVERSE if necessary e.g:
        #          1.1.168.192.in-addr.arpa to 192.168.1.1/32
        #          1.168.192.in-addr.arpa to 192.168.1.0/24
        #          168.192.in-addr.arpa to 192.168.0.0/16
        #          192.in-addr.arpa to 192.0.0.0/8
        if [[ "${CONDITIONAL_FORWARDING_REVERSE}" == *"in-addr.arpa" ]];then
            arrRev=("${CONDITIONAL_FORWARDING_REVERSE//./ }")        
            case ${#arrRev[@]} in 
                6   )   REV_SERVER_CIDR="${arrRev[3]}.${arrRev[2]}.${arrRev[1]}.${arrRev[0]}/32";;
                5   )   REV_SERVER_CIDR="${arrRev[2]}.${arrRev[1]}.${arrRev[0]}.0/24";;
                4   )   REV_SERVER_CIDR="${arrRev[1]}.${arrRev[0]}.0.0/16";;
                3   )   REV_SERVER_CIDR="${arrRev[0]}.0.0.0/8";; 
            esac
        else
          # Set REV_SERVER_CIDR to whatever value it was set to
          REV_SERVER_CIDR="${CONDITIONAL_FORWARDING_REVERSE}"
        fi
        
        # If REV_SERVER_CIDR is not converted by the above, then use the REV_SERVER_TARGET variable to derive it
        if [ -z "${REV_SERVER_CIDR}" ]; then
            # Convert existing input to /24 subnet (preserves legacy behavior)
            # This sed converts "192.168.1.2" to "192.168.1.0/24"
            # shellcheck disable=2001
            REV_SERVER_CIDR="$(sed "s+\\.[0-9]*$+\\.0/24+" <<< "${REV_SERVER_TARGET}")"
        fi
        add_setting "REV_SERVER_CIDR" "${REV_SERVER_CIDR}"

        # Remove obsolete settings from setupVars.conf
        delete_setting "CONDITIONAL_FORWARDING"
        delete_setting "CONDITIONAL_FORWARDING_REVERSE"
        delete_setting "CONDITIONAL_FORWARDING_DOMAIN"
        delete_setting "CONDITIONAL_FORWARDING_IP"
    fi

    if [[ "${REV_SERVER}" == true ]]; then
        add_dnsmasq_setting "rev-server=${REV_SERVER_CIDR},${REV_SERVER_TARGET}"
        if [ -n "${REV_SERVER_DOMAIN}" ]; then
            add_dnsmasq_setting "server=/${REV_SERVER_DOMAIN}/${REV_SERVER_TARGET}"
        fi
    fi

    # Prevent Firefox from automatically switching over to DNS-over-HTTPS
    # This follows https://support.mozilla.org/en-US/kb/configuring-networks-disable-dns-over-https
    # (sourced 7th September 2019)
    add_dnsmasq_setting "server=/use-application-dns.net/"

    # We need to process DHCP settings here as well to account for possible
    # changes in the non-FQDN forwarding. This cannot be done in 01-pihole.conf
    # as we don't want to delete all local=/.../ lines so it's much safer to
    # simply rewrite the entire corresponding config file (which is what the
    # DHCP settings subroutie is doing)
    ProcessDHCPSettings
}

SetDNSServers() {
    # Save setting to file
    delete_setting "PIHOLE_DNS"
    IFS=',' read -r -a array <<< "${args[2]}"
    for index in "${!array[@]}"
    do
        # Replace possible "\#" by "#". This fixes AdminLTE#1427
        local ip
        ip="${array[index]//\\#/#}"

        if valid_ip "${ip}" || valid_ip6 "${ip}" ; then
            add_setting "PIHOLE_DNS_$((index+1))" "${ip}"
        else
            echo -e "  ${CROSS} Invalid IP has been passed"
            exit 1
        fi
    done

    if [[ "${args[3]}" == "domain-needed" ]]; then
        change_setting "DNS_FQDN_REQUIRED" "true"
    else
        change_setting "DNS_FQDN_REQUIRED" "false"
    fi

    if [[ "${args[4]}" == "bogus-priv" ]]; then
        change_setting "DNS_BOGUS_PRIV" "true"
    else
        change_setting "DNS_BOGUS_PRIV" "false"
    fi

    if [[ "${args[5]}" == "dnssec" ]]; then
        change_setting "DNSSEC" "true"
    else
        change_setting "DNSSEC" "false"
    fi

    if [[ "${args[6]}" == "rev-server" ]]; then
        change_setting "REV_SERVER" "true"
        change_setting "REV_SERVER_CIDR" "${args[7]}"
        change_setting "REV_SERVER_TARGET" "${args[8]}"
        change_setting "REV_SERVER_DOMAIN" "${args[9]}"
    else
        change_setting "REV_SERVER" "false"
    fi

    ProcessDNSSettings

    # Restart dnsmasq to load new configuration
    RestartDNS
}

SetExcludeDomains() {
    change_setting "API_EXCLUDE_DOMAINS" "${args[2]}"
}

SetExcludeClients() {
    change_setting "API_EXCLUDE_CLIENTS" "${args[2]}"
}

Poweroff(){
    nohup bash -c "sleep 5; poweroff" &> /dev/null </dev/null &
}

Reboot() {
    nohup bash -c "sleep 5; reboot" &> /dev/null </dev/null &
}

RestartDNS() {
    "${PI_HOLE_BIN_DIR}"/pihole restartdns
}

SetQueryLogOptions() {
    change_setting "API_QUERY_LOG_SHOW" "${args[2]}"
}

ProcessDHCPSettings() {
    source "${setupVars}"

    if [[ "${DHCP_ACTIVE}" == "true" ]]; then
    interface="${PIHOLE_INTERFACE}"

    # Use eth0 as fallback interface
    if [ -z ${interface} ]; then
        interface="eth0"
    fi

    if [[ "${PIHOLE_DOMAIN}" == "" ]]; then
        PIHOLE_DOMAIN="lan"
        change_setting "PIHOLE_DOMAIN" "${PIHOLE_DOMAIN}"
    fi

    if [[ "${DHCP_LEASETIME}" == "0" ]]; then
        leasetime="infinite"
    elif [[ "${DHCP_LEASETIME}" == "" ]]; then
        leasetime="24"
        change_setting "DHCP_LEASETIME" "${leasetime}"
    elif [[ "${DHCP_LEASETIME}" == "24h" ]]; then
        #Installation is affected by known bug, introduced in a previous version.
        #This will automatically clean up setupVars.conf and remove the unnecessary "h"
        leasetime="24"
        change_setting "DHCP_LEASETIME" "${leasetime}"
    else
        leasetime="${DHCP_LEASETIME}h"
    fi

    # Write settings to file
    echo "###############################################################################
#  DHCP SERVER CONFIG FILE AUTOMATICALLY POPULATED BY PI-HOLE WEB INTERFACE.  #
#            ANY CHANGES MADE TO THIS FILE WILL BE LOST ON CHANGE             #
###############################################################################
dhcp-authoritative
dhcp-range=${DHCP_START},${DHCP_END},${leasetime}
dhcp-option=option:router,${DHCP_ROUTER}
dhcp-leasefile=/etc/pihole/dhcp.leases
#quiet-dhcp
" > "${dhcpconfig}"
    chmod 644 "${dhcpconfig}"

    if [[ "${PIHOLE_DOMAIN}" != "none" ]]; then
        echo "domain=${PIHOLE_DOMAIN}" >> "${dhcpconfig}"

        # When there is a Pi-hole domain set and "Never forward non-FQDNs" is
        # ticked, we add `local=/domain/` to tell FTL that this domain is purely
        # local and FTL may answer queries from /etc/hosts or DHCP but should
        # never forward queries on that domain to any upstream servers
        if  [[ "${DNS_FQDN_REQUIRED}" == true ]]; then
          echo "local=/${PIHOLE_DOMAIN}/" >> "${dhcpconfig}"
        fi
    fi

    # Sourced from setupVars
    # shellcheck disable=SC2154
    if [[ "${DHCP_rapid_commit}" == "true" ]]; then
        echo "dhcp-rapid-commit" >> "${dhcpconfig}"
    fi

    if [[ "${DHCP_IPv6}" == "true" ]]; then
        echo "#quiet-dhcp6
#enable-ra
dhcp-option=option6:dns-server,[::]
dhcp-range=::100,::1ff,constructor:${interface},ra-names,slaac,${leasetime}
ra-param=*,0,0
" >> "${dhcpconfig}"
    fi

    else
        if [[ -f "${dhcpconfig}" ]]; then
            rm "${dhcpconfig}" &> /dev/null
        fi
    fi
}

EnableDHCP() {
    change_setting "DHCP_ACTIVE" "true"
    change_setting "DHCP_START" "${args[2]}"
    change_setting "DHCP_END" "${args[3]}"
    change_setting "DHCP_ROUTER" "${args[4]}"
    change_setting "DHCP_LEASETIME" "${args[5]}"
    change_setting "PIHOLE_DOMAIN" "${args[6]}"
    change_setting "DHCP_IPv6" "${args[7]}"
    change_setting "DHCP_rapid_commit" "${args[8]}"

    # Remove possible old setting from file
    delete_dnsmasq_setting "dhcp-"
    delete_dnsmasq_setting "quiet-dhcp"

    # If a DHCP client claims that its name is "wpad", ignore that.
    # This fixes a security hole. see CERT Vulnerability VU#598349
    # We also ignore "localhost" as Windows behaves strangely if a
    # device claims this host name
    add_dnsmasq_setting "dhcp-name-match=set:hostname-ignore,wpad
dhcp-name-match=set:hostname-ignore,localhost
dhcp-ignore-names=tag:hostname-ignore"

    ProcessDHCPSettings

    RestartDNS
}

DisableDHCP() {
    change_setting "DHCP_ACTIVE" "false"

    # Remove possible old setting from file
    delete_dnsmasq_setting "dhcp-"
    delete_dnsmasq_setting "quiet-dhcp"

    ProcessDHCPSettings

    RestartDNS
}

SetWebUILayout() {
    change_setting "WEBUIBOXEDLAYOUT" "${args[2]}"
}

SetWebUITheme() {
    change_setting "WEBTHEME" "${args[2]}"
}

CheckUrl(){
    local regex check_url
    # Check for characters NOT allowed in URLs
    regex="[^a-zA-Z0-9:/?&%=~._()-;]"

    # this will remove first @ that is after schema and before domain
    # \1 is optional schema, \2 is userinfo
    check_url="$( sed -re 's#([^:/]*://)?([^/]+)@#\1\2#' <<< "$1" )"

    if [[ "${check_url}" =~ ${regex} ]]; then
        return 1
    else
        return 0
    fi
}

CustomizeAdLists() {
    local address
    address="${args[3]}"
    local comment
    comment="${args[4]}"

    if CheckUrl "${address}"; then
        if [[ "${args[2]}" == "enable" ]]; then
            sqlite3 "${gravityDBfile}" "UPDATE adlist SET enabled = 1 WHERE address = '${address}'"
        elif [[ "${args[2]}" == "disable" ]]; then
            sqlite3 "${gravityDBfile}" "UPDATE adlist SET enabled = 0 WHERE address = '${address}'"
        elif [[ "${args[2]}" == "add" ]]; then
            sqlite3 "${gravityDBfile}" "INSERT OR IGNORE INTO adlist (address, comment) VALUES ('${address}', '${comment}')"
        elif [[ "${args[2]}" == "del" ]]; then
            sqlite3 "${gravityDBfile}" "DELETE FROM adlist WHERE address = '${address}'"
        else
            echo "Not permitted"
            return 1
        fi
    else
        echo "Invalid Url"
        return 1
    fi
}

SetPrivacyMode() {
    if [[ "${args[2]}" == "true" ]]; then
        change_setting "API_PRIVACY_MODE" "true"
    else
        change_setting "API_PRIVACY_MODE" "false"
    fi
}

ResolutionSettings() {
    typ="${args[2]}"
    state="${args[3]}"

    if [[ "${typ}" == "forward" ]]; then
        change_setting "API_GET_UPSTREAM_DNS_HOSTNAME" "${state}"
    elif [[ "${typ}" == "clients" ]]; then
        change_setting "API_GET_CLIENT_HOSTNAME" "${state}"
    fi
}

AddDHCPStaticAddress() {
    mac="${args[2]}"
    ip="${args[3]}"
    host="${args[4]}"

    if [[ "${ip}" == "noip" ]]; then
        # Static host name
        echo "dhcp-host=${mac},${host}" >> "${dhcpstaticconfig}"
    elif [[ "${host}" == "nohost" ]]; then
        # Static IP
        echo "dhcp-host=${mac},${ip}" >> "${dhcpstaticconfig}"
    else
        # Full info given
        echo "dhcp-host=${mac},${ip},${host}" >> "${dhcpstaticconfig}"
    fi
}

RemoveDHCPStaticAddress() {
    mac="${args[2]}"
    sed -i "/dhcp-host=${mac}.*/d" "${dhcpstaticconfig}"
}

SetAdminEmail() {
    if [[ "${1}" == "-h" ]] || [[ "${1}" == "--help" ]]; then
        echo "Usage: pihole -a email <address>
Example: 'pihole -a email admin@address.com'
Set an administrative contact address for the Block Page

Options:
  \"\"                  Empty: Remove admin contact
  -h, --help          Show this help dialog"
        exit 0
    fi

    if [[ -n "${args[2]}" ]]; then

        # Sanitize email address in case of security issues
        # Regex from https://stackoverflow.com/a/2138832/4065967
        local regex
        regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\$"
        if [[ ! "${args[2]}" =~ ${regex} ]]; then
            echo -e "  ${CROSS} Invalid email address"
            exit 0
        fi

        change_setting "ADMIN_EMAIL" "${args[2]}"
        echo -e "  ${TICK} Setting admin contact to ${args[2]}"
    else
        change_setting "ADMIN_EMAIL" ""
        echo -e "  ${TICK} Removing admin contact"
    fi
}

SetListeningMode() {
    source "${setupVars}"

    if [[ "$3" == "-h" ]] || [[ "$3" == "--help" ]]; then
        echo "Usage: pihole -a -i [interface]
Example: 'pihole -a -i local'
Specify dnsmasq's network interface listening behavior

Interfaces:
  local               Listen on all interfaces, but only allow queries from
                      devices that are at most one hop away (local devices)
  single              Listen only on ${PIHOLE_INTERFACE} interface
  all                 Listen on all interfaces, permit all origins"
        exit 0
  fi

    if [[ "${args[2]}" == "all" ]]; then
        echo -e "  ${INFO} Listening on all interfaces, permitting all origins. Please use a firewall!"
        change_setting "DNSMASQ_LISTENING" "all"
    elif [[ "${args[2]}" == "local" ]]; then
        echo -e "  ${INFO} Listening on all interfaces, permitting origins from one hop away (LAN)"
        change_setting "DNSMASQ_LISTENING" "local"
    else
        echo -e "  ${INFO} Listening only on interface ${PIHOLE_INTERFACE}"
        change_setting "DNSMASQ_LISTENING" "single"
    fi

    # Don't restart DNS server yet because other settings
    # will be applied afterwards if "-web" is set
    if [[ "${args[3]}" != "-web" ]]; then
        ProcessDNSSettings
        # Restart dnsmasq to load new configuration
        RestartDNS
    fi
}

Teleporter() {
    local datetimestamp
    datetimestamp=$(date "+%Y-%m-%d_%H-%M-%S")
    php /var/www/html/admin/scripts/pi-hole/php/teleporter.php > "pi-hole-teleporter_${datetimestamp}.tar.gz"
}

checkDomain()
{
    local domain validDomain
    # Convert to lowercase
    domain="${1,,}"
    validDomain=$(grep -P "^((-|_)*[a-z\\d]((-|_)*[a-z\\d])*(-|_)*)(\\.(-|_)*([a-z\\d]((-|_)*[a-z\\d])*))*$" <<< "${domain}") # Valid chars check
    validDomain=$(grep -P "^[^\\.]{1,63}(\\.[^\\.]{1,63})*$" <<< "${validDomain}") # Length of each label
    echo "${validDomain}"
}

addAudit()
{
    shift # skip "-a"
    shift # skip "audit"
    local domains validDomain
    domains=""
    for domain in "$@"
    do
      # Check domain to be added. Only continue if it is valid
      validDomain="$(checkDomain "${domain}")"
      if [[ -n "${validDomain}" ]]; then
        # Put comma in between domains when there is
        # more than one domains to be added
        # SQL INSERT allows adding multiple rows at once using the format
        ## INSERT INTO table (domain) VALUES ('abc.de'),('fgh.ij'),('klm.no'),('pqr.st');
        if [[ -n "${domains}" ]]; then
          domains="${domains},"
        fi
        domains="${domains}('${domain}')"
      fi
    done
    # Insert only the domain here. The date_added field will be
    # filled with its default value (date_added = current timestamp)
    sqlite3 "${gravityDBfile}" "INSERT INTO domain_audit (domain) VALUES ${domains};"
}

clearAudit()
{
    sqlite3 "${gravityDBfile}" "DELETE FROM domain_audit;"
}

SetPrivacyLevel() {
    # Set privacy level. Minimum is 0, maximum is 3
    if [ "${args[2]}" -ge 0 ] && [ "${args[2]}" -le 3 ]; then
        changeFTLsetting "PRIVACYLEVEL" "${args[2]}"
        pihole restartdns reload-lists
    fi
}

AddCustomDNSAddress() {
    echo -e "  ${TICK} Adding custom DNS entry..."

    ip="${args[2]}"
    host="${args[3]}"
	echo "${ip} ${host}" >> "${dnscustomfile}"

    # Restart dnsmasq to load new custom DNS entries
    RestartDNS
}

RemoveCustomDNSAddress() {
    echo -e "  ${TICK} Removing custom DNS entry..."

    ip="${args[2]}"
    host="${args[3]}"
    sed -i "/${ip} ${host}/d" "${dnscustomfile}"

    # Restart dnsmasq to update removed custom DNS entries
    RestartDNS
}

AddCustomCNAMERecord() {
    echo -e "  ${TICK} Adding custom CNAME record..."

    domain="${args[2]}"
    target="${args[3]}"
    echo "cname=${domain},${target}" >> "${dnscustomcnamefile}"

    # Restart dnsmasq to load new custom CNAME records
    RestartDNS
}

RemoveCustomCNAMERecord() {
    echo -e "  ${TICK} Removing custom CNAME record..."

    domain="${args[2]}"
    target="${args[3]}"
    sed -i "/cname=${domain},${target}/d" "${dnscustomcnamefile}"

    # Restart dnsmasq to update removed custom CNAME records
    RestartDNS
}

main() {
    args=("$@")

    case "${args[1]}" in
        "-p" | "password"     ) SetWebPassword;;
        "-c" | "celsius"      ) unit="C"; SetTemperatureUnit;;
        "-f" | "fahrenheit"   ) unit="F"; SetTemperatureUnit;;
        "-k" | "kelvin"       ) unit="K"; SetTemperatureUnit;;
        "setdns"              ) SetDNSServers;;
        "setexcludedomains"   ) SetExcludeDomains;;
        "setexcludeclients"   ) SetExcludeClients;;
        "poweroff"            ) Poweroff;;
        "reboot"              ) Reboot;;
        "restartdns"          ) RestartDNS;;
        "setquerylog"         ) SetQueryLogOptions;;
        "enabledhcp"          ) EnableDHCP;;
        "disabledhcp"         ) DisableDHCP;;
        "layout"              ) SetWebUILayout;;
        "theme"               ) SetWebUITheme;;
        "-h" | "--help"       ) helpFunc;;
        "privacymode"         ) SetPrivacyMode;;
        "resolve"             ) ResolutionSettings;;
        "addstaticdhcp"       ) AddDHCPStaticAddress;;
        "removestaticdhcp"    ) RemoveDHCPStaticAddress;;
        "-e" | "email"        ) SetAdminEmail "$3";;
        "-i" | "interface"    ) SetListeningMode "$@";;
        "-t" | "teleporter"   ) Teleporter;;
        "adlist"              ) CustomizeAdLists;;
        "audit"               ) addAudit "$@";;
        "clearaudit"          ) clearAudit;;
        "-l" | "privacylevel" ) SetPrivacyLevel;;
        "addcustomdns"        ) AddCustomDNSAddress;;
        "removecustomdns"     ) RemoveCustomDNSAddress;;
        "addcustomcname"      ) AddCustomCNAMERecord;;
        "removecustomcname"   ) RemoveCustomCNAMERecord;;
        *                     ) helpFunc;;
    esac

    shift

    if [[ $# = 0 ]]; then
        helpFunc
    fi
}
