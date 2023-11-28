#!/usr/bin/env sh
# shellcheck disable=SC3043 #https://github.com/koalaman/shellcheck/wiki/SC3043#exceptions

# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Script to hold api functions for use in other scripts
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.


# The basic usage steps are
# 1) Test Availability of the API
# 2) Try to authenticate (read password if needed)
# 3) Get the data from the API endpoint
# 4) Delete the session


TestAPIAvailability() {

    # as we are running locally, we can get the port value from FTL directly
    local ports port availabilityResonse
    ports="$(pihole-FTL --config webserver.port)"
    port="${ports%%,*}"

    # Iterate over comma separated list of ports
    while [ -n "${ports}" ]; do
        # if the port ends with an "s", it is a secure connection
        if [ "${port#"${port%?}"}" = "s" ]; then
            # remove the "s" from the port
            API_PROT="https"
            API_PORT="${port%?}"
        elif [ "${port#"${port%?}"}" = "r" ]; then
            # Ignore this port, the client may not be able to follow the
            # redirected target when FTL is not used as local resolver
            API_PORT="0"
        else
            # otherwise it is an insecure (plain HTTP) connection
            API_PROT="http"
            API_PORT="${port}"
        fi

        if [ ! "${API_PORT}" = "0" ]; then
            # If the port is of form "ip:port", we need to remove everything before
            # the last ":" in the string, e.g., "[::]:80" -> "80"
            if [ "${API_PORT#*:}" != "${API_PORT}" ]; then
                API_PORT="${API_PORT##*:}"
            fi

            API_URL="${API_PROT}://localhost:${API_PORT}/api"
            availabilityResonse=$(curl -skS -o /dev/null -w "%{http_code}" "${API_URL}/auth")

            # Test if http status code was 200 (OK), 308 (redirect, we follow) 401 (authentication required)
            if [ ! "${availabilityResonse}" = 200 ] && [ ! "${availabilityResonse}" = 308 ] && [ ! "${availabilityResonse}" = 401 ]; then
                # API is not available at this port/protocol combination
                API_PORT="0"
            else
                # API is available at this port/protocol combination
                break
            fi
        fi

        # If the loop has not been broken, remove the first port from the list
        # and get the next port
        ports="${ports#*,}"
        port="${ports%%,*}"
    done

    # if API_PORT is 0, no working API port was found
    if [ "${API_PORT}" = "0" ]; then
        echo "API not available at: ${API_URL}"
        echo "Exiting."
        exit 1
    fi
}

Authenthication() {
    # Try to authenticate
    LoginAPI

    while [ "${validSession}" = false ] || [ -z "${validSession}" ] ; do
        echo "Authentication failed. Please enter your Pi-hole password"

        # secretly read the password
        secretRead; printf '\n'

        # Try to authenticate again
        LoginAPI
    done

    # Loop exited, authentication was successful
    echo "Authentication successful."

}

LoginAPI() {
  sessionResponse="$(curl -skS -X POST "${API_URL}/auth" --user-agent "Pi-hole cli " --data "{\"password\":\"${password}\"}" )"

  if [ -z "${sessionResponse}" ]; then
    echo "No response from FTL server. Please check connectivity"
    exit 1
  fi
  # obtain validity and session ID from session response
  validSession=$(echo "${sessionResponse}"| jq .session.valid 2>/dev/null)
  SID=$(echo "${sessionResponse}"| jq --raw-output .session.sid 2>/dev/null)
}

DeleteSession() {
    # if a valid Session exists (no password required or successful authenthication) and
    # SID is not null (successful authenthication only), delete the session
    if [ "${validSession}" = true ] && [ ! "${SID}" = null ]; then
        # Try to delete the session. Omit the output, but get the http status code
        deleteResponse=$(curl -skS -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}/auth"  -H "Accept: application/json" -H "sid: ${SID}")

        case "${deleteResponse}" in
            "200") printf "%b" "A session that was not created cannot be deleted (e.g., empty API password).\n";;
            "401") printf "%b" "Logout attempt without a valid session. Unauthorized!\n";;
            "410") printf "%b" "Session successfully deleted.\n";;
         esac;
    fi

}

GetFTLData() {
  local data response status
  # get the data from querying the API as well as the http status code
  response=$(curl -skS -w "%{http_code}" -X GET "${API_URL}$1" -H "Accept: application/json" -H "sid: ${SID}" )

  # status are the last 3 characters
  status=$(printf %s "${response#"${response%???}"}")
  # data is everything from response without the last 3 characters
  data=$(printf %s "${response%???}")

  if [ "${status}" = 200 ] || [ "${status}" = 308 ]; then
    # response OK
    echo "${data}"
  elif [ "${status}" = 000 ]; then
    # connection lost
    echo "000"
  elif [ "${status}" = 401 ]; then
    # unauthorized
    echo "401"
  fi
}

secretRead() {

    # POSIX compliant function to read user-input and
    # mask every character entered by (*)
    #
    # This is challenging, because in POSIX, `read` does not support
    # `-s` option (suppressing the input) or
    # `-n` option (reading n chars)


    # This workaround changes the terminal characteristics to not echo input and later resets this option
    # credits https://stackoverflow.com/a/4316765
    # showing asterisk instead of password
    # https://stackoverflow.com/a/24600839
    # https://unix.stackexchange.com/a/464963


    # Save current terminal settings (needed for later restore after password prompt)
    stty_orig=$(stty -g)

    stty -echo # do not echo user input
    stty -icanon min 1 time 0 # disable canonical mode https://man7.org/linux/man-pages/man3/termios.3.html

    unset password
    unset key
    unset charcount
    charcount=0
    while key=$(dd ibs=1 count=1 2>/dev/null); do #read one byte of input
        if [ "${key}" = "$(printf '\0' | tr -d '\0')" ] ; then
            # Enter - accept password
            break
        fi
        if [ "${key}" = "$(printf '\177')" ] ; then
            # Backspace
            if [ $charcount -gt 0 ] ; then
                charcount=$((charcount-1))
                printf '\b \b'
                password="${password%?}"
            fi
        else
            # any other character
            charcount=$((charcount+1))
            printf '*'
            password="$password$key"
        fi
    done

    # restore original terminal settings
    stty "${stty_orig}"
}


TestAPIAvailability
