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
    local chaos_api_list availabilityResponse

    # Query the API URLs from FTL using CHAOS TXT local.api.ftl
    # The result is a space-separated enumeration of full URLs
    # e.g., "http://localhost:80/api/" "https://localhost:443/api/"
    chaos_api_list="$(dig +short chaos txt local.api.ftl @127.0.0.1)"

    # If the query was not successful, the variable is empty
    if [ -z "${chaos_api_list}" ]; then
        echo "API not available. Please check connectivity"
        exit 1
    fi

    # Iterate over space-separated list of URLs
    while [ -n "${chaos_api_list}" ]; do
        # Get the first URL
        API_URL="${chaos_api_list%% *}"
        # Strip leading and trailing quotes
        API_URL="${API_URL%\"}"
        API_URL="${API_URL#\"}"

        # Test if the API is available at this URL
        availabilityResponse=$(curl -skS -o /dev/null -w "%{http_code}" "${API_URL}auth")

        # Test if http status code was 200 (OK) or 401 (authentication required)
        if [ ! "${availabilityResponse}" = 200 ] && [ ! "${availabilityResponse}" = 401 ]; then
            # API is not available at this port/protocol combination
            API_PORT=""
        else
            # API is available at this URL combination

            if [ "${availabilityResponse}" = 200 ]; then
                # API is available without authentication
                needAuth=false
            fi

            break
        fi

        # Remove the first URL from the list
        local last_api_list
        last_api_list="${chaos_api_list}"
        chaos_api_list="${chaos_api_list#* }"

        # If the list did not change, we are at the last element
        if [ "${last_api_list}" = "${chaos_api_list}" ]; then
            # Remove the last element
            chaos_api_list=""
        fi
    done

    # if API_PORT is empty, no working API port was found
    if [ -n "${API_PORT}" ]; then
        echo "API not available at: ${API_URL}"
        echo "Exiting."
        exit 1
    fi
}

LoginAPI() {
    # If the API URL is not set, test the availability
    if [ -z "${API_URL}" ]; then
        TestAPIAvailability
    fi

    # Exit early if authentication is not needed
    if [ "${needAuth}" = false ]; then
        return
    fi

    # Try to read the CLI password (if enabled and readable by the current user)
    if [ -r /etc/pihole/cli_pw ]; then
        password=$(cat /etc/pihole/cli_pw)

        # Try to authenticate using the CLI password
        Authentication
    fi



    # If this did not work, ask the user for the password
    while [ "${validSession}" = false ] || [ -z "${validSession}" ] ; do
        echo "Authentication failed. Please enter your Pi-hole password"

        # secretly read the password
        secretRead; printf '\n'

        # Try to authenticate again
        Authentication
    done

}

Authentication() {
  sessionResponse="$(curl -skS -X POST "${API_URL}auth" --user-agent "Pi-hole cli " --data "{\"password\":\"${password}\"}" )"

  if [ -z "${sessionResponse}" ]; then
    echo "No response from FTL server. Please check connectivity"
    exit 1
  fi
  # obtain validity and session ID from session response
  validSession=$(echo "${sessionResponse}"| jq .session.valid 2>/dev/null)
  SID=$(echo "${sessionResponse}"| jq --raw-output .session.sid 2>/dev/null)
}

LogoutAPI() {
    # if a valid Session exists (no password required or successful Authentication) and
    # SID is not null (successful Authentication only), delete the session
    if [ "${validSession}" = true ] && [ ! "${SID}" = null ]; then
        # Try to delete the session. Omit the output, but get the http status code
        deleteResponse=$(curl -skS -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}auth"  -H "Accept: application/json" -H "sid: ${SID}")

        case "${deleteResponse}" in
            "401") printf "%b" "Logout attempt without a valid session. Unauthorized!\n";;
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

  if [ "${status}" = 200 ]; then
    # response OK
    printf %s "${data}"
  elif [ "${status}" = 000 ]; then
    # connection lost
    echo "000"
  elif [ "${status}" = 401 ]; then
    # unauthorized
    echo "401"
  fi
}

PostFTLData() {
  local data response status
  # send the data to the API
  response=$(curl -skS -w "%{http_code}" -X POST "${API_URL}$1" --data-raw "$2" -H "Accept: application/json" -H "sid: ${SID}" )
  # data is everything from response without the last 3 characters
  if [ "${3}" = "status" ]; then
    # Keep the status code appended if requested
    printf %s "${response}"
  else
    # Strip the status code
    printf %s "${response%???}"
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
