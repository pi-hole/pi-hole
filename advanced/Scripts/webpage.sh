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

readonly setupVars="/etc/pihole/setupVars.conf"
readonly dnsmasqconfig="/etc/dnsmasq.d/01-pihole.conf"
readonly dhcpconfig="/etc/dnsmasq.d/02-pihole-dhcp.conf"
readonly FTLconf="/etc/pihole/pihole-FTL.conf"
# 03 -> wildcards
readonly dhcpstaticconfig="/etc/dnsmasq.d/04-pihole-static-dhcp.conf"

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
  -r, hostrecord      Add a name to the DNS associated to an IPv4/IPv6 address
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
    return=$(echo -n ${1} | sha256sum | sed 's/\s.*$//')
    return=$(echo -n ${return} | sha256sum | sed 's/\s.*$//')
    echo ${return}
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
        read -s -p -r "Enter New Password (Blank for no password): " PASSWORD
        echo ""

    if [ "${PASSWORD}" == "" ]; then
        change_setting "WEBPASSWORD" ""
        echo -e "  ${TICK} Password Removed"
        exit 0
    fi

    read -s -p -r "Confirm Password: " CONFIRM
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
    while [[ 1 ]]; do
        var=PIHOLE_DNS_${COUNTER}
        if [ -z "${!var}" ]; then
            break;
        fi
        add_dnsmasq_setting "server" "${!var}"
        let COUNTER=COUNTER+1
    done

    # The option LOCAL_DNS_PORT is deprecated
    # We apply it once more, and then convert it into the current format
    if [ ! -z "${LOCAL_DNS_PORT}" ]; then
        add_dnsmasq_setting "server" "127.0.0.1#${LOCAL_DNS_PORT}"
        add_setting "PIHOLE_DNS_${COUNTER}" "127.0.0.1#${LOCAL_DNS_PORT}"
        delete_setting "LOCAL_DNS_PORT"
    fi

    delete_dnsmasq_setting "domain-needed"

    if [[ "${DNS_FQDN_REQUIRED}" == true ]]; then
        add_dnsmasq_setting "domain-needed"
    fi

    delete_dnsmasq_setting "bogus-priv"

    if [[ "${DNS_BOGUS_PRIV}" == true ]]; then
        add_dnsmasq_setting "bogus-priv"
    fi

    delete_dnsmasq_setting "dnssec"
    delete_dnsmasq_setting "trust-anchor="

    if [[ "${DNSSEC}" == true ]]; then
        echo "dnssec
trust-anchor=.,19036,8,2,49AAC11D7B6F6446702E54A1607371607A1A41855200FD2CE1CDDE32F24E8FB5
trust-anchor=.,20326,8,2,E06D44B80B8F1D39A95C0B0D7C65D08458E880409BBC683457104237C7F8EC8D
" >> "${dnsmasqconfig}"
    fi

    delete_dnsmasq_setting "host-record"

    if [ ! -z "${HOSTRECORD}" ]; then
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
        add_dnsmasq_setting "server=/${CONDITIONAL_FORWARDING_DOMAIN}/${CONDITIONAL_FORWARDING_IP}"
        add_dnsmasq_setting "server=/${CONDITIONAL_FORWARDING_REVERSE}/${CONDITIONAL_FORWARDING_IP}"
    fi
}

SetDNSServers() {
    # Save setting to file
    delete_setting "PIHOLE_DNS"
    IFS=',' read -r -a array <<< "${args[2]}"
    for index in "${!array[@]}"
    do
        add_setting "PIHOLE_DNS_$((index+1))" "${array[index]}"
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

    if [[ "${args[6]}" == "conditional_forwarding" ]]; then
        change_setting "CONDITIONAL_FORWARDING" "true"
        change_setting "CONDITIONAL_FORWARDING_IP" "${args[7]}"
        change_setting "CONDITIONAL_FORWARDING_DOMAIN" "${args[8]}"
        change_setting "CONDITIONAL_FORWARDING_REVERSE" "${args[9]}"
    else
        change_setting "CONDITIONAL_FORWARDING" "false"
        delete_setting "CONDITIONAL_FORWARDING_IP"
        delete_setting "CONDITIONAL_FORWARDING_DOMAIN"
        delete_setting "CONDITIONAL_FORWARDING_REVERSE"
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
    /usr/local/bin/pihole restartdns
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

    if [[ "${PIHOLE_DOMAIN}" != "none" ]]; then
        echo "domain=${PIHOLE_DOMAIN}" >> "${dhcpconfig}"
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

    # Remove possible old setting from file
    delete_dnsmasq_setting "dhcp-"
    delete_dnsmasq_setting "quiet-dhcp"

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

CustomizeAdLists() {
    list="/etc/pihole/adlists.list"

    if [[ "${args[2]}" == "enable" ]]; then
        sed -i "\\@${args[3]}@s/^#http/http/g" "${list}"
    elif [[ "${args[2]}" == "disable" ]]; then
        sed -i "\\@${args[3]}@s/^http/#http/g" "${list}"
    elif [[ "${args[2]}" == "add" ]]; then
        if [[ $(grep -c "^${args[3]}$" "${list}") -eq 0 ]] ; then
            echo "${args[3]}" >> ${list}
        fi
    elif [[ "${args[2]}" == "del" ]]; then
        var=$(echo "${args[3]}" | sed 's/\//\\\//g')
        sed -i "/${var}/Id" "${list}"
    else
        echo "Not permitted"
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

SetHostRecord() {
    if [[ "${1}" == "-h" ]] || [[ "${1}" == "--help" ]]; then
        echo "Usage: pihole -a hostrecord <domain> [IPv4-address],[IPv6-address]
Example: 'pihole -a hostrecord home.domain.com 192.168.1.1,2001:db8:a0b:12f0::1'
Add a name to the DNS associated to an IPv4/IPv6 address

Options:
  \"\"                  Empty: Remove host record
  -h, --help          Show this help dialog"
        exit 0
    fi

    if [[ -n "${args[3]}" ]]; then
        change_setting "HOSTRECORD" "${args[2]},${args[3]}"
        echo -e "  ${TICK} Setting host record for ${args[2]} to ${args[3]}"
    else
        change_setting "HOSTRECORD" ""
        echo -e "  ${TICK} Removing host record"
    fi

    ProcessDNSSettings

    # Restart dnsmasq to load new configuration
    RestartDNS
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
        echo -e "  ${INFO} Listening on all interfaces, permiting all origins. Please use a firewall!"
        change_setting "DNSMASQ_LISTENING" "all"
    elif [[ "${args[2]}" == "local" ]]; then
        echo -e "  ${INFO} Listening on all interfaces, permiting origins from one hop away (LAN)"
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
    local datetimestamp=$(date "+%Y-%m-%d_%H-%M-%S")
    php /var/www/html/admin/scripts/pi-hole/php/teleporter.php > "pi-hole-teleporter_${datetimestamp}.zip"
}

addAudit()
{
    shift # skip "-a"
    shift # skip "audit"
    for var in "$@"
    do
        echo "${var}" >> /etc/pihole/auditlog.list
    done
}

clearAudit()
{
    echo -n "" > /etc/pihole/auditlog.list
}

SetPrivacyLevel() {
    # Set privacy level. Minimum is 0, maximum is 4
    if [ "${args[2]}" -ge 0 ] && [ "${args[2]}" -le 4 ]; then
        changeFTLsetting "PRIVACYLEVEL" "${args[2]}"
    fi
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
        "-h" | "--help"       ) helpFunc;;
        "privacymode"         ) SetPrivacyMode;;
        "resolve"             ) ResolutionSettings;;
        "addstaticdhcp"       ) AddDHCPStaticAddress;;
        "removestaticdhcp"    ) RemoveDHCPStaticAddress;;
        "-r" | "hostrecord"   ) SetHostRecord "$3";;
        "-e" | "email"        ) SetAdminEmail "$3";;
        "-i" | "interface"    ) SetListeningMode "$@";;
        "-t" | "teleporter"   ) Teleporter;;
        "adlist"              ) CustomizeAdLists;;
        "audit"               ) addAudit "$@";;
        "clearaudit"          ) clearAudit;;
        "-l" | "privacylevel" ) SetPrivacyLevel;;
        *                     ) helpFunc;;
    esac

    shift

    if [[ $# = 0 ]]; then
        helpFunc
    fi
}
