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
# getFTLConfigValue() from utils.sh

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
    echo -e "  ${CROSS} ${str}
        Script called with non-root privileges
        The Pi-hole requires elevated privileges to uninstall"
    exit 1
fi

# Get paths for admin interface, log files and database files,
# to allow deletion where user has specified a non-default location
ADMIN_INTERFACE_DIR=$(getFTLConfigValue "webserver.paths.webroot")$(getFTLConfigValue "webserver.paths.webhome")
FTL_LOG=$(getFTLConfigValue "files.log.ftl")
DNSMASQ_LOG=$(getFTLConfigValue "files.log.dnsmasq")
WEBSERVER_LOG=$(getFTLConfigValue "files.log.webserver")
PIHOLE_DB=$(getFTLConfigValue "files.database")
GRAVITY_DB=$(getFTLConfigValue "files.gravity")
MACVENDOR_DB=$(getFTLConfigValue "files.macvendor")

PI_HOLE_LOCAL_REPO="/etc/.pihole"
# Setting SKIP_INSTALL="true" to source the installer functions without running them
SKIP_INSTALL="true"
# shellcheck source="./automated install/basic-install.sh"
source "${PI_HOLE_LOCAL_REPO}/automated install/basic-install.sh"
# Functions and Variables sources from basic-install:
# package_manager_detect(), disable_service(), stop_service(),
# restart service() and is_command()
# PI_HOLE_CONFIG_DIR PI_HOLE_INSTALL_DIR PI_HOLE_LOCAL_REPO

removeMetaPackage() {
    # Purge Pi-hole meta package
    echo ""
    echo -ne "  ${INFO} Removing Pi-hole meta package...";
    eval "${PKG_REMOVE}" "pihole-meta" &> /dev/null;
    echo -e "${OVER}  ${INFO} Removed Pi-hole meta package";
}

removeWebInterface() {
    # Remove the web interface of Pi-hole
    echo -ne "  ${INFO} Removing Web Interface..."
    rm -rf "${ADMIN_INTERFACE_DIR:-/var/www/html/admin/}" &> /dev/null
    echo -e "${OVER}  ${TICK} Removed Web Interface"
}

removeFTL() {
    # Remove FTL and stop any running FTL service
    if is_command "pihole-FTL"; then
        # service stop & disable from basic_install.sh
        stop_service pihole-FTL
        disable_service pihole-FTL

        echo -ne "  ${INFO} Removing pihole-FTL..."
        rm -f /etc/systemd/system/pihole-FTL.service &> /dev/null
        if [[ -d '/etc/systemd/system/pihole-FTL.service.d' ]]; then
            read -rp "  ${QST} FTL service override directory /etc/systemd/system/pihole-FTL.service.d detected. Do you wish to remove this from your system? [y/N] " answer
            case $answer in
                [yY]*)
                    echo -ne "  ${INFO} Removing /etc/systemd/system/pihole-FTL.service.d..."
                    rm -R /etc/systemd/system/pihole-FTL.service.d &> /dev/null
                    echo -e "${OVER}  ${INFO} Removed /etc/systemd/system/pihole-FTL.service.d"
                ;;
                *) echo -e "  ${INFO} Leaving /etc/systemd/system/pihole-FTL.service.d in place.";;
            esac
        fi
        rm -f /etc/init.d/pihole-FTL &> /dev/null
        rm -f /usr/bin/pihole-FTL &> /dev/null
        echo -e "${OVER}  ${TICK} Removed pihole-FTL"

        # Force systemd reload after service files are removed
        if is_command "systemctl"; then
            echo -ne "  ${INFO} Restarting systemd..."
            systemctl daemon-reload
            echo -e "${OVER}  ${TICK} Restarted systemd..."
        fi
    fi
}

removeCronFiles() {
    # Attempt to preserve backwards compatibility with older versions
    # to guarantee no additional changes were made to /etc/crontab after
    # the installation of pihole, /etc/crontab.pihole should be permanently
    # preserved.
    if [[ -f /etc/crontab.orig ]]; then
        mv /etc/crontab /etc/crontab.pihole
        mv /etc/crontab.orig /etc/crontab
        restart_service cron
        echo -e "  ${TICK} Restored the default system cron"
        echo -e "  ${INFO} A backup of the most recent crontab is saved at /etc/crontab.pihole"
    fi

    # Attempt to preserve backwards compatibility with older versions
    if [[ -f /etc/cron.d/pihole ]];then
        rm -f /etc/cron.d/pihole &> /dev/null
        echo -e "  ${TICK} Removed /etc/cron.d/pihole"
    fi
}

removePiholeFiles() {
    # Remove databases (including user specified non-default paths)
    rm -f "${PIHOLE_DB:-/etc/pihole/pihole-FTL.db}" &> /dev/null
    rm -f "${GRAVITY_DB:-/etc/pihole/gravity.db}" &> /dev/null
    rm -f "${MACVENDOR_DB:-/etc/pihole/macvendor.db}" &> /dev/null

    # Remove pihole config, repo and local files
    rm -rf "${PI_HOLE_CONFIG_DIR:-/etc/pihole}" &> /dev/null
    rm -rf "${PI_HOLE_LOCAL_REPO:-/etc/.pihole}" &> /dev/null
    rm -rf "${PI_HOLE_INSTALL_DIR:-/opt/pihole}" &> /dev/null

    # Remove log files (including user specified non-default paths)
    # and rotated logs
    # Explicitly escape spaces, in case of trailing space in path before wildcard
    rm -f "$(printf '%q' "${FTL_LOG:-/var/log/pihole/FTL.log}")*" &> /dev/null
    rm -f "$(printf '%q' "${DNSMASQ_LOG:-/var/log/pihole/pihole.log}")*" &> /dev/null
    rm -f "$(printf '%q' "${WEBSERVER_LOG:-/var/log/pihole/webserver.log}")*" &> /dev/null

    # remove any remnant log-files from old versions
    rm -rf /var/log/*pihole* &> /dev/null

    # remove log directory
    rm -rf /var/log/pihole &> /dev/null

    # remove the pihole command
    rm -f /usr/local/bin/pihole &> /dev/null

    # remove Pi-hole's bash completion
    rm -f /etc/bash_completion.d/pihole &> /dev/null
    rm -f /etc/bash_completion.d/pihole-FTL &> /dev/null

    # Remove pihole from sudoers for compatibility with old versions
    rm -f /etc/sudoers.d/pihole &> /dev/null

    echo -e "  ${TICK} Removed config files"
}

removeManPage() {
    # If the pihole manpage exists, then delete
    if [[ -f /usr/local/share/man/man8/pihole.8 ]]; then
        rm -f /usr/local/share/man/man8/pihole.8 /usr/local/share/man/man8/pihole-FTL.8 /usr/local/share/man/man5/pihole-FTL.conf.5
        # Rebuild man-db if present
        if is_command "mandb"; then
            mandb -q &>/dev/null
        fi
        echo -e "  ${TICK} Removed pihole man page"
    fi
}

removeUser() {
    # If the pihole user exists, then remove
    if id "pihole" &> /dev/null; then
        if userdel -r pihole 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pihole' user"
        else
            echo -e "  ${CROSS} Unable to remove 'pihole' user"
        fi
    fi

    # If the pihole group exists, then remove
    if getent group "pihole" &> /dev/null; then
        if groupdel pihole 2> /dev/null; then
            echo -e "  ${TICK} Removed 'pihole' group"
        else
            echo -e "  ${CROSS} Unable to remove 'pihole' group"
        fi
    fi
}

restoreResolved() {
    # Restore Resolved from saved configuration, if present
    if [[ -e /etc/systemd/resolved.conf.orig ]] || [[ -e /etc/systemd/resolved.conf.d/90-pi-hole-disable-stub-listener.conf ]]; then
        cp -p /etc/systemd/resolved.conf.orig /etc/systemd/resolved.conf &> /dev/null || true
        rm -f /etc/systemd/resolved.conf.d/90-pi-hole-disable-stub-listener.conf &> /dev/null
        systemctl reload-or-restart systemd-resolved
    fi
}

completionMessage() {
    echo -e "\\n   We're sorry to see you go, but thanks for checking out Pi-hole!
       If you need help, reach out to us on GitHub, Discourse, Reddit or Twitter
       Reinstall at any time: ${COL_BOLD}curl -sSL https://install.pi-hole.net | bash${COL_NC}

      ${COL_RED}Please reset the DNS on your router/clients to restore internet connectivity${COL_NC}
      ${INFO} Pi-hole's meta package has been removed, use the 'autoremove' function from your package manager to remove unused dependencies${COL_NC}
      ${COL_GREEN}Uninstallation Complete! ${COL_NC}"
}

######### SCRIPT ###########
# The ordering here allows clean uninstallation with nothing
# removed before anything that depends upon it.
# eg removeFTL relies on scripts removed by removePiholeFiles
# removeUser relies on commands removed by removeMetaPackage
package_manager_detect
removeWebInterface
removeCronFiles
restoreResolved
removeManPage
removeFTL
removeUser
removeMetaPackage
removePiholeFiles
completionMessage
