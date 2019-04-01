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

setupVars="/etc/pihole/setupVars.conf"
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
  -r, hostrecord      Add a name to the DNS associated to an IPv4/IPv6 address
  -e, email           Set an administrative contact address for the Block Page
  -h, --help          Show this help dialog
  -i, interface       Specify dnsmasq's interface listening behavior
  -l, privacylevel    Set privacy level (0 = lowest, 4 = highest)"
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

HashPassword() {
    # Compute password hash twice to avoid rainbow table vulnerability
    return=$(echo -n ${1} | sha256sum | sed 's/\s.*$//')
    return=$(echo -n ${return} | sha256sum | sed 's/\s.*$//')
    echo ${return}
}

SetWebPassword() {
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

        # Load restart_service if it's not already available (webpage.sh gets
        # sourced and used in the installer)
        if ! type restart_service &> /dev/null; then
            # shellcheck disable=SC1091
            source "/etc/.pihole/automated install/basic-install.sh"
        fi

        # Restart the API so it uses the new password
        restart_service pihole-API

        echo -e "  ${TICK} New password set"
    else
        echo -e "  ${CROSS} Passwords don't match. Your password has not been changed"
        exit 1
    fi
}

# Regenerate the dnsmasq config and restart the DNS server to apply the changes
GenerateDnsmasqConfig() {
    # Run the command under the pihole user so the API can manipulate the
    # resulting dnsmasq config
    sudo -u pihole pihole-API generate-dnsmasq 1>/dev/null
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

    GenerateDnsmasqConfig
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

EnableDHCP() {
    change_setting "DHCP_ACTIVE" "true"
    change_setting "DHCP_START" "${args[2]}"
    change_setting "DHCP_END" "${args[3]}"
    change_setting "DHCP_ROUTER" "${args[4]}"
    change_setting "DHCP_LEASETIME" "${args[5]}"
    change_setting "PIHOLE_DOMAIN" "${args[6]}"
    change_setting "DHCP_IPv6" "${args[7]}"
    change_setting "DHCP_rapid_commit" "${args[8]}"

    GenerateDnsmasqConfig
}

DisableDHCP() {
    change_setting "DHCP_ACTIVE" "false"

    GenerateDnsmasqConfig
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

    GenerateDnsmasqConfig
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
        GenerateDnsmasqConfig
    fi
}

Teleporter() {
    echo "The teleporter has not been reimplemented in the API yet" 1>&2
    exit 1
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
