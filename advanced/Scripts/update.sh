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
readonly ADMIN_INTERFACE_GIT_URL="https://github.com/pi-hole/web.git"
readonly PI_HOLE_GIT_URL="https://github.com/pi-hole/pi-hole.git"
readonly PI_HOLE_FILES_DIR="/etc/.pihole"

SKIP_INSTALL=true

# when --check-only is passed to this script, it will not perform the actual update
CHECK_ONLY=false

# shellcheck source="./automated install/basic-install.sh"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"
# shellcheck source=./advanced/Scripts/COL_TABLE
source "/opt/pihole/COL_TABLE"
# shellcheck source="./advanced/Scripts/utils.sh"
source "${PI_HOLE_INSTALL_DIR}/utils.sh"

# is_repo() sourced from basic-install.sh
# make_repo() sourced from basic-install.sh
# update_repo() source from basic-install.sh
# getGitFiles() sourced from basic-install.sh
# FTLcheckUpdate() sourced from basic-install.sh
# getFTLConfigValue() sourced from utils.sh

# Honour configured paths for the web application.
ADMIN_INTERFACE_DIR=$(getFTLConfigValue "webserver.paths.webroot")$(getFTLConfigValue "webserver.paths.webhome")
readonly ADMIN_INTERFACE_DIR

GitCheckUpdateAvail() {
    local directory
    local curBranch
    directory="${1}"
    curdir=$PWD
    cd "${directory}" || exit 1

    # Fetch latest changes in this repo
    if ! git fetch --quiet origin ; then
        echo -e "\\n  ${COL_RED}Error: Unable to update local repository. Contact Pi-hole Support.${COL_NC}"
        exit 1
    fi

    # Check current branch. If it is master, then check for the latest available tag instead of latest commit.
    curBranch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${curBranch}" == "master" ]]; then
        # get the latest local tag
        LOCAL=$(git describe --abbrev=0 --tags master)
        # get the latest tag from remote
        REMOTE=$(git describe --abbrev=0 --tags origin/master)

    else
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
    fi


    if [[ "${#LOCAL}" == 0 ]]; then
        echo -e "\\n  ${COL_RED}Error: Local revision could not be obtained, please contact Pi-hole Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit 1
    fi
    if [[ "${#REMOTE}" == 0 ]]; then
        echo -e "\\n  ${COL_RED}Error: Remote revision could not be obtained, please contact Pi-hole Support"
        echo -e "  Additional debugging output:${COL_NC}"
        git status
        exit 1
    fi

    # Change back to original directory
    cd "${curdir}" || exit 1

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
    local basicError="\\n  ${COL_RED}Unable to complete update, please contact Pi-hole Support${COL_NC}"
    local core_update
    local web_update
    local FTL_update

    core_update=false
    web_update=false
    FTL_update=false


    # Install packages used by this installation script (necessary if users have removed e.g. git from their systems)
    package_manager_detect
    build_dependency_package
    install_dependent_packages

    # This is unlikely
    if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
        echo -e "\\n  ${COL_RED}Error: Core Pi-hole repo is missing from system!"
        echo -e "  Please re-run install script from https://pi-hole.net${COL_NC}"
        exit 1;
    fi

    echo -e "  ${INFO} Checking for updates..."

    if GitCheckUpdateAvail "${PI_HOLE_FILES_DIR}" ; then
        core_update=true
        echo -e "  ${INFO} Pi-hole Core:\\t${COL_YELLOW}update available${COL_NC}"
    else
        core_update=false
        echo -e "  ${INFO} Pi-hole Core:\\t${COL_GREEN}up to date${COL_NC}"
    fi

    if ! is_repo "${ADMIN_INTERFACE_DIR}" ; then
        echo -e "\\n  ${COL_RED}Error: Web Admin repo is missing from system!"
        echo -e "  Please re-run install script from https://pi-hole.net${COL_NC}"
        exit 1;
    fi

    if GitCheckUpdateAvail "${ADMIN_INTERFACE_DIR}" ; then
        web_update=true
        echo -e "  ${INFO} Web Interface:\\t${COL_YELLOW}update available${COL_NC}"
    else
        web_update=false
        echo -e "  ${INFO} Web Interface:\\t${COL_GREEN}up to date${COL_NC}"
    fi

    local funcOutput
    funcOutput=$(get_binary_name) #Store output of get_binary_name here
    local binary
    binary="pihole-FTL${funcOutput##*pihole-FTL}" #binary name will be the last line of the output of get_binary_name (it always begins with pihole-FTL)

    if FTLcheckUpdate "${binary}" &>/dev/null; then
        FTL_update=true
        echo -e "  ${INFO} FTL:\\t\\t${COL_YELLOW}update available${COL_NC}"
    else
        case $? in
            1)
                echo -e "  ${INFO} FTL:\\t\\t${COL_GREEN}up to date${COL_NC}"
                ;;
            2)
                echo -e "  ${INFO} FTL:\\t\\t${COL_RED}Branch is not available.${COL_NC}\\n\\t\\t\\tUse ${COL_GREEN}pihole checkout ftl [branchname]${COL_NC} to switch to a valid branch."
                exit 1
                ;;
            3)
                echo -e "  ${INFO} FTL:\\t\\t${COL_RED}Something has gone wrong, cannot reach download server${COL_NC}"
                exit 1
                ;;
            *)
                echo -e "  ${INFO} FTL:\\t\\t${COL_RED}Something has gone wrong, contact support${COL_NC}"
                exit 1
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
        printf "  %b %bWarning:%b You are using FTL from a custom branch (%s) and might be missing future releases.\\n" "${INFO}" "${COL_RED}" "${COL_NC}" "${ftlBranch}"
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
        echo -e "  ${INFO} If you had made any changes in '${ADMIN_INTERFACE_DIR}', they have been stashed using 'git stash'"
    fi

    if [[ "${FTL_update}" == true ]]; then
        echo ""
        echo -e "  ${INFO} FTL out of date, it will be updated by the installer."
    fi

    if [[ "${FTL_update}" == true || "${core_update}" == true ]]; then
        ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --repair --unattended || \
            echo -e "${basicError}" && exit 1
    fi

    if [[ "${FTL_update}" == true || "${core_update}" == true || "${web_update}" == true ]]; then
        # Update local and remote versions via updatechecker
        /opt/pihole/updatecheck.sh
        echo -e "  ${INFO} Local version file information updated."
    fi

    # if there was only a web update, show the new versions
    # (on core and FTL updates, this is done as part of the installer run)
    if [[ "${web_update}" == true &&  "${FTL_update}" == false && "${core_update}" == false ]]; then
        "${PI_HOLE_BIN_DIR}"/pihole version
    fi

    echo ""
    exit 0
}

if [[ "$1" == "--check-only" ]]; then
    CHECK_ONLY=true
fi

main
