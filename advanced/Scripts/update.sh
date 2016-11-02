#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2015, 2016 by Jacob Salmela
# Network-wide ad blocking via your Raspberry Pi
# http://pi-hole.net
# Check Pi-hole core and admin pages versions and determine what
# upgrade (if any) is required. Automatically updates and reinstalls
# application if update is detected.
#
# Pi-hole is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# Variables

readonly ADMIN_INTERFACE_GIT_URL="https://github.com/pi-hole/AdminLTE.git"
readonly ADMIN_INTERFACE_DIR="/var/www/html/admin"
readonly PI_HOLE_GIT_URL="https://github.com/pi-hole/pi-hole.git"
readonly PI_HOLE_FILES_DIR="/etc/.pihole"

is_repo() {
  # Use git to check if directory is currently under VCS, return the value
  local directory="${1}"

  git -C "${directory}" status --short &> /dev/null
  return
}

prep_repo() {
  # Prepare directory for local repository building
  local directory="${1}"

  rm -rf "${directory}" &> /dev/null
  return
}

make_repo() {
  # Remove the non-repod interface and clone the interface
  local remoteRepo="${2}"
  local directory="${1}"

  (prep_repo "${directory}" && git clone -q --depth 1 "${remoteRepo}" "${directory}" > /dev/null)
     return
}

update_repo() {
  local directory="${1}"
  local retVal=0
  # Pull the latest commits

  # Stash all files not tracked for later retrieval
  git -C "${directory}" stash --all --quiet &> /dev/null || ${retVal}=1
  # Force a clean working directory for cloning
  git -C "${directory}" clean --force -d &> /dev/null || ${retVal}=1
  # Fetch latest changes and apply
  git -C "${directory}" pull --quiet &> /dev/null || ${retVal}=1
  return ${retVal}
}

getGitFiles() {
  # Setup git repos for directory and repository passed
  # as arguments 1 and 2
  local directory="${1}"
  local remoteRepo="${2}"
  echo ":::"
  echo "::: Checking for existing repository..."
  if is_repo "${directory}"; then
    echo -n ":::     Updating repository in ${directory}..."
    update_repo "${directory}" || (echo "*** Error: Could not update local repository. Contact support."; exit 1)
    echo " done!"
  else
    echo -n ":::    Cloning ${remoteRepo} into ${directory}..."
    make_repo "${directory}" "${remoteRepo}" || (echo "Unable to clone repository, please contact support"; exit 1)
    echo " done!"
  fi
}

main() {
  local pihole_version_current
  local pihole_version_latest
  local web_version_current
  local web_version_latest

#  if ! is_repo "${PI_HOLE_FILES_DIR}" || ! is_repo "${ADMIN_INTERFACE_DIR}" ; then #This is unlikely
#    echo "::: Critical Error: One or more Pi-Hole repos are missing from system!"
#    echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
#    exit 1;
#  fi

  echo "::: Checking for updates..."
  # Checks Pi-hole version string in format vX.X.X
  pihole_version_current="$(/usr/local/bin/pihole version --pihole --current)"
  pihole_version_latest="$(/usr/local/bin/pihole version --pihole --latest)"
  web_version_current="$(/usr/local/bin/pihole version --admin --current)"
  web_version_latest="$(/usr/local/bin/pihole version --admin --latest)"

  if [[ "${pihole_version_latest}" -eq "-1" || "${web_version_latest}" -eq -1 ]]; then
    echo "*** Unable to contact GitHub for latest version. Please try again later, contact support if this continues."
    exit 1
  fi

  # Logic
  # If latest versions are blank - we've probably hit Github rate limit (stop running `pihole -up so often!):
  #            Update anyway
  # If Core up to date AND web up to date:
  #            Do nothing
  # If Core up to date AND web NOT up to date:
  #            Pull web repo
  # If Core NOT up to date AND web up to date:
  #            pull pihole repo, run install --unattended -- reconfigure
  # if Core NOT up to date AND web NOT up to date:
  #            pull pihole repo run install --unattended

  if [[ "${pihole_version_current}" == "${pihole_version_latest}" ]] && [[ "${web_version_current}" == "${web_version_latest}" ]]; then
    echo ":::"
    echo "::: Pi-hole version is $pihole_version_current"
    echo "::: Web Admin version is $web_version_current"
    echo ":::"
    echo "::: Everything is up to date!"
    exit 0

  elif [[ "${pihole_version_current}" == "${pihole_version_latest}" ]] && [[ "${web_version_current}" < "${web_version_latest}" ]]; then
    echo ":::"
    echo "::: Pi-hole Web Admin files out of date"
    getGitFiles "${ADMIN_INTERFACE_DIR}" "${ADMIN_INTERFACE_GIT_URL}"

    web_updated=true

  elif [[ "${pihole_version_current}" < "${pihole_version_latest}" ]] && [[ "${web_version_current}" == "${web_version_latest}" ]]; then
    echo "::: Pi-hole core files out of date"
    getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
    /etc/.pihole/automated\ install/basic-install.sh --reconfigure --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1
    core_updated=true

  elif [[ "${pihole_version_current}" < "${pihole_version_latest}" ]] && [[ "${web_version_current}" < "${web_version_latest}" ]]; then
    echo "::: Updating Everything"
    getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
    /etc/.pihole/automated\ install/basic-install.sh --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1
    web_updated=true
    core_updated=true
  else
    echo "*** Update script has malfunctioned, fallthrough reached. Please contact support"
    exit 1
  fi

  if [[ "${web_updated}" == true ]]; then
    web_version_current="$(/usr/local/bin/pihole version --admin --current)"
    echo ":::"
    echo "::: Web Admin version is now at ${web_version_current}"
    echo "::: If you had made any changes in '/var/www/html/admin/', they have been stashed using 'git stash'"
  fi

  if [[ "${core_updated}" == true ]]; then
    pihole_version_current="$(/usr/local/bin/pihole version --pihole --current)"
    echo ":::"
    echo "::: Pi-hole version is now at ${pihole_version_current}"
    echo "::: If you had made any changes in '/etc/.pihole/', they have been stashed using 'git stash'"
  fi

  echo ""
  exit 0

}

main
