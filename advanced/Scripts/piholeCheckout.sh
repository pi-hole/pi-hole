#!/usr/bin/env bash
# Pi-hole: A black hole for Internet advertisements
# (c) 2017 Pi-hole, LLC (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# Switch Pi-hole subsystems to a different GitHub branch.
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

readonly PI_HOLE_FILES_DIR="/etc/.pihole"
SKIP_INSTALL="true"
# shellcheck source="./automated install/basic-install.sh"
source "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh"

# webInterfaceGitUrl set in basic-install.sh
# webInterfaceDir set in basic-install.sh
# piholeGitURL set in basic-install.sh
# is_repo() sourced from basic-install.sh
# check_download_exists sourced from basic-install.sh
# fully_fetch_repo sourced from basic-install.sh
# get_available_branches sourced from basic-install.sh
# fetch_checkout_pull_branch sourced from basic-install.sh
# checkout_pull_branch sourced from basic-install.sh

warning1() {
    echo "  Please note that changing branches severely alters your Pi-hole subsystems"
    echo "  Features that work on the master branch, may not on a development branch"
    echo -e "  ${COL_RED}This feature is NOT supported unless a Pi-hole developer explicitly asks!${COL_NC}"
    read -r -p "  Have you read and understood this? [y/N] " response
    case "${response}" in
        [yY][eE][sS]|[yY])
            echo ""
            return 0
            ;;
        *)
            echo -e "\\n  ${INFO} Branch change has been canceled"
            return 1
            ;;
    esac
}

checkout() {
    local corebranches
    local webbranches

    # Check if FTL is installed - do this early on as FTL is a hard dependency for Pi-hole
    local funcOutput
    funcOutput=$(get_binary_name) #Store output of get_binary_name here
    local binary
    binary="pihole-FTL${funcOutput##*pihole-FTL}" #binary name will be the last line of the output of get_binary_name (it always begins with pihole-FTL)

    # Avoid globbing
    set -f

    # This is unlikely
    if ! is_repo "${PI_HOLE_FILES_DIR}" ; then
        echo -e "  ${COL_RED}Error: Core Pi-hole repo is missing from system!"
        echo -e "  Please re-run install script from https://github.com/pi-hole/pi-hole${COL_NC}"
        exit 1;
    fi

    if ! is_repo "${webInterfaceDir}" ; then
        echo -e "  ${COL_RED}Error: Web Admin repo is missing from system!"
        echo -e "  Please re-run install script from https://github.com/pi-hole/pi-hole${COL_NC}"
        exit 1;
    fi

    if [[ -z "${1}" ]]; then
        echo -e "  ${COL_RED}Invalid option${COL_NC}"
        echo -e "  Try 'pihole checkout --help' for more information."
        exit 1
    fi

    if ! warning1 ; then
        exit 1
    fi

    if [[ "${1}" == "dev" ]] ; then
        # Shortcut to check out development branches
        echo -e "  ${INFO} Shortcut \"${COL_YELLOW}dev${COL_NC}\" detected - checking out development branches..."
        echo ""
        echo -e "  ${INFO} Pi-hole Core"
        fetch_checkout_pull_branch "${PI_HOLE_FILES_DIR}" "development" || { echo "  ${CROSS} Unable to pull Core development branch"; exit 1; }
        echo ""
        echo -e "  ${INFO} Web interface"
        fetch_checkout_pull_branch "${webInterfaceDir}" "development" || { echo "  ${CROSS} Unable to pull Web development branch"; exit 1; }
        #echo -e "  ${TICK} Pi-hole Core"

        local path
        path="development/${binary}"
        echo "development" > /etc/pihole/ftlbranch
        chmod 644 /etc/pihole/ftlbranch
    elif [[ "${1}" == "master" ]] ; then
        # Shortcut to check out master branches
        echo -e "  ${INFO} Shortcut \"${COL_YELLOW}master${COL_NC}\" detected - checking out master branches..."
        echo -e "  ${INFO} Pi-hole core"
        fetch_checkout_pull_branch "${PI_HOLE_FILES_DIR}" "master" || { echo "  ${CROSS} Unable to pull Core master branch"; exit 1; }
        echo -e "  ${INFO} Web interface"
        fetch_checkout_pull_branch "${webInterfaceDir}" "master" || { echo "  ${CROSS} Unable to pull Web master branch"; exit 1; }
        #echo -e "  ${TICK} Web Interface"
        local path
        path="master/${binary}"
        echo "master" > /etc/pihole/ftlbranch
        chmod 644 /etc/pihole/ftlbranch
    elif [[ "${1}" == "core" ]] ; then
        str="Fetching branches from ${piholeGitUrl}"
        echo -ne "  ${INFO} $str"
        if ! fully_fetch_repo "${PI_HOLE_FILES_DIR}" ; then
            echo -e "${OVER}  ${CROSS} $str"
            exit 1
        fi
        mapfile -t corebranches < <(get_available_branches "${PI_HOLE_FILES_DIR}")

        if [[ "${corebranches[*]}" == *"master"* ]]; then
            echo -e "${OVER}  ${TICK} $str"
            echo -e "  ${INFO} ${#corebranches[@]} branches available for Pi-hole Core"
        else
            # Print STDERR output from get_available_branches
            echo -e "${OVER}  ${CROSS} $str\\n\\n${corebranches[*]}"
            exit 1
        fi

        echo ""
        # Have the user choose the branch they want
        if ! (for e in "${corebranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
            echo -e "  ${INFO} Requested branch \"${COL_CYAN}${2}${COL_NC}\" is not available"
            echo -e "  ${INFO} Available branches for Core are:"
            for e in "${corebranches[@]}"; do echo "      - $e"; done
            exit 1
        fi
        checkout_pull_branch "${PI_HOLE_FILES_DIR}" "${2}"
    elif [[ "${1}" == "web" ]] ; then
        str="Fetching branches from ${webInterfaceGitUrl}"
        echo -ne "  ${INFO} $str"
        if ! fully_fetch_repo "${webInterfaceDir}" ; then
            echo -e "${OVER}  ${CROSS} $str"
            exit 1
        fi
        mapfile -t webbranches < <(get_available_branches "${webInterfaceDir}")

        if [[ "${webbranches[*]}" == *"master"* ]]; then
            echo -e "${OVER}  ${TICK} $str"
            echo -e "  ${INFO} ${#webbranches[@]} branches available for Web Admin"
        else
            # Print STDERR output from get_available_branches
            echo -e "${OVER}  ${CROSS} $str\\n\\n${webbranches[*]}"
            exit 1
        fi

        echo ""
        # Have the user choose the branch they want
        if ! (for e in "${webbranches[@]}"; do [[ "$e" == "${2}" ]] && exit 0; done); then
            echo -e "  ${INFO} Requested branch \"${COL_CYAN}${2}${COL_NC}\" is not available"
            echo -e "  ${INFO} Available branches for Web Admin are:"
            for e in "${webbranches[@]}"; do echo "      - $e"; done
            exit 1
        fi
        checkout_pull_branch "${webInterfaceDir}" "${2}"
        # Update local and remote versions via updatechecker
        /opt/pihole/updatecheck.sh
    elif [[ "${1}" == "ftl" ]] ; then
        local path
        local oldbranch
        local existing=false
        path="${2}/${binary}"
        oldbranch="$(pihole-FTL -b)"

        # Check if requested branch is available
        echo -e "  ${INFO} Checking for availability of branch ${COL_CYAN}${2}${COL_NC} on GitHub"
        mapfile -t ftlbranches < <(git ls-remote https://github.com/pi-hole/ftl | grep "refs/heads" | cut -d'/' -f3- -)
        # If returned array is empty -> connectivity issue
        if [[ ${#ftlbranches[@]} -eq 0 ]]; then
            echo -e "  ${CROSS} Unable to fetch branches from GitHub. Please check your Internet connection and try again later."
            exit 1
        fi

        for e in "${ftlbranches[@]}"; do [[ "$e" == "${2}" ]] && existing=true; done
        if [[ "${existing}" == false ]]; then
            echo -e "  ${CROSS} Requested branch is not available\n"
            echo -e "  ${INFO} Available branches are:"
            for e in "${ftlbranches[@]}"; do echo "      - $e"; done
            exit 1
        fi
        echo -e "  ${TICK} Branch ${2} exists on GitHub"

        echo -e "  ${INFO} Checking for ${COL_YELLOW}${binary}${COL_NC} binary on https://ftl.pi-hole.net"

        if check_download_exists "$path"; then
            echo "  ${TICK} Binary exists"
            echo "${2}" > /etc/pihole/ftlbranch
            chmod 644 /etc/pihole/ftlbranch
            echo -e "  ${INFO} Switching to branch: ${COL_CYAN}${2}${COL_NC} from ${COL_CYAN}${oldbranch}${COL_NC}"
            FTLinstall "${binary}"
            restart_service pihole-FTL
            enable_service pihole-FTL
            str="Restarting FTL..."
            echo -ne "  ${INFO} ${str}"
            # Wait until name resolution is working again after restarting FTL,
            # so that the updatechecker can run successfully and does not fail
            # trying to resolve github.com
            until getent hosts github.com &> /dev/null; do
                # Append one dot for each second waiting
                str="${str}."
                echo -ne "  ${OVER}  ${INFO} ${str}"
                sleep 1
            done
            echo -e "  ${OVER}  ${TICK} Restarted FTL service"

            # Update local and remote versions via updatechecker
            /opt/pihole/updatecheck.sh
        else
            local status
            status=$?
            if [ $status -eq 1 ]; then
                # Binary for requested branch is not available, may still be
                # int he process of being built or CI build job failed
                printf "  %b Binary for requested branch is not available, please try again later.\\n" "${CROSS}"
                printf "      If the issue persists, please contact Pi-hole Support and ask them to re-generate the binary.\\n"
                exit 1
            elif [ $status -eq 2 ]; then
                printf "  %b Unable to download from ftl.pi-hole.net. Please check your Internet connection and try again later.\\n" "${CROSS}"
                exit 1
            else
                printf "  %b Unknown checkout error. Please contact Pi-hole Support\\n" "${CROSS}"
                exit 1
            fi
        fi

    else
        echo -e "  ${CROSS} Requested option \"${1}\" is not available"
        exit 1
    fi

    # Force updating everything
    if [[  ! "${1}" == "web" && ! "${1}" == "ftl" ]]; then
        echo -e "  ${INFO} Running installer to upgrade your installation"
        if "${PI_HOLE_FILES_DIR}/automated install/basic-install.sh" --unattended; then
            exit 0
        else
            echo -e "  ${COL_RED} Error: Unable to complete update, please contact support${COL_NC}"
            exit 1
        fi
    fi
}
