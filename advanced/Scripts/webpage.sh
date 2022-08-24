#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2154


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
# shellcheck disable=SC2034  # used in basic-install to source the script without running it
SKIP_INSTALL="true"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"

utilsfile="/opt/pihole/utils.sh"
source "${utilsfile}"

coltable="/opt/pihole/COL_TABLE"
if [[ -f ${coltable} ]]; then
    source ${coltable}
fi

helpFunc() {
    echo "Usage: pihole -a [options]
Example: pihole -a -p password
Set options for the Admin Console

Options:
  -p, password                    Set Admin Console password
  -c, celsius                     Set Celsius as preferred temperature unit
  -f, fahrenheit                  Set Fahrenheit as preferred temperature unit
  -k, kelvin                      Set Kelvin as preferred temperature unit
  -h, --help                      Show this help dialog
  -i, interface                   Specify dnsmasq's interface listening behavior
  -l, privacylevel                Set privacy level (0 = lowest, 3 = highest)
  -t, teleporter                  Backup configuration as an archive
  -t, teleporter myname.tar.gz    Backup configuration to archive with name myname.tar.gz as specified"
    exit 0
}

add_setting() {
    addOrEditKeyValPair "${setupVars}" "${1}" "${2}"
}

delete_setting() {
    removeKey "${setupVars}" "${1}"
}

change_setting() {
    addOrEditKeyValPair "${setupVars}" "${1}" "${2}"
}

addFTLsetting() {
    addOrEditKeyValPair "${FTLconf}" "${1}" "${2}"
}

deleteFTLsetting() {
    removeKey "${FTLconf}" "${1}"
}

changeFTLsetting() {
    addOrEditKeyValPair "${FTLconf}" "${1}" "${2}"
}

add_dnsmasq_setting() {
    addOrEditKeyValPair "${dnsmasqconfig}" "${1}" "${2}"
}

delete_dnsmasq_setting() {
    removeKey "${dnsmasqconfig}" "${1}"
}

SetTemperatureUnit() {
    addOrEditKeyValPair "${setupVars}" "TEMPERATUREUNIT" "${unit}"
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
            addOrEditKeyValPair "${setupVars}" "WEBPASSWORD" ""
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
        addOrEditKeyValPair "${setupVars}" "WEBPASSWORD" "${hash}"
        echo -e "  ${TICK} New password set"
    else
        echo -e "  ${CROSS} Passwords don't match. Your password has not been changed"
        exit 1
    fi
}

ProcessDNSSettings() {
    source "${setupVars}"

    removeKey "${dnsmasqconfig}" "server"

    COUNTER=1
    while true ; do
        var=PIHOLE_DNS_${COUNTER}
        if [ -z "${!var}" ]; then
            break;
        fi
        addKey "${dnsmasqconfig}" "server=${!var}"
        (( COUNTER++ ))
    done

    # The option LOCAL_DNS_PORT is deprecated
    # We apply it once more, and then convert it into the current format
    if [ -n "${LOCAL_DNS_PORT}" ]; then
        addOrEditKeyValPair "${dnsmasqconfig}" "server" "127.0.0.1#${LOCAL_DNS_PORT}"
        addOrEditKeyValPair "${setupVars}" "PIHOLE_DNS_${COUNTER}" "127.0.0.1#${LOCAL_DNS_PORT}"
        removeKey "${setupVars}" "LOCAL_DNS_PORT"
    fi

    removeKey "${dnsmasqconfig}" "domain-needed"
    removeKey "${dnsmasqconfig}" "expand-hosts"

    if [[ "${DNS_FQDN_REQUIRED}" == true ]]; then
        addKey "${dnsmasqconfig}" "domain-needed"
        addKey "${dnsmasqconfig}" "expand-hosts"
    fi

    removeKey "${dnsmasqconfig}" "bogus-priv"

    if [[ "${DNS_BOGUS_PRIV}" == true ]]; then
        addKey "${dnsmasqconfig}" "bogus-priv"
    fi

    removeKey "${dnsmasqconfig}" "dnssec"
    removeKey "${dnsmasqconfig}" "trust-anchor"

    if [[ "${DNSSEC}" == true ]]; then
        echo "dnssec
trust-anchor=.,20326,8,2,E06D44B80B8F1D39A95C0B0D7C65D08458E880409BBC683457104237C7F8EC8D
" >> "${dnsmasqconfig}"
    fi

    removeKey "${dnsmasqconfig}" "host-record"

    if [ -n "${HOSTRECORD}" ]; then
        addOrEditKeyValPair "${dnsmasqconfig}" "host-record" "${HOSTRECORD}"
    fi

    # Setup interface listening behavior of dnsmasq
    removeKey "${dnsmasqconfig}" "interface"
    removeKey "${dnsmasqconfig}" "local-service"
    removeKey "${dnsmasqconfig}" "except-interface"
    removeKey "${dnsmasqconfig}" "bind-interfaces"

    if [[ "${DNSMASQ_LISTENING}" == "all" ]]; then
        # Listen on all interfaces, permit all origins
        addOrEditKeyValPair "${dnsmasqconfig}" "except-interface" "nonexisting"
    elif [[ "${DNSMASQ_LISTENING}" == "local" ]]; then
        # Listen only on all interfaces, but only local subnets
        addKey "${dnsmasqconfig}" "local-service"
    else
        # Options "bind" and "single"
        # Listen only on one interface
        # Use eth0 as fallback interface if interface is missing in setupVars.conf
        if [ -z "${PIHOLE_INTERFACE}" ]; then
            PIHOLE_INTERFACE="eth0"
        fi

        addOrEditKeyValPair "${dnsmasqconfig}" "interface" "${PIHOLE_INTERFACE}"

        if [[ "${DNSMASQ_LISTENING}" == "bind" ]]; then
            # Really bind to interface
            addKey "${dnsmasqconfig}" "bind-interfaces"
        fi
    fi

    if [[ "${CONDITIONAL_FORWARDING}" == true ]]; then
        # Convert legacy "conditional forwarding" to rev-server configuration
        # Remove any existing REV_SERVER settings
        removeKey "${setupVars}" "REV_SERVER"
        removeKey "${setupVars}" "REV_SERVER_DOMAIN"
        removeKey "${setupVars}" "REV_SERVER_TARGET"
        removeKey "${setupVars}" "REV_SERVER_CIDR"

        REV_SERVER=true
        addOrEditKeyValPair "${setupVars}" "REV_SERVER" "true"

        REV_SERVER_DOMAIN="${CONDITIONAL_FORWARDING_DOMAIN}"
        addOrEditKeyValPair "${setupVars}" "REV_SERVER_DOMAIN" "${REV_SERVER_DOMAIN}"

        REV_SERVER_TARGET="${CONDITIONAL_FORWARDING_IP}"
        addOrEditKeyValPair "${setupVars}" "REV_SERVER_TARGET" "${REV_SERVER_TARGET}"

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
        addOrEditKeyValPair "${setupVars}" "REV_SERVER_CIDR" "${REV_SERVER_CIDR}"

        # Remove obsolete settings from setupVars.conf
        removeKey "${setupVars}" "CONDITIONAL_FORWARDING"
        removeKey "${setupVars}" "CONDITIONAL_FORWARDING_REVERSE"
        removeKey "${setupVars}" "CONDITIONAL_FORWARDING_DOMAIN"
        removeKey "${setupVars}" "CONDITIONAL_FORWARDING_IP"
    fi

    removeKey "${dnsmasqconfig}" "rev-server"

    if [[ "${REV_SERVER}" == true ]]; then
        addKey "${dnsmasqconfig}" "rev-server=${REV_SERVER_CIDR},${REV_SERVER_TARGET}"
        if [ -n "${REV_SERVER_DOMAIN}" ]; then
            # Forward local domain names to the CF target, too
            addKey "${dnsmasqconfig}" "server=/${REV_SERVER_DOMAIN}/${REV_SERVER_TARGET}"
        fi

        if [[ "${DNS_FQDN_REQUIRED}" != true ]]; then
            # Forward unqualified names to the CF target only when the "never
            # forward non-FQDN" option is unticked
            addKey "${dnsmasqconfig}" "server=//${REV_SERVER_TARGET}"
        fi

    fi

    # We need to process DHCP settings here as well to account for possible
    # changes in the non-FQDN forwarding. This cannot be done in 01-pihole.conf
    # as we don't want to delete all local=/.../ lines so it's much safer to
    # simply rewrite the entire corresponding config file (which is what the
    # DHCP settings subroutine is doing)
    ProcessDHCPSettings
}

SetDNSServers() {
    # Save setting to file
    removeKey "${setupVars}" "PIHOLE_DNS"
    IFS=',' read -r -a array <<< "${args[2]}"
    for index in "${!array[@]}"
    do
        # Replace possible "\#" by "#". This fixes AdminLTE#1427
        local ip
        ip="${array[index]//\\#/#}"

        if valid_ip "${ip}" || valid_ip6 "${ip}" ; then
            addOrEditKeyValPair "${setupVars}" "PIHOLE_DNS_$((index+1))" "${ip}"
        else
            echo -e "  ${CROSS} Invalid IP has been passed"
            exit 1
        fi
    done

    if [[ "${args[3]}" == "domain-needed" ]]; then
        addOrEditKeyValPair "${setupVars}" "DNS_FQDN_REQUIRED" "true"
    else
        addOrEditKeyValPair "${setupVars}" "DNS_FQDN_REQUIRED" "false"
    fi

    if [[ "${args[4]}" == "bogus-priv" ]]; then
        addOrEditKeyValPair "${setupVars}" "DNS_BOGUS_PRIV" "true"
    else
        addOrEditKeyValPair "${setupVars}" "DNS_BOGUS_PRIV" "false"
    fi

    if [[ "${args[5]}" == "dnssec" ]]; then
        addOrEditKeyValPair "${setupVars}" "DNSSEC" "true"
    else
        addOrEditKeyValPair "${setupVars}" "DNSSEC" "false"
    fi

    if [[ "${args[6]}" == "rev-server" ]]; then
        addOrEditKeyValPair "${setupVars}" "REV_SERVER" "true"
        addOrEditKeyValPair "${setupVars}" "REV_SERVER_CIDR" "${args[7]}"
        addOrEditKeyValPair "${setupVars}" "REV_SERVER_TARGET" "${args[8]}"
        addOrEditKeyValPair "${setupVars}" "REV_SERVER_DOMAIN" "${args[9]}"
    else
        addOrEditKeyValPair "${setupVars}" "REV_SERVER" "false"
    fi

    ProcessDNSSettings

    # Restart dnsmasq to load new configuration
    RestartDNS
}

SetExcludeDomains() {
    addOrEditKeyValPair "${setupVars}" "API_EXCLUDE_DOMAINS" "${args[2]}"
}

SetExcludeClients() {
    addOrEditKeyValPair "${setupVars}" "API_EXCLUDE_CLIENTS" "${args[2]}"
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
    addOrEditKeyValPair "${setupVars}" "API_QUERY_LOG_SHOW" "${args[2]}"
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
            addOrEditKeyValPair "${setupVars}" "PIHOLE_DOMAIN" "${PIHOLE_DOMAIN}"
        fi

        if [[ "${DHCP_LEASETIME}" == "0" ]]; then
            leasetime="infinite"
        elif [[ "${DHCP_LEASETIME}" == "" ]]; then
            leasetime="24"
            addOrEditKeyValPair "${setupVars}" "DHCP_LEASETIME" "${leasetime}"
        elif [[ "${DHCP_LEASETIME}" == "24h" ]]; then
            #Installation is affected by known bug, introduced in a previous version.
            #This will automatically clean up setupVars.conf and remove the unnecessary "h"
            leasetime="24"
            addOrEditKeyValPair "${setupVars}" "DHCP_LEASETIME" "${leasetime}"
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
dhcp-range=::,constructor:${interface},ra-names,ra-stateless,64

" >> "${dhcpconfig}"
        fi

    else
        if [[ -f "${dhcpconfig}" ]]; then
            rm "${dhcpconfig}" &> /dev/null
        fi
    fi
}

EnableDHCP() {
    addOrEditKeyValPair "${setupVars}" "DHCP_ACTIVE" "true"
    addOrEditKeyValPair "${setupVars}" "DHCP_START" "${args[2]}"
    addOrEditKeyValPair "${setupVars}" "DHCP_END" "${args[3]}"
    addOrEditKeyValPair "${setupVars}" "DHCP_ROUTER" "${args[4]}"
    addOrEditKeyValPair "${setupVars}" "DHCP_LEASETIME" "${args[5]}"
    addOrEditKeyValPair "${setupVars}" "PIHOLE_DOMAIN" "${args[6]}"
    addOrEditKeyValPair "${setupVars}" "DHCP_IPv6" "${args[7]}"
    addOrEditKeyValPair "${setupVars}" "DHCP_rapid_commit" "${args[8]}"

    # Remove possible old setting from file
    removeKey "${dnsmasqconfig}" "dhcp-"
    removeKey "${dnsmasqconfig}" "quiet-dhcp"

    # If a DHCP client claims that its name is "wpad", ignore that.
    # This fixes a security hole. see CERT Vulnerability VU#598349
    # We also ignore "localhost" as Windows behaves strangely if a
    # device claims this host name
    addKey "${dnsmasqconfig}" "dhcp-name-match=set:hostname-ignore,wpad
dhcp-name-match=set:hostname-ignore,localhost
dhcp-ignore-names=tag:hostname-ignore"

    ProcessDHCPSettings

    RestartDNS
}

DisableDHCP() {
    addOrEditKeyValPair "${setupVars}" "DHCP_ACTIVE" "false"

    # Remove possible old setting from file
    removeKey "${dnsmasqconfig}" "dhcp-"
    removeKey "${dnsmasqconfig}" "quiet-dhcp"

    ProcessDHCPSettings

    RestartDNS
}

SetWebUILayout() {
    addOrEditKeyValPair "${setupVars}" "WEBUIBOXEDLAYOUT" "${args[2]}"
}

SetWebUITheme() {
    addOrEditKeyValPair "${setupVars}" "WEBTHEME" "${args[2]}"
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
            pihole-FTL sqlite3 "${gravityDBfile}" "UPDATE adlist SET enabled = 1 WHERE address = '${address}'"
        elif [[ "${args[2]}" == "disable" ]]; then
            pihole-FTL sqlite3 "${gravityDBfile}" "UPDATE adlist SET enabled = 0 WHERE address = '${address}'"
        elif [[ "${args[2]}" == "add" ]]; then
            pihole-FTL sqlite3 "${gravityDBfile}" "INSERT OR IGNORE INTO adlist (address, comment) VALUES ('${address}', '${comment}')"
        elif [[ "${args[2]}" == "del" ]]; then
            pihole-FTL sqlite3 "${gravityDBfile}" "DELETE FROM adlist WHERE address = '${address}'"
        else
            echo "Not permitted"
            return 1
        fi
    else
        echo "Invalid Url"
        return 1
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
    if [[ "$mac" =~ ^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$ ]]; then
        sed -i "/dhcp-host=${mac}.*/d" "${dhcpstaticconfig}"
    else
        echo "  ${CROSS} Invalid Mac Passed!"
        exit 1
    fi

}

SetListeningMode() {
    source "${setupVars}"

    if [[ "$3" == "-h" ]] || [[ "$3" == "--help" ]]; then
        echo "Usage: pihole -a -i [interface]
Example: 'pihole -a -i local'
Specify dnsmasq's network interface listening behavior

Interfaces:
  local               Only respond to queries from devices that
                      are at most one hop away (local devices)
  single              Respond only on interface ${PIHOLE_INTERFACE}
  bind                Bind only on interface ${PIHOLE_INTERFACE}
  all                 Listen on all interfaces, permit all origins"
        exit 0
    fi

    if [[ "${args[2]}" == "all" ]]; then
        echo -e "  ${INFO} Listening on all interfaces, permitting all origins. Please use a firewall!"
        addOrEditKeyValPair "${setupVars}" "DNSMASQ_LISTENING" "all"
    elif [[ "${args[2]}" == "local" ]]; then
        echo -e "  ${INFO} Listening on all interfaces, permitting origins from one hop away (LAN)"
        addOrEditKeyValPair "${setupVars}" "DNSMASQ_LISTENING" "local"
    elif [[ "${args[2]}" == "bind" ]]; then
        echo -e "  ${INFO} Binding on interface ${PIHOLE_INTERFACE}"
        addOrEditKeyValPair "${setupVars}" "DNSMASQ_LISTENING" "bind"
    else
        echo -e "  ${INFO} Listening only on interface ${PIHOLE_INTERFACE}"
        addOrEditKeyValPair "${setupVars}" "DNSMASQ_LISTENING" "single"
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
    local filename
    filename="${args[2]}"
    if [[ -z "${filename}" ]]; then
        local datetimestamp
        local host
        datetimestamp=$(date "+%Y-%m-%d_%H-%M-%S")
        host=$(hostname)
        host="${host//./_}"
        filename="pi-hole-${host:-noname}-teleporter_${datetimestamp}.tar.gz"
    fi
    # webroot is sourced from basic-install above
    php "${webroot}/admin/scripts/pi-hole/php/teleporter.php" > "${filename}"
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
    pihole-FTL sqlite3 "${gravityDBfile}" "INSERT INTO domain_audit (domain) VALUES ${domains};"
}

clearAudit()
{
    pihole-FTL sqlite3 "${gravityDBfile}" "DELETE FROM domain_audit;"
}

SetPrivacyLevel() {
    # Set privacy level. Minimum is 0, maximum is 3
    if [ "${args[2]}" -ge 0 ] && [ "${args[2]}" -le 3 ]; then
        addOrEditKeyValPair "${FTLconf}" "PRIVACYLEVEL" "${args[2]}"
        pihole restartdns reload-lists
    fi
}

AddCustomDNSAddress() {
    echo -e "  ${TICK} Adding custom DNS entry..."

    ip="${args[2]}"
    host="${args[3]}"
    reload="${args[4]}"

    validHost="$(checkDomain "${host}")"
    if [[ -n "${validHost}" ]]; then
        if valid_ip "${ip}" || valid_ip6 "${ip}" ; then
            echo "${ip} ${validHost}" >> "${dnscustomfile}"
        else
            echo -e "  ${CROSS} Invalid IP has been passed"
            exit 1
        fi
    else
        echo "  ${CROSS} Invalid Domain passed!"
        exit 1
    fi

    # Restart dnsmasq to load new custom DNS entries only if $reload not false
    if [[ ! $reload == "false" ]]; then
        RestartDNS
    fi
}

RemoveCustomDNSAddress() {
    echo -e "  ${TICK} Removing custom DNS entry..."

    ip="${args[2]}"
    host="${args[3]}"
    reload="${args[4]}"

    validHost="$(checkDomain "${host}")"
    if [[ -n "${validHost}" ]]; then
        if valid_ip "${ip}" || valid_ip6 "${ip}" ; then
            sed -i "/^${ip} ${validHost}$/Id" "${dnscustomfile}"
        else
            echo -e "  ${CROSS} Invalid IP has been passed"
            exit 1
        fi
    else
        echo "  ${CROSS} Invalid Domain passed!"
        exit 1
    fi

    # Restart dnsmasq to load new custom DNS entries only if reload is not false
    if [[ ! $reload == "false" ]]; then
        RestartDNS
    fi
}

AddCustomCNAMERecord() {
    echo -e "  ${TICK} Adding custom CNAME record..."

    domain="${args[2]}"
    target="${args[3]}"
    reload="${args[4]}"

    validDomain="$(checkDomain "${domain}")"
    if [[ -n "${validDomain}" ]]; then
        validTarget="$(checkDomain "${target}")"
        if [[ -n "${validTarget}" ]]; then
            echo "cname=${validDomain},${validTarget}" >> "${dnscustomcnamefile}"
        else
            echo "  ${CROSS} Invalid Target Passed!"
            exit 1
        fi
    else
        echo "  ${CROSS} Invalid Domain passed!"
        exit 1
    fi
    # Restart dnsmasq to load new custom CNAME records only if reload is not false
    if [[ ! $reload == "false" ]]; then
        RestartDNS
    fi
}

RemoveCustomCNAMERecord() {
    echo -e "  ${TICK} Removing custom CNAME record..."

    domain="${args[2]}"
    target="${args[3]}"
    reload="${args[4]}"

    validDomain="$(checkDomain "${domain}")"
    if [[ -n "${validDomain}" ]]; then
        validTarget="$(checkDomain "${target}")"
        if [[ -n "${validTarget}" ]]; then
            sed -i "/cname=${validDomain},${validTarget}$/Id" "${dnscustomcnamefile}"
        else
            echo "  ${CROSS} Invalid Target Passed!"
            exit 1
        fi
    else
        echo "  ${CROSS} Invalid Domain passed!"
        exit 1
    fi

    # Restart dnsmasq to update removed custom CNAME records only if $reload not false
    if [[ ! $reload == "false" ]]; then
        RestartDNS
    fi
}

SetRateLimit() {
    local rate_limit_count rate_limit_interval reload
    rate_limit_count="${args[2]}"
    rate_limit_interval="${args[3]}"
    reload="${args[4]}"

    # Set rate-limit setting inf valid
    if [ "${rate_limit_count}" -ge 0 ] && [ "${rate_limit_interval}" -ge 0 ]; then
        addOrEditKeyValPair "${FTLconf}" "RATE_LIMIT" "${rate_limit_count}/${rate_limit_interval}"
    fi

    # Restart FTL to update rate-limit settings only if $reload not false
    if [[ ! $reload == "false" ]]; then
        RestartDNS
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
        "theme"               ) SetWebUITheme;;
        "-h" | "--help"       ) helpFunc;;
        "addstaticdhcp"       ) AddDHCPStaticAddress;;
        "removestaticdhcp"    ) RemoveDHCPStaticAddress;;
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
        "ratelimit"           ) SetRateLimit;;
        *                     ) helpFunc;;
    esac

    shift

    if [[ $# = 0 ]]; then
        helpFunc
    fi
}
