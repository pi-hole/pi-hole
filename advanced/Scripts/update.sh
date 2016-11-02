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
	# Use git to check if directory is currently under VCS
	local directory="${1}"
	cd "${directory}" &> /dev/null || false
  $(git status --short &> /dev/null)
  return
}

 make_repo() {
	# Remove the non-repod interface and clone the interface
	echo -n ":::    Cloning $2 into $1..."
	rm -rf "${1}"
	git clone -q --depth 1 "${2}" "${1}" > /dev/null || exit 1
	echo " done!"
}

update_repo() {
# Pull the latest commits
	echo -n ":::     Updating repo in $1..."
	cd "${1}" || exit 1
	git stash -q > /dev/null || exit 1
	git pull -q > /dev/null || exit 1
	echo " done!"
}

getGitFiles() {
	# Setup git repos for directory and repository passed
	# as arguments 1 and 2
	echo ":::"
	echo "::: Checking for existing repository..."
	if is_repo "${1}"; then
		update_repo "${1}"
	else
		make_repo "${1}" "${2}"
	fi
}

main() {

  is_repo "${PI_HOLE_FILES_DIR}"
  if [[ $? -ne 0 ]]; then #This is unlikely
    echo "::: Critical Error: Pi-Hole repo missing from system!"
    echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
    exit 1;
  fi

  is_repo "${ADMIN_INTERFACE_DIR}" &> /dev/null
  if [[ $? -ne 0 ]]; then #This is unlikely
    echo "::: Critical Error: Pi-Hole repo missing from system!"
    echo "::: Please re-run install script from https://github.com/pi-hole/pi-hole"
    exit 1;
  fi

  echo "::: Checking for updates..."
  # Checks Pi-hole version > pihole only > current local git repo version : returns string in format vX.X.X
  local -r pihole_version_current="$(/usr/local/bin/pihole -v -p -c)"
  # Checks Pi-hole version > pihole only > remote upstream repo version : returns string in format vX.X.X
  local -r pihole_version_latest="$(/usr/local/bin/pihole -v -p -l)"

  # Checks Pi-hole version > admin only > current local git repo version : returns string in format vX.X.X
  local -r web_version_current="$(/usr/local/bin/pihole -v -a -c)"
  # Checks Pi-hole version > admin only > remote upstream repo version : returns string in format vX.X.X
  local -r web_version_latest="$(/usr/local/bin/pihole -v -a -l)"

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
    echo "::: Pi-hole version is $pihole_version_current"
    echo "::: Web Admin version is $web_version_current"
    echo "::: Everything is up to date!"
    echo ""
    exit 0

  elif [[ "${pihole_version_current}" == "${pihole_version_latest}" ]] && [[ "${web_version_current}" != "${web_version_latest}" ]]; then
    echo "::: Pi-hole Web Admin files out of date"
    getGitFiles "${ADMIN_INTERFACE_DIR}" "${ADMIN_INTERFACE_GIT_URL}"
    echo ":::"
    web_version_current="$(/usr/local/bin/pihole -v -a -c)"
    echo "::: Web Admin version is now at ${web_version_current}"
    echo "::: If you had made any changes in '/var/www/html/admin', they have been stashed using 'git stash'"
    echo ""
  elif [[ "${pihole_version_current}" != "${pihole_version_latest}" ]] && [[ "${web_version_current}" == "${web_version_latest}" ]]; then
    echo "::: Pi-hole core files out of date"
    getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"

    /etc/.pihole/automated\ install/basic-install.sh --reconfigure --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1

    echo ":::"
    pihole_version_current="$(/usr/local/bin/pihole -v -p -c)"
    echo "::: Pi-hole version is now at ${pihole_version_current}"
    echo "::: If you had made any changes in '/etc/.pihole', they have been stashed using 'git stash'"
    echo ""
  elif [[ "${pihole_version_current}" != "${pihole_version_latest}" ]] && [[ "${web_version_current}" != "${web_version_latest}" ]]; then
    echo "::: Updating Everything"
    getGitFiles "${PI_HOLE_FILES_DIR}" "${PI_HOLE_GIT_URL}"

    /etc/.pihole/automated\ install/basic-install.sh --unattended || echo "Unable to complete update, contact Pi-hole" && exit 1

    # Checks Pi-hole version > admin only > current local git repo version : returns string in format vX.X.X
    web_version_current="$(/usr/local/bin/pihole -v -a -c)"
    # Checks Pi-hole version > admin only > current local git repo version : returns string in format vX.X.X
    pihole_version_current="$(/usr/local/bin/pihole -v -p -c)"
    echo ":::"
    echo "::: Pi-hole version is now at ${pihole_version_current}"
    echo "::: If you had made any changes in '/etc/.pihole', they have been stashed using 'git stash'"
    echo ":::"
    echo "::: Pi-hole version is now at ${pihole_version_current}"
    echo "::: If you had made any changes in '/etc/.pihole', they have been stashed using 'git stash'"
    echo ""
  fi
}

main
