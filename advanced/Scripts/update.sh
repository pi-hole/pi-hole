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

# shellcheck disable=SC1090
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"
# shellcheck disable=SC1091
source "/opt/pihole/COL_TABLE"

# is_repo() sourced from basic-install.sh
# make_repo() sourced from basic-install.sh
# update_repo() source from basic-install.sh
# getGitFiles() sourced from basic-install.sh

GitCheckUpdateAvail() {
  local directory="${1}"
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
    echo -e "\\n  ${COL_LIGHT_RED}Error: Local revision could not be obtained, please contact Pi-hole Support
  Additional debugging output:${COL_NC}"
    git status
    exit
  fi
  if [[ "${#REMOTE}" == 0 ]]; then
    echo -e "\\n  ${COL_LIGHT_RED}Error: Remote revision could not be obtained, please contact Pi-hole Support
  Additional debugging output:${COL_NC}"
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

FTLcheckUpdate() {
	local FTLversion
	FTLversion=$(/usr/bin/pihole-FTL tag)
	local FTLlatesttag
	FTLlatesttag=$(curl -sI https://github.com/pi-hole/FTL/releases/latest | grep 'Location' | awk -F '/' '{print $NF}' | tr -d '\r\n')

	if [[ "${FTLversion}" != "${FTLlatesttag}" ]]; then
		return 0
	else
		return 1
	fi
}

main() {
  local pihole_version_current
  local web_version_current
  local basicError="\\n  ${COL_LIGHT_RED}Unable to complete update, please contact Pi-hole Support${COL_NC}"
  
  # shellcheck disable=1090,2154
  source "${setupVars}"

  # This is unlikely
  if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
    echo -e "\\n  ${COL_LIGHT_RED}Error: Core Pi-hole repo is missing from system!
  Please re-run install script from https://pi-hole.net${COL_NC}"
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

  if FTLcheckUpdate ; then
    FTL_update=true
    echo -e "  ${INFO} FTL:\\t\\t${COL_YELLOW}update available${COL_NC}"
  else
    FTL_update=false
    echo -e "  ${INFO} FTL:\\t\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
  fi

  # Logic: Don't update FTL when there is a core update available
  # since the core update will run the installer which will itself
  # re-install (i.e. update) FTL
  if ${FTL_update} && ! ${core_update}; then
    echo ""
    echo -e "  ${INFO} FTL out of date"
    FTLdetect
    echo ""
  fi

  if [[ "${INSTALL_WEB}" == true ]]; then
    if ! is_repo "${ADMIN_INTERFACE_DIR}" ; then
      echo -e "\\n  ${COL_LIGHT_RED}Error: Web Admin repo is missing from system!
  Please re-run install script from https://pi-hole.net${COL_NC}"
      exit 1;
    fi

    if GitCheckUpdateAvail "${ADMIN_INTERFACE_DIR}" ; then
      web_update=true
      echo -e "  ${INFO} Web Interface:\\t${COL_YELLOW}update available${COL_NC}"
    else
      web_update=false
      echo -e "  ${INFO} Web Interface:\\t${COL_LIGHT_GREEN}up to date${COL_NC}"
    fi

    # Logic
    # If Core up to date AND web up to date:
    #            Do nothing
    # If Core up to date AND web NOT up to date:
    #            Pull web repo
    # If Core NOT up to date AND web up to date:
    #            pull pihole repo, run install --unattended -- reconfigure
    # if Core NOT up to date AND web NOT up to date:
    #            pull pihole repo run install --unattended

    if ! ${core_update} && ! ${web_update} ; then
      if ! ${FTL_update} ; then
        echo ""
        echo -e "  ${TICK} Everything is up to date!"
        exit 0
      fi
    elif ! ${core_update} && ${web_update} ; then
      echo ""
      echo -e "  ${INFO} Pi-hole Web Admin files out of date"
      getGitFiles "${ADMIN_INTERFACE_DIR}" "${ADMIN_INTERFACE_GIT_URL}"
    elif ${core_update} && ! ${web_update} ; then
      echo ""
      echo -e "  ${INFO} Pi-hole core files out of date"
      getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
      ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --reconfigure --unattended || \
        echo -e "${basicError}" && exit 1
    elif ${core_update} && ${web_update} ; then
      echo ""
      echo -e "  ${INFO} Updating Pi-hole core and web admin files"
      getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
      ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --unattended || \
        echo -e "${basicError}" && exit 1
    else
      echo -e "  ${COL_LIGHT_RED}Update script has malfunctioned, please contact Pi-hole Support${COL_NC}"
      exit 1
    fi
  else # Web Admin not installed, so only verify if core is up to date
    if ! ${core_update}; then
      if ! ${FTL_update} ; then
        echo ""
        echo -e "  ${INFO} Everything is up to date!"
        exit 0
      fi
    else
      echo ""
      echo -e "  ${INFO} Pi-hole Core files out of date"
      getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
      ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --reconfigure --unattended || \
        echo -e "${basicError}" && exit 1
    fi
  fi

  if [[ "${web_update}" == true ]]; then
    web_version_current="$(/usr/local/bin/pihole version --admin --current)"
    echo ""
    echo -e "  ${INFO} Web Admin version is now at ${web_version_current/* v/v}
  ${INFO} If you had made any changes in '/var/www/html/admin/', they have been stashed using 'git stash'"
  fi

  if [[ "${core_update}" == true ]]; then
    pihole_version_current="$(/usr/local/bin/pihole version --pihole --current)"
    echo ""
    echo -e "  ${INFO} Pi-hole version is now at ${pihole_version_current/* v/v}
  ${INFO} If you had made any changes in '/etc/.pihole/', they have been stashed using 'git stash'"
  fi

  if [[ "${FTL_update}" == true ]]; then
    FTL_version_current="$(/usr/bin/pihole-FTL tag)"
    echo -e "\\n  ${INFO} FTL version is now at ${FTL_version_current/* v/v}"
    start_service pihole-FTL
    enable_service pihole-FTL
  fi

  echo ""
  exit 0
}

main
