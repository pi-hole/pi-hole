#!/usr/bin/env sh

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

    local chaos_api_list authResponse authStatus authData apiAvailable DNSport

    # as we are running locally, we can get the port value from FTL directly
    PI_HOLE_SCRIPT_DIR="/opt/pihole"
    utilsfile="${PI_HOLE_SCRIPT_DIR}/utils.sh"
    # shellcheck source=./advanced/Scripts/utils.sh
    . "${utilsfile}"

    DNSport=$(getFTLConfigValue dns.port)

    # Query the API URLs from FTL using CHAOS TXT local.api.ftl
    # The result is a space-separated enumeration of full URLs
    # e.g., "http://localhost:80/api/" "https://localhost:443/api/"
    chaos_api_list="$(dig +short -p "${DNSport}" chaos txt local.api.ftl @127.0.0.1)"

    # If the query was not successful, the variable is empty
    if [ -z "${chaos_api_list}" ]; then
        echo "API not available. Please check connectivity"
        exit 1
    fi

    # If an error occurred, the variable starts with ;;
    if [ "${chaos_api_list#;;}" != "${chaos_api_list}" ]; then
        echo "Communication error. Is FTL running?"
        exit 1
    fi

    # Iterate over space-separated list of URLs
    while [ -n "${chaos_api_list}" ]; do
        # Get the first URL
        API_URL="${chaos_api_list%% *}"
        # Strip leading and trailing quotes
        API_URL="${API_URL%\"}"
        API_URL="${API_URL#\"}"

        # Test if the API is available at this URL, include delimiter for ease in splitting payload
        authResponse=$(curl --connect-timeout 2 -skS -w ">>%{http_code}" "${API_URL}auth")

        # authStatus is the response http_code, eg. 200, 401.
        # Shell parameter expansion, remove everything up to and including the >> delim
        authStatus=${authResponse#*>>}
        # data is everything from response
        # Shell parameter expansion, remove the >> delim and everything after
        authData=${authResponse%>>*}

        # Test if http status code was 200 (OK) or 401 (authentication required)
        if [ "${authStatus}" = 200 ]; then
            # API is available without authentication
            apiAvailable=true
            needAuth=false
            break

        elif [ "${authStatus}" = 401 ]; then
            # API is available with authentication
            apiAvailable=true
            needAuth=true
            # Check if 2FA is required
            needTOTP=$(echo "${authData}"| jq --raw-output .session.totp 2>/dev/null)
            break

        else
            # API is not available at this port/protocol combination
            apiAvailable=false
            # Remove the first URL from the list
            local last_api_list
            last_api_list="${chaos_api_list}"
            chaos_api_list="${chaos_api_list#* }"

            # If the list did not change, we are at the last element
            if [ "${last_api_list}" = "${chaos_api_list}" ]; then
                # Remove the last element
                chaos_api_list=""
            fi
        fi
    done

    # if apiAvailable is false, no working API was found
    if [ "${apiAvailable}" = false ]; then
        echo "API not available. Please check FTL.log"
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
        if [ "${1}" = "verbose" ]; then
            echo "API Authentication: Not needed"
        fi
        return
    fi

    # Try to read the CLI password (if enabled and readable by the current user)
    if [ -r /etc/pihole/cli_pw ]; then
        password=$(cat /etc/pihole/cli_pw)

        if [ "${1}" = "verbose" ]; then
            echo "API Authentication: Trying to use CLI password"
        fi

        # If we can read the CLI password, we can skip 2FA even when it's required otherwise
        needTOTP=false
    elif [ "${1}" = "verbose" ]; then
        echo "API Authentication: CLI password not available"
    fi

    if [ -z "${password}" ]; then
        # no password read from CLI file
        echo "Please enter your password:"
        # secretly read the password
        secretRead; printf '\n'
    fi

    if [ "${needTOTP}" = true ]; then
        # 2FA required
        echo "Please enter the correct second factor."
        echo "(Can be any number if you used the app password)"
        read -r totp
    fi

    # Try to authenticate using the supplied password (CLI file or user input) and TOTP
    Authentication "${1}"

    # Try to login again until the session is valid
    while [ ! "${validSession}" = true ]  ; do

        # Print the error message if there is one
        if  [ ! "${sessionError}" = "null"  ] && [ "${1}" = "verbose" ]; then
            echo "Error: ${sessionError}"
        fi
        # Print the session message if there is one
        if  [ ! "${sessionMessage}" = "null" ] && [ "${1}" = "verbose" ]; then
            echo "Error: ${sessionMessage}"
        fi

        if  [ "${1}" = "verbose" ]; then
            # If we are not in verbose mode, no need to print the error message again
            echo "Please enter your Pi-hole password"
        else

            echo "Authentication failed. Please enter your Pi-hole password"
        fi

        # secretly read the password
        secretRead; printf '\n'

        if [ "${needTOTP}" = true ]; then
            echo "Please enter the correct second factor:"
            echo "(Can be any number if you used the app password)"
            read -r totp
        fi

        # Try to authenticate again
        Authentication "${1}"
    done

}

Authentication() {
    sessionResponse="$(curl --connect-timeout 2 -skS -X POST "${API_URL}auth" --user-agent "Pi-hole cli" --data "{\"password\":\"${password}\", \"totp\":${totp:-null}}" )"

    if [ -z "${sessionResponse}" ]; then
        echo "No response from FTL server. Please check connectivity"
        exit 1
    fi

    # obtain validity, session ID, sessionMessage and error message from
    # session response, apply default values if none returned
    result=$(echo "${sessionResponse}" | jq -r '
        (.session.valid // false),
        (.session.sid // null),
        (.session.message // null),
        (.error.message // null)
    ' 2>/dev/null)

    validSession=$(echo "${result}" | sed -n '1p')
    SID=$(echo "${result}" | sed -n '2p')
    sessionMessage=$(echo "${result}" | sed -n '3p')
    sessionError=$(echo "${result}" | sed -n '4p')

    if [ "${1}" = "verbose" ]; then
        if [ "${validSession}" = true ]; then
            echo "API Authentication: ${COL_GREEN}Success${COL_NC}"
        else
            echo "API Authentication: ${COL_RED}Failed${COL_NC}"
        fi
    fi
}

LogoutAPI() {
    # if a valid Session exists (no password required or successful Authentication) and
    # SID is not null (successful Authentication only), delete the session
    if [ "${validSession}" = true ] && [ ! "${SID}" = null ]; then
        # Try to delete the session. Omit the output, but get the http status code
        deleteResponse=$(curl -skS -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}auth"  -H "Accept: application/json" -H "sid: ${SID}")

        case "${deleteResponse}" in
            "401") echo "Logout attempt without a valid session. Unauthorized!";;
            "204") if [ "${1}" = "verbose" ]; then echo "API Logout: ${COL_GREEN}Success${COL_NC} (session deleted)"; fi;;
        esac;
    elif [ "${1}" = "verbose" ]; then
        echo "API Logout: ${COL_GREEN}Success${COL_NC} (no valid session)"
    fi
}

GetFTLData() {
  local data response status
  # get the data from querying the API as well as the http status code
  response=$(curl -skS -w "%{http_code}" -X GET "${API_URL}$1" -H "Accept: application/json" -H "sid: ${SID}" )

  if [ "${2}" = "raw" ]; then
    # return the raw response
    echo "${response}"
  else

    # status are the last 3 characters
    # not using ${response#"${response%???}"}" here because it's extremely slow on big responses
    status=$(printf "%s" "${response}" | tail -c 3)
    # data is everything from response without the last 3 characters
    data="${response%???}"

    # return only the data
    if [ "${status}" = 200 ]; then
        # response OK
        printf %s "${data}"
    else
        # connection lost
        echo "${status}"
    fi
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

apiFunc() {
  local data response status status_col verbosity

  # Define if the output will be silent (default) or verbose
  verbosity="silent"
  if [ "$1" = "verbose" ]; then
    verbosity="verbose"
    shift
  fi

  # Authenticate with the API
  LoginAPI "${verbosity}"

  if [ "${verbosity}" = "verbose" ]; then
    echo ""
    echo "Requesting: ${COL_PURPLE}GET ${COL_CYAN}${API_URL}${COL_YELLOW}$1${COL_NC}"
    echo ""
  fi

  # Get the data from the API
  response=$(GetFTLData "$1" raw)

  # status are the last 3 characters
  # not using ${response#"${response%???}"}" here because it's extremely slow on big responses
  status=$(printf "%s" "${response}" | tail -c 3)
  # data is everything from response without the last 3 characters
  data="${response%???}"

  # Output the status (200 -> green, else red)
  if [ "${status}" = 200 ]; then
    status_col="${COL_GREEN}"
  else
    status_col="${COL_RED}"
  fi

  # Only print the status in verbose mode or if the status is not 200
  if [ "${verbosity}" = "verbose" ] || [ "${status}" != 200 ]; then
    echo "Status: ${status_col}${status}${COL_NC}"
  fi

  # Output the data. Format it with jq if available and data is actually JSON.
  # Otherwise just print it
  if [ "${verbosity}" = "verbose" ]; then
    echo "Data:"
  fi
  # Attempt to print the data with jq, if it is not valid JSON, or not installed
  # then print the plain text.
  echo "${data}" | jq . 2>/dev/null || echo "${data}"

  # Delete the session
  LogoutAPI "${verbosity}"
}
