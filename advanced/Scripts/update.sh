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
  local curdir
  local rc

  curdir="${PWD}"
  cd "${directory}" &> /dev/null || return 1
  git status --short &> /dev/null
  rc=$?
  cd "${curdir}" &> /dev/null || return 1
  return "${rc}"
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

  (prep_repo "${directory}" && git clone -q --depth 1 "${remoteRepo}" "${directory}")
     return
}

update_repo() {
  local directory="${1}"
  local curdir

  curdir="${PWD}"
  cd "${directory}" &> /dev/null || return 1
  # Pull the latest commits
  # Stash all files not tracked for later retrieval
  git stash --all --quiet
  # Force a clean working directory for cloning
  git clean --force -d
  # Fetch latest changes and apply
  git pull --quiet
  cd "${curdir}" &> /dev/null || return 1
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

GitCheckUpdateAvail() {
  local directory="${1}"
  curdir=$PWD;
  cd "${directory}"

  # Fetch latest changes in this repo
  git fetch --quiet origin

  # @ alone is a shortcut for HEAD. Older versions of git
  # need @{0}
  LOCAL="$(git rev-parse @{0})"

  # The suffix @{upstream} to a branchname
  # (short form <branchname>@{u}) refers
  # to the branch that the branch specified
  # by branchname is set to build on top of#
  # (configured with branch.<name>.remote and
  # branch.<name>.merge). A missing branchname
  # defaults to the current one.
  REMOTE="$(git rev-parse @{upstream})"

  if [[ ${#LOCAL} == 0 ]]; then
    echo "::: Error: Local revision could not be obtained, ask Pi-hole support."
    echo "::: Additional debugging output:"
    git status
    exit
  fi
  if [[ ${#REMOTE} == 0 ]]; then
    echo "::: Error: Remote revision could not be obtained, ask Pi-hole support."
    echo "::: Additional debugging output:"
    git status
    exit
  fi
  
  # Change back to original directory
  cd "${curdir}"

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
  local pihole_version_current
  local web_version_current

  #This is unlikely
  if ! is_repo "${PI_HOLE_FILES_DIR}" || ! is_repo "${ADMIN_INTERFACE_DIR}" ; then
    echo "::: Critical Error: One or more Pi-Hole repos are missing from system!"
    echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
    exit 1;
  fi

  echo "::: Checking for updates..."

  if GitCheckUpdateAvail "${PI_HOLE_FILES_DIR}" ; then
    core_update=true
    echo "::: Pi-hole Core:   update available"
  else
    core_update=false
    echo "::: Pi-hole Core:   up to date"
  fi

  if GitCheckUpdateAvail "${ADMIN_INTERFACE_DIR}" ; then
    web_update=true
    echo "::: Web Interface:  update available"
  else
    web_update=false
    echo "::: Web Interface:  up to date"
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
    echo ":::"
    echo "::: Everything is up to date!"
    exit 0

  elif ! ${core_update} && ${web_update} ; then
    echo ":::"
    echo "::: Pi-hole Web Admin files out of date"
    getGitFiles "${ADMIN_INTERFACE_DIR}" "${ADMIN_INTERFACE_GIT_URL}"

  elif ${core_update} && ! ${web_update} ; then
    echo ":::"
    echo "::: Pi-hole core files out of date"
    getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
    /etc/.pihole/automated\ install/basic-install.sh --reconfigure --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1

  elif ${core_update} && ${web_update} ; then
    echo ":::"
    echo "::: Updating Everything"
    getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"
    /etc/.pihole/automated\ install/basic-install.sh --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1
  else
    echo "*** Update script has malfunctioned, fallthrough reached. Please contact support"
    exit 1
  fi

  if [[ "${web_update}" == true ]]; then
    web_version_current="$(/usr/local/bin/pihole version --admin --current)"
    echo ":::"
    echo "::: Web Admin version is now at ${web_version_current}"
    echo "::: If you had made any changes in '/var/www/html/admin/', they have been stashed using 'git stash'"
  fi

  if [[ "${core_update}" == true ]]; then
    pihole_version_current="$(/usr/local/bin/pihole version --pihole --current)"
    echo ":::"
    echo "::: Pi-hole version is now at ${pihole_version_current}"
    echo "::: If you had made any changes in '/etc/.pihole/', they have been stashed using 'git stash'"
  fi

  echo ""
  exit 0

}

main
