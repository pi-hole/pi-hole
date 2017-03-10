#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Checkout other branches than master
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_FILES_DIR="/etc/.pihole"
PH_TEST="true" source ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh

# webInterfaceGitUrl set in basic-install.sh
# webInterfaceDir set in basic-install.sh
# piholeGitURL set in basic-install.sh
# is_repo() sourced from basic-install.sh

fully_fetch_repo() {
  # Add upstream branches to shallow clone
  local directory="${1}"

  cd "${directory}" || return 1
  if is_repo "${directory}"; then
    git remote set-branches origin '*' || return 1
    git fetch --quiet || return 1
  else
    return 1
  fi
  return 0
}

get_available_branches(){
  # Return available branches
  local directory="${1}"

  cd "${directory}" || return 1
  # Get reachable remote branches
  git remote show origin | grep 'tracked' | sed 's/tracked//;s/ //g'
  return
}

checkout_pull_branch() {
  # Check out specified branch
  local directory="${1}"
  local branch="${2}"

  cd "${directory}" || return 1
  git checkout "${branch}" || return 1
  git pull || return 1
  return 0
}

warning1() {
  echo "::: Note that changing the branch is a severe change of your Pi-hole system."
  echo "::: This is not supported unless one of the developers explicitly asks you to do this!"
  read -r -p "::: Have you read and understood this? [y/N] " response
  case ${response} in
  [yY][eE][sS]|[yY])
    echo "::: Continuing."
    return 0
    ;;
  *)
    echo "::: Aborting."
    return 1
    ;;
  esac
}

checkout()
{
  local corebranches
  local webbranches

  # Avoid globbing
  set -f

  #This is unlikely
  if ! is_repo "${PI_HOLE_FILES_DIR}" || ! is_repo "${webInterfaceDir}" ; then
    echo "::: Critical Error: One or more Pi-Hole repos are missing from your system!"
    echo "::: Please re-run the install script from https://github.com/pi-hole/pi-hole"
    exit 1
  fi

  if [[ -z "${1}" ]]; then
    echo "::: No option detected. Please use 'pihole checkout <master|dev>'."
    echo "::: Or enter the repository and branch you would like to check out:"
    echo "::: 'pihole checkout <web|core> <branchname>'"
    exit 1
  fi

  if ! warning1 ; then
    exit 1
  fi

  echo -n "::: Fetching remote branches for Pi-hole core from ${piholeGitUrl} ... "
  if ! fully_fetch_repo "${PI_HOLE_FILES_DIR}" ; then
    echo "::: Fetching all branches for Pi-hole core repo failed!"
    exit 1
  fi
  corebranches=($(get_available_branches "${PI_HOLE_FILES_DIR}"))
  echo " done!"
  echo "::: ${#corebranches[@]} branches available"
  echo ":::"

  echo -n "::: Fetching remote branches for the web interface from ${webInterfaceGitUrl} ... "
  if ! fully_fetch_repo "${webInterfaceDir}" ; then
    echo "::: Fetching all branches for Pi-hole web interface repo failed!"
    exit 1
  fi
  webbranches=($(get_available_branches "${webInterfaceDir}"))
  echo " done!"
  echo "::: ${#webbranches[@]} branches available"
  echo ":::"

  if [[ "${1}" == "dev" ]] ; then
    # Shortcut to check out development branches
    echo "::: Shortcut \"dev\" detected - checking out development / devel branches ..."
    echo "::: Pi-hole core"
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "development"
    echo "::: Web interface"
    checkout_pull_branch "${webInterfaceDir}" "devel"
    echo "::: done!"
  elif [[ "${1}" == "master" ]] ; then
    # Shortcut to check out master branches
    echo "::: Shortcut \"master\" detected - checking out master branches ..."
    echo "::: Pi-hole core"
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "master"
    echo "::: Web interface"
    checkout_pull_branch "${webInterfaceDir}" "master"
    echo "::: done!"
  elif [[ "${1}" == "core" ]] ; then
    # Have to user chosing the branch he wants
    if ! (for e in "${corebranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
      echo "::: Requested branch \"${2}\" is not available!"
      echo "::: Available branches for core are:"
      for e in "${corebranches[@]}"; do echo ":::   $e"; done
      exit 1
    fi
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "${2}"
  elif [[ "${1}" == "web" ]] ; then
    # Have to user chosing the branch he wants
    if ! (for e in "${webbranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
      echo "::: Requested branch \"${2}\" is not available!"
      echo "::: Available branches for web are:"
      for e in "${webbranches[@]}"; do echo ":::   $e"; done
      exit 1
    fi
    checkout_pull_branch "${webInterfaceDir}" "${2}"
  else
    echo "::: Requested option \"${1}\" is not available!"
    exit 1
  fi

  # Force updating everything
  echo "::: Running installer to upgrade your installation"
  if ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh --unattended; then
   exit 0
  else
   echo "Unable to complete update, contact Pi-hole"
   exit 1
  fi
}

