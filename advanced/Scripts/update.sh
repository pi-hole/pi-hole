#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Check Pi-hole core and admin pages versions and determine what
# upgrade (if any) is required. Automatically updates and reinstalls
# application if update is detected.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Variables
readonly ADMIN_INTERFACE_GIT_URL="https://github.com/pi-hole/AdminLTE.git"
readonly ADMIN_INTERFACE_DIR="/var/www/html/admin"
readonly PI_HOLE_GIT_URL="https://github.com/pi-hole/pi-hole.git"
readonly PI_HOLE_FILES_DIR="/etc/.pihole"

# shellcheck disable=SC2034
PH_TEST=true

# when --check-only is passed to this script, it will not perform the actual update
CHECK_ONLY=false

# shellcheck disable=SC1090
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"
# shellcheck disable=SC1091
source "/opt/pihole/COL_TABLE"

# is_repo() sourced from basic-install.sh
# make_repo() sourced from basic-install.sh
# update_repo() source from basic-install.sh
# getGitFiles() sourced from basic-install.sh
# FTLcheckUpdate() sourced from basic-install.sh

GitCheckUpdateAvail() {
    local directory
    directory="${1}"
    curdir=$PWD
    cd "${directory}" || return

    # Fetch latest changes in this repo
    git fetch --quiet origin

    # @ alone is a shortcut for HEAD. Older versions of git
    # need @{0}
    LOCAL="$(git rev-parse "@{0}")"

    # The suffix @{upstream} to a branchname
    # (short form <branchname>@{u}) refers
    # to the branch that the branch specified
    # by branchname is set to build on top of#
    # (configured with branch.<name>.remote and
    # branch.<name>.merge). A missing branchname
    # defaults to the current one.
    REMOTE="$(git rev-parse "@{upstream}")"

    if [[ "${#LOCAL}" == 0 ]]; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Local revision could not be obtained, please contact Pi-hole Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit
    fi
    if [[ "${#REMOTE}" == 0 ]]; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Remote revision could not be obtained, please contact Pi-hole Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit
    fi

    # Change back to original directory
    cd "${curdir}" || exit

    if [[ "${LOCAL}" != "${REMOTE}" ]]; then
        # Local branch is behind remote branch -> Update
        return 0
    else
        # Local branch is up-to-date or in a situation
        # where this updater cannot be used (like on a
        # branch that exists only locally)
        return 1
    fi
}

main() {
    local basicError="\\n  ${COL_LIGHT_RED}Unable to complete update, please contact Pi-hole Support${COL_NC}"
    local core_update
    local web_update
    local FTL_update

    core_update=false
    web_update=false
    FTL_update=false

    # shellcheck disable=1090,2154
    source "${setupVars}"

    # This is unlikely
    if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
        echo -e "\\n  ${COL_LIGHT_RED}Error: Core Pi-hole repo is missing from system!"
        echo -e "  Please re-run install script from https://pi-hole.net${COL_NC}"
        exit 1;
    fi

    echo -e "  ${INFO} Checking for updates..."

    if GitCheckUpdateAvail "${PI_HOLE_FILES_DIR}" ; then
        core_update=true
        echo -e "  ${INFO} Pi-hole Core:\\t${COL_YELLOW}update available${COL_NC}"
    else
        core_update=false
        echo -e "  ${INFO} Pi-hole Core:\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
    fi

    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        if ! is_repo "${ADMIN_INTERFACE_DIR}" ; then
            echo -e "\\n  ${COL_LIGHT_RED}Error: Web Admin repo is missing from system!"
            echo -e "  Please re-run install script from https://pi-hole.net${COL_NC}"
            exit 1;
        fi

        if GitCheckUpdateAvail "${ADMIN_INTERFACE_DIR}" ; then
            web_update=true
            echo -e "  ${INFO} Web Interface:\\t${COL_YELLOW}update available${COL_NC}"
        else
            web_update=false
            echo -e "  ${INFO} Web Interface:\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
        fi
    fi

    local funcOutput
    funcOutput=$(get_binary_name) #Store output of get_binary_name here
    local binary
    binary="pihole-FTL${funcOutput##*pihole-FTL}" #binary name will be the last line of the output of get_binary_name (it always begins with pihole-FTL)

    if FTLcheckUpdate "${binary}" > /dev/null; then
        FTL_update=true
        echo -e "  ${INFO} FTL:\\t\\t${COL_YELLOW}update available${COL_NC}"
    else
        case $? in
            1)
                echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
                ;;
            2)
                echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_RED}Branch is not available.${COL_NC}\\n\\t\\t\\tUse ${COL_LIGHT_GREEN}pihole checkout ftl [branchname]${COL_NC} to switch to a valid branch."
                ;;
            *)
                echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_RED}Something has gone wrong, contact support${COL_NC}"
        esac
        FTL_update=false
    fi

    # Determine FTL branch
    local ftlBranch
    if [[ -f "/etc/pihole/ftlbranch" ]]; then
        ftlBranch=$(</etc/pihole/ftlbranch)
    else
        ftlBranch="master"
    fi

    if [[ ! "${ftlBranch}" == "master" && ! "${ftlBranch}" == "development" ]]; then
        # Notify user that they are on a custom branch which might mean they they are lost
        # behind if a branch was merged to development and got abandoned
        printf "  %b %bWarning:%b You are using FTL from a custom branch (%s) and might be missing future releases.\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}" "${ftlBranch}"
    fi

    if [[ "${core_update}" == false && "${web_update}" == false && "${FTL_update}" == false ]]; then
        echo ""
        echo -e "  ${TICK} Everything is up to date!"
        exit 0
    fi

    if [[ "${CHECK_ONLY}" == true ]]; then
        echo ""
        exit 0
    fi

    if [[ "${core_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} Pi-hole core files out of date, updating local repo."
        getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
        echo -e "  ${INFO} If you had made any changes in '/etc/.pihole/', they have been stashed using 'git stash'"
    fi

    if [[ "${web_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} Pi-hole Web Admin files out of date, updating local repo."
        getGitFiles "${ADMIN_INTERFACE_DIR}" "${ADMIN_INTERFACE_GIT_URL}"
        echo -e "  ${INFO} If you had made any changes in '/var/www/html/admin/', they have been stashed using 'git stash'"
    fi

    if [[ "${FTL_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} FTL out of date, it will be updated by the installer."
    fi

    if [[ "${FTL_update}" == true || "${core_update}" == true ]]; then
        ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --reconfigure --unattended || \
        echo -e "${basicError}" && exit 1
    fi

    if [[ "${FTL_update}" == true || "${core_update}" == true || "${web_update}" == true ]]; then
        # Force an update of the updatechecker
        /opt/pihole/updatecheck.sh
        /opt/pihole/updatecheck.sh x remote
        echo -e "  ${INFO} Local version file information updated."
    fi

    echo ""
    exit 0
}

if [[ "$1" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

main
