#!/usr/bin/env bash

# Pi-hole: A black hole for Internet advertisements
# (c) 2020 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Controller for all pihole scripts and functions.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# Ensure there is a newline at the end of the file passed as argument
ensure_newline() {
  # Check if the last line of the passed file is empty, if not, append a newline
  # to the file to ensure we can append new content safely using echo "" >>
  # later on
  [ -n "$(tail -c1 "${1}")" ] && printf '\n' >> "${1}"
  # There was also the suggestion of using a sed-magic call here, however, this
  # had the drawback to updating all the file timestamps whenever the sed was
  # run. This solution only updates the timestamp when actually appending a
  # newline
}