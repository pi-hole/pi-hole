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

# TODO - this entire file might be able to be removed in v6

readonly dnsmasqconfig="/etc/dnsmasq.d/01-pihole.conf"
readonly dhcpconfig="/etc/dnsmasq.d/02-pihole-dhcp.conf"
readonly FTLconf="/etc/pihole/pihole-FTL.conf"
# 03 -> wildcards
readonly dhcpstaticconfig="/etc/dnsmasq.d/04-pihole-static-dhcp.conf"
readonly dnscustomfile="/etc/pihole/custom.list"
readonly dnscustomcnamefile="/etc/dnsmasq.d/05-pihole-custom-cname.conf"

readonly gravityDBfile="/etc/pihole/gravity.db"


readonly setupVars="/etc/pihole/setupVars.conf"
readonly PI_HOLE_BIN_DIR="/usr/local/bin"

# Root of the web server
readonly webroot="/var/www/html"

# Source utils script
utilsfile="/opt/pihole/utils.sh"
source "${utilsfile}"

coltable="/opt/pihole/COL_TABLE"
if [[ -f ${coltable} ]]; then
    source ${coltable}
fi

helpFunc() {
    echo "Usage: pihole -a [options]
Example: pihole -a -p password
Set options for the API/Web interface

Options:
  -p, password                    Set API/Web interface password
  -h, --help                      Show this help dialog"
    exit 0
}

# TODO: We can probably remove the reliance on this function too, just tell people to pihole-FTL --config webserver.api.password "password"
SetWebPassword() {
    if (( ${#args[2]} > 0 )) ; then
        readonly PASSWORD="${args[2]}"
        readonly CONFIRM="${PASSWORD}"
    else
        # Prevents a bug if the user presses Ctrl+C and it continues to hide the text typed.
        # So we reset the terminal via stty if the user does press Ctrl+C
        trap '{ echo -e "\nNot changed" ; stty sane ; exit 1; }' INT
        read -s -r -p "Enter New Password (Blank for no password): " PASSWORD
        echo ""

        if [ "${PASSWORD}" == "" ]; then
            setFTLConfigValue "webserver.api.pwhash" "" >/dev/null
            echo -e "  ${TICK} Password Removed"
            exit 0
        fi

        read -s -r -p "Confirm Password: " CONFIRM
        echo ""
    fi

    if [ "${PASSWORD}" == "${CONFIRM}" ] ; then
        # pihole-FTL will automatically hash the password
        setFTLConfigValue "webserver.api.password" "${PASSWORD}" >/dev/null
        echo -e "  ${TICK} New password set"
    else
        echo -e "  ${CROSS} Passwords don't match. Your password has not been changed"
        exit 1
    fi
}

main() {
    args=("$@")

    case "${args[1]}" in
        "-p" | "password"     ) SetWebPassword;;
        "-h" | "--help"       ) helpFunc;;
        *                     ) helpFunc;;
    esac

    shift

    if [[ $# = 0 ]]; then
        helpFunc
    fi
}
