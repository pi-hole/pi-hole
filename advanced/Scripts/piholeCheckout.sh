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
PH_TEST=true source ${PI_HOLE_FILES_DIR}/automated\ install/basic-install.sh

readonly WEB_INTERFACE_GIT_URL="https://github.com/pi-hole/AdminLTE.git"
readonly WEB_INTERFACE_DIR="/var/www/html/admin"
readonly PI_HOLE_GIT_URL="https://github.com/pi-hole/pi-hole.git"


# is_repo() sourced from basic-install.sh

fully_fetch_repo() {
  # Add upstream branches to shallow clone
  local directory="${1}"

  cd "${directory}" || return 1
  git fetch --quiet --unshallow || return 1
  return 0
}

get_available_branches(){
  # Return available branches
  local directory="${1}"
  local curdir

  curdir="${PWD}"
  cd "${directory}" || return 1
  # Get reachable remote branches
  git remote show origin | grep 'tracked' | sed 's/tracked//;s/ //g'
  cd "${curdir}" || return 1
  return
}

checkout_pull_branch() {
  # Check out specified branch
  local directory="${1}"
  local branch="${2}"
  local curdir

  curdir="${PWD}"
  cd "${directory}" || return 1
  git checkout "${branch}"
  git pull
  cd "${curdir}" || return 1
  return
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
  if ! is_repo "${PI_HOLE_FILES_DIR}" || ! is_repo "${WEB_INTERFACE_DIR}" ; then
    echo "::: Critical Error: One or more Pi-Hole repos are missing from your system!"
    echo "::: Please re-run the install script from https://github.com/pi-hole/pi-hole"
    exit 1
  fi

  if ! warning1 ; then
    exit 1
  fi

  echo -n "::: Fetching remote branches for Pi-hole core from ${PI_HOLE_GIT_URL} ... "
  if ! fully_fetch_repo "${PI_HOLE_FILES_DIR}" ; then
    echo "::: Fetching all branches for Pi-hole core repo failed!"
    exit 1
  fi
  corebranches=($(get_available_branches "${PI_HOLE_FILES_DIR}"))
  echo " done!"
  echo "::: ${#corebranches[@]} branches available"
  echo ":::"

  echo -n "::: Fetching remote branches for the web interface from ${WEB_INTERFACE_GIT_URL} ... "
  if ! fully_fetch_repo "${WEB_INTERFACE_DIR}" ; then
    echo "::: Fetching all branches for Pi-hole web interface repo failed!"
    exit 1
  fi
  webbranches=($(get_available_branches "${WEB_INTERFACE_DIR}"))
  echo " done!"
  echo "::: ${#webbranches[@]} branches available"
  echo ":::"

  if [[ "${2}" == "dev" ]] ; then
    # Shortcut to check out development branches
    echo "::: Shortcut \"dev\" detected - checking out development / devel branches ..."
    echo "::: Pi-hole core"
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "development"
    echo "::: Web interface"
    checkout_pull_branch "${WEB_INTERFACE_DIR}" "devel"
    echo "::: done!"
  elif [[ "${2}" == "master" ]] ; then
    # Shortcut to check out master branches
    echo "::: Shortcut \"master\" detected - checking out master branches ..."
    echo "::: Pi-hole core"
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "master"
    echo "::: Web interface"
    checkout_pull_branch "${WEB_INTERFACE_DIR}" "master"
    echo "::: done!"
  elif [[ "${2}" == "core" ]] ; then
    # Have to user chosing the branch he wants
    if ! (for e in "${corebranches[@]}"; do [[ "$e" == "${3}" ]] && exit 0; done); then
      echo "::: Requested branch \"${3}\" is not available!"
      echo "::: Available branches for core are:"
      for e in "${corebranches[@]}"; do echo ":::   $e"; done
      exit 1
    fi
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "${3}"
  elif [[ "${2}" == "web" ]] ; then
    # Have to user chosing the branch he wants
    if ! (for e in "${webbranches[@]}"; do [[ "$e" == "${3}" ]] && exit 0; done); then
      echo "::: Requested branch \"${3}\" is not available!"
      echo "::: Available branches for web are:"
      for e in "${webbranches[@]}"; do echo ":::   $e"; done
      exit 1
    fi
    checkout_pull_branch "${WEB_INTERFACE_DIR}" "${3}"
  else
    echo "::: Requested option \"${2}\" is not available!"
    exit 1
  fi

  # Force updating everything
  echo "::: Running installer to upgrade your installation"
  /etc/.pihole/automated\ install/basic-install.sh --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1

  exit 0
}
