#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Switch Pi-hole subsystems to a different Github branch.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_FILES_DIR="/etc/.pihole"
PH_TEST="true"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"

# webInterfaceGitUrl set in basic-install.sh
# webInterfaceDir set in basic-install.sh
# piholeGitURL set in basic-install.sh
# is_repo() sourced from basic-install.sh
# setupVars set in basic-install.sh

source "${setupVars}"
update="false"

coltable="/opt/pihole/COL_TABLE"
source ${coltable}

check_download_exists() {
  status=$(curl --head --silent "https://ftl.pi-hole.net/${1}" | head -n 1)
  if grep -q "404" <<< "$status"; then
    return 1
  else
    return 0
  fi
}

FTLinstall() {
  # Download and install FTL binary
  local binary
  binary="${1}"
  local path
  path="${2}"
  local str
  str="Installing FTL"
  echo -ne "  ${INFO} ${str}..."

  if curl -sSL --fail "https://ftl.pi-hole.net/${path}" -o "/tmp/${binary}"; then
    # Get sha1 of the binary we just downloaded for verification.
    curl -sSL --fail "https://ftl.pi-hole.net/${path}.sha1" -o "/tmp/${binary}.sha1"
    # Check if we just downloaded text, or a binary file.
    cd /tmp || return 1
    if sha1sum --status --quiet -c "${binary}".sha1; then
      echo -n "transferred... "
      stop_service pihole-FTL &> /dev/null
      install -T -m 0755 "/tmp/${binary}" "/usr/bin/pihole-FTL"
      rm "/tmp/${binary}" "/tmp/${binary}.sha1"
      start_service pihole-FTL &> /dev/null
      echo -e "${OVER}  ${TICK} ${str}"
      return 0
    else
      echo -e "${OVER}  ${CROSS} ${str}"
      echo -e "  ${COL_LIGHT_RED}Error: Download of binary from ftl.pi-hole.net failed${COL_NC}"
      return 1
    fi
  else
    echo -e "${OVER}  ${CROSS} ${str}"
    echo -e "  ${COL_LIGHT_RED}Error: URL not found${COL_NC}"
  fi
}

get_binary_name() {
  local machine
  machine=$(uname -m)

  local str
  str="Detecting architecture"
  echo -ne "  ${INFO} ${str}..."
  if [[ "${machine}" == "arm"* || "${machine}" == *"aarch"* ]]; then
    # ARM
    local rev
    rev=$(uname -m | sed "s/[^0-9]//g;")
    local lib
    lib=$(ldd /bin/ls | grep -E '^\s*/lib' | awk '{ print $1 }')
    if [[ "${lib}" == "/lib/ld-linux-aarch64.so.1" ]]; then
      echo -e "${OVER}  ${TICK} Detected ARM-aarch64 architecture"
      binary="pihole-FTL-aarch64-linux-gnu"
    elif [[ "${lib}" == "/lib/ld-linux-armhf.so.3" ]]; then
      if [[ "$rev" -gt "6" ]]; then
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv7+)"
        binary="pihole-FTL-arm-linux-gnueabihf"
      else
        echo -e "${OVER}  ${TICK} Detected ARM-hf architecture (armv6 or lower) Using ARM binary"
        binary="pihole-FTL-arm-linux-gnueabi"
      fi
    else
      echo -e "${OVER}  ${TICK} Detected ARM architecture"
      binary="pihole-FTL-arm-linux-gnueabi"
    fi
  elif [[ "${machine}" == "ppc" ]]; then
    # PowerPC
    echo -e "${OVER}  ${TICK} Detected PowerPC architecture"
    binary="pihole-FTL-powerpc-linux-gnu"
  elif [[ "${machine}" == "x86_64" ]]; then
    # 64bit
    echo -e "${OVER}  ${TICK} Detected x86_64 architecture"
    binary="pihole-FTL-linux-x86_64"
  else
    # Something else - we try to use 32bit executable and warn the user
    if [[ ! "${machine}" == "i686" ]]; then
      echo -e "${OVER}  ${CROSS} ${str}...
      ${COL_LIGHT_RED}Not able to detect architecture (unknown: ${machine}), trying 32bit executable
      Contact support if you experience issues (e.g: FTL not running)${COL_NC}"
    else
      echo -e "${OVER}  ${TICK} Detected 32bit (i686) architecture"
    fi
    binary="pihole-FTL-linux-x86_32"
  fi
}

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

get_available_branches() {
  # Return available branches
  local directory
  directory="${1}"
  local output

  cd "${directory}" || return 1
  # Get reachable remote branches, but store STDERR as STDOUT variable
  output=$( { git remote show origin | grep 'tracked' | sed 's/tracked//;s/ //g'; } 2>&1 )
  echo "$output"
  return
}

fetch_checkout_pull_branch() {
  # Check out specified branch
  local directory
  directory="${1}"
  local branch
  branch="${2}"

  # Set the reference for the requested branch, fetch, check it put and pull it
  cd "${directory}" || return 1
  git remote set-branches origin "${branch}" || return 1
  git stash --all --quiet &> /dev/null || true
  git clean --quiet --force -d || true
  git fetch --quiet || return 1
  checkout_pull_branch "${directory}" "${branch}" || return 1
}

checkout_pull_branch() {
  # Check out specified branch
  local directory
  directory="${1}"
  local branch
  branch="${2}"
  local oldbranch

  cd "${directory}" || return 1

  oldbranch="$(git symbolic-ref HEAD)"

  str="Switching to branch: '${branch}' from '${oldbranch}'"
  echo -ne "  ${INFO} $str"
  git checkout "${branch}" --quiet || return 1
  echo -e "${OVER}  ${TICK} $str"


  if [[ "$(git diff "${oldbranch}" | grep -c "^")" -gt "0" ]]; then
    update="true"
  fi

  git_pull=$(git pull || return 1)

  if [[ "$git_pull" == *"up-to-date"* ]]; then
    echo -e "  ${INFO} ${git_pull}"
  else
    echo -e "$git_pull\\n"
  fi

  return 0
}

warning1() {
  echo "  Please note that changing branches severely alters your Pi-hole subsystems"
  echo "  Features that work on the master branch, may not on a development branch"
  echo -e "  ${COL_LIGHT_RED}This feature is NOT supported unless a Pi-hole developer explicitly asks!${COL_NC}"
  read -r -p "  Have you read and understood this? [y/N] " response
  case "${response}" in
  [yY][eE][sS]|[yY])
    echo ""
    return 0
    ;;
  *)
    echo -e "\\n  ${INFO} Branch change has been cancelled"
    return 1
    ;;
  esac
}

checkout() {
  local corebranches
  local webbranches

  # Avoid globbing
  set -f

  # This is unlikely
  if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
    echo -e "  ${COL_LIGHT_RED}Error: Core Pi-hole repo is missing from system!
  Please re-run install script from https://github.com/pi-hole/pi-hole${COL_NC}"
    exit 1;
  fi
  if [[ "${INSTALL_WEB}" == "true" ]]; then
    if ! is_repo "${webInterfaceDir}" ; then
     echo -e "  ${COL_LIGHT_RED}Error: Web Admin repo is missing from system!
  Please re-run install script from https://github.com/pi-hole/pi-hole${COL_NC}"
      exit 1;
    fi
  fi

  if [[ -z "${1}" ]]; then
    echo -e "  ${COL_LIGHT_RED}Invalid option${COL_NC}
  Try 'pihole checkout --help' for more information."
    exit 1
  fi

  if ! warning1 ; then
    exit 1
  fi

  if [[ "${1}" == "dev" ]] ; then
    # Shortcut to check out development branches
    echo -e "  ${INFO} Shortcut \"dev\" detected - checking out development / devel branches..."
    echo ""
    echo -e "  ${INFO} Pi-hole Core"
    fetch_checkout_pull_branch "${PI_HOLE_FILES_DIR}" "development" || { echo "  ${CROSS} Unable to pull Core developement branch"; exit 1; }
    if [[ "${INSTALL_WEB}" == "true" ]]; then
      echo ""
      echo -e "  ${INFO} Web interface"
      fetch_checkout_pull_branch "${webInterfaceDir}" "devel" || { echo "  ${CROSS} Unable to pull Web development branch"; exit 1; }
    fi
    #echo -e "  ${TICK} Pi-hole Core"

    get_binary_name
    local path
    path="development/${binary}"
    echo "development" > /etc/pihole/ftlbranch
    FTLinstall "${binary}" "${path}"
  elif [[ "${1}" == "master" ]] ; then
    # Shortcut to check out master branches
    echo -e "  ${INFO} Shortcut \"master\" detected - checking out master branches..."
    echo -e "  ${INFO} Pi-hole core"
    fetch_checkout_pull_branch "${PI_HOLE_FILES_DIR}" "master" || { echo "  ${CROSS} Unable to pull Core master branch"; exit 1; }
    if [[ ${INSTALL_WEB} == "true" ]]; then
      echo -e "  ${INFO} Web interface"
      fetch_checkout_pull_branch "${webInterfaceDir}" "master" || { echo "  ${CROSS} Unable to pull Web master branch"; exit 1; }
    fi
    #echo -e "  ${TICK} Web Interface"
    get_binary_name
    local path
    path="master/${binary}"
    echo "master" > /etc/pihole/ftlbranch
    FTLinstall "${binary}" "${path}"
  elif [[ "${1}" == "core" ]] ; then
    str="Fetching branches from ${piholeGitUrl}"
    echo -ne "  ${INFO} $str"
    if ! fully_fetch_repo "${PI_HOLE_FILES_DIR}" ; then
      echo -e "${OVER}  ${CROSS} $str"
      exit 1
    fi
    corebranches=($(get_available_branches "${PI_HOLE_FILES_DIR}"))

    if [[ "${corebranches[*]}" == *"master"* ]]; then
      echo -e "${OVER}  ${TICK} $str
  ${INFO} ${#corebranches[@]} branches available for Pi-hole Core"
    else
      # Print STDERR output from get_available_branches
      echo -e "${OVER}  ${CROSS} $str\\n\\n${corebranches[*]}"
      exit 1
    fi

    echo ""
    # Have the user choose the branch they want
    if ! (for e in "${corebranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
      echo -e "  ${INFO} Requested branch \"${2}\" is not available"
      echo -e "  ${INFO} Available branches for Core are:"
      for e in "${corebranches[@]}"; do echo "      - $e"; done
      exit 1
    fi
    checkout_pull_branch "${PI_HOLE_FILES_DIR}" "${2}"
  elif [[ "${1}" == "web" ]] && [[ "${INSTALL_WEB}" == "true" ]] ; then
    str="Fetching branches from ${webInterfaceGitUrl}"
    echo -ne "  ${INFO} $str"
    if ! fully_fetch_repo "${webInterfaceDir}" ; then
      echo -e "${OVER}  ${CROSS} $str"
      exit 1
    fi
    webbranches=($(get_available_branches "${webInterfaceDir}"))

    if [[ "${webbranches[*]}" == *"master"* ]]; then
      echo -e "${OVER}  ${TICK} $str
  ${INFO} ${#webbranches[@]} branches available for Web Admin"
    else
      # Print STDERR output from get_available_branches
      echo -e "${OVER}  ${CROSS} $str\\n\\n${webbranches[*]}"
      exit 1
    fi

    echo ""
    # Have the user choose the branch they want
    if ! (for e in "${webbranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
      echo -e "  ${INFO} Requested branch \"${2}\" is not available"
      echo -e "  ${INFO} Available branches for Web Admin are:"
      for e in "${webbranches[@]}"; do echo "      - $e"; done
      exit 1
    fi
    checkout_pull_branch "${webInterfaceDir}" "${2}"
  elif [[ "${1}" == "ftl" ]] ; then
    get_binary_name
    local path
    path="${2}/${binary}"

    if check_download_exists "$path"; then
        echo "  ${TICK} Branch ${2} exists"
        echo "${2}" > /etc/pihole/ftlbranch
        FTLinstall "${binary}" "${path}"
    else
        echo "  ${CROSS} Requested branch \"${2}\" is not available"
        ftlbranches=( $(git ls-remote https://github.com/pi-hole/ftl | grep 'heads' | sed 's/refs\/heads\///;s/ //g' | awk '{print $2}') )
        echo -e "  ${INFO} Available branches for FTL are:"
        for e in "${ftlbranches[@]}"; do echo "      - $e"; done
        exit 1
    fi

  else
    echo -e "  ${INFO} Requested option \"${1}\" is not available"
    exit 1
  fi

  # Force updating everything
  if [[ ( ! "${1}" == "web" && ! "${1}" == "ftl" ) && "${update}" == "true" ]]; then
    echo -e "  ${INFO} Running installer to upgrade your installation"
    if "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh" --unattended; then
      exit 0
    else
      echo -e "  ${COL_LIGHT_RED} Error: Unable to complete update, please contact support${COL_NC}"
      exit 1
    fi
  fi
}
