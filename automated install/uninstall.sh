#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Completely uninstalls Pi-hole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# shellcheck source="./advanced/Scripts/COL_TABLE"
source "/opt/pihole/COL_TABLE"
# shellcheck source="./advanced/Scripts/utils.sh"
source "/opt/pihole/utils.sh"

ADMIN_INTERFACE_DIR=$(getFTLConfigValue "webserver.paths.webroot")$(getFTLConfigValue "webserver.paths.webhome")
readonly ADMIN_INTERFACE_DIR

while true; do
    read -rp "  ${QST} Are you sure you would like to remove ${COL_BOLD}Pi-hole${COL_NC}? [y/N] " answer
    case ${answer} in
        [Yy]* ) break;;
        * ) echo -e "${OVER}  ${COL_GREEN}Uninstall has been canceled${COL_NC}"; exit 0;;
    esac
done

# Must be root to uninstall
str="Root user check"
if [[ ${EUID} -eq 0 ]]; then
    echo -e "  ${TICK} ${str}"
else
    # Check if sudo is actually installed
    # If it isn't, exit because the uninstall can not complete
    if [ -x "$(command -v sudo)" ]; then
        export SUDO="sudo"
    else
        echo -e "  ${CROSS} ${str}
            Script called with non-root privileges
            The Pi-hole requires elevated privileges to uninstall"
        exit 1
    fi
fi

readonly PI_HOLE_FILES_DIR="/etc/.pihole"
SKIP_INSTALL="true"
# shellcheck source="./automated install/basic-install.sh"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"

# package_manager_detect() sourced from basic-install.sh
package_manager_detect


removeMetaPackage() {
    # Purge Pi-hole meta package
    echo ""
    echo -ne "  ${INFO} Removing Pi-hole meta package...";
    eval "${SUDO}" "${PKG_REMOVE}" "pihole-meta" &> /dev/null;
    echo -e "${OVER}  ${INFO} Removed Pi-hole meta package";

}

removePiholeFiles() {
    # Remove the web interface of Pi-hole
    echo -ne "  ${INFO} Removing Web Interface..."
    ${SUDO} rm -rf "${ADMIN_INTERFACE_DIR}" &> /dev/null
    echo -e "${OVER}  ${TICK} Removed Web Interface"

    # Attempt to preserve backwards compatibility with older versions
    # to guarantee no additional changes were made to /etc/crontab after
    # the installation of pihole, /etc/crontab.pihole should be permanently
    # preserved.
    if [[ -f /etc/crontab.orig ]]; then
        ${SUDO} mv /etc/crontab /etc/crontab.pihole
        ${SUDO} mv /etc/crontab.orig /etc/crontab
        ${SUDO} service cron restart
        echo -e "  ${TICK} Restored the default system cron"
    fi

    # Attempt to preserve backwards compatibility with older versions
    if [[ -f /etc/cron.d/pihole ]];then
        ${SUDO} rm -f /etc/cron.d/pihole &> /dev/null
        echo -e "  ${TICK} Removed /etc/cron.d/pihole"
    fi

    ${SUDO} rm -rf /var/log/*pihole* &> /dev/null
    ${SUDO} rm -rf /var/log/pihole/*pihole* &> /dev/null
    ${SUDO} rm -rf /etc/pihole/ &> /dev/null
    ${SUDO} rm -rf /etc/.pihole/ &> /dev/null
    ${SUDO} rm -rf /opt/pihole/ &> /dev/null
    ${SUDO} rm -f /usr/local/bin/pihole &> /dev/null
    ${SUDO} rm -f /etc/bash_completion.d/pihole &> /dev/null
    ${SUDO} rm -f /etc/sudoers.d/pihole &> /dev/null
    echo -e "  ${TICK} Removed config files"

    # Restore Resolved
    if [[ -e /etc/systemd/resolved.conf.orig ]] || [[ -e /etc/systemd/resolved.conf.d/90-pi-hole-disable-stub-listener.conf ]]; then
        ${SUDO} cp -p /etc/systemd/resolved.conf.orig /etc/systemd/resolved.conf &> /dev/null || true
        ${SUDO} rm -f /etc/systemd/resolved.conf.d/90-pi-hole-disable-stub-listener.conf
        systemctl reload-or-restart systemd-resolved
    fi

    # Remove FTL
    if command -v pihole-FTL &> /dev/null; then
        echo -ne "  ${INFO} Removing pihole-FTL..."
        if [[ -x "$(command -v systemctl)" ]]; then
            systemctl stop pihole-FTL
        else
            service pihole-FTL stop
        fi
        ${SUDO} rm -f /etc/systemd/system/pihole-FTL.service
        if [[ -d '/etc/systemd/system/pihole-FTL.service.d' ]]; then
            read -rp "  ${QST} FTL service override directory /etc/systemd/system/pihole-FTL.service.d detected. Do you wish to remove this from your system? [y/N] " answer
            case $answer in
                [yY]*)
                    echo -ne "  ${INFO} Removing /etc/systemd/system/pihole-FTL.service.d..."
                    ${SUDO} rm -R /etc/systemd/system/pihole-FTL.service.d
                    echo -e "${OVER}  ${INFO} Removed /etc/systemd/system/pihole-FTL.service.d"
                ;;
                *) echo -e "  ${INFO} Leaving /etc/systemd/system/pihole-FTL.service.d in place.";;
            esac
        fi
        ${SUDO} rm -f /etc/init.d/pihole-FTL
        ${SUDO} rm -f /usr/bin/pihole-FTL
        echo -e "${OVER}  ${TICK} Removed pihole-FTL"
    fi

    # If the pihole manpage exists, then delete and rebuild man-db
    if [[ -f /usr/local/share/man/man8/pihole.8 ]]; then
        ${SUDO} rm -f /usr/local/share/man/man8/pihole.8 /usr/local/share/man/man8/pihole-FTL.8 /usr/local/share/man/man5/pihole-FTL.conf.5
        ${SUDO} mandb -q &>/dev/null
        echo -e "  ${TICK} Removed pihole man page"
    fi

    # If the pihole user exists, then remove
    if id "pihole" &> /dev/null; then
        if ${SUDO} userdel -r pihole 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pihole' user"
        else
            echo -e "  ${CROSS} Unable to remove 'pihole' user"
        fi
    fi
    # If the pihole group exists, then remove
    if getent group "pihole" &> /dev/null; then
        if ${SUDO} groupdel pihole 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pihole' group"
        else
            echo -e "  ${CROSS} Unable to remove 'pihole' group"
        fi
    fi

    echo -e "\\n   We're sorry to see you go, but thanks for checking out Pi-hole!
       If you need help, reach out to us on GitHub, Discourse, Reddit or Twitter
       Reinstall at any time: ${COL_BOLD}curl -sSL https://install.pi-hole.net | bash${COL_NC}

      ${COL_RED}Please reset the DNS on your router/clients to restore internet connectivity${COL_NC}
      ${INFO} Pi-hole's meta package has been removed, use the 'autoremove' function from your package manager to remove unused dependencies${COL_NC}
      ${COL_GREEN}Uninstallation Complete! ${COL_NC}"
}

######### SCRIPT ###########
removeMetaPackage
removePiholeFiles
