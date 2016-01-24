#!/usr/bin/env bash
#
# this script will update the pihole web interface files.
#
# if this is the first time running this script after an 
# existing installation, the existing web interface files
# will be removed and replaced with the latest master
# branch from github. subsequent executions of this script
# will pull the latest version of the web interface.
#
# @TODO: add git as requirement to basic-install.sh
#

WEB_INTERFACE_GIT_URL="https://github.com/pi-hole/AdminLTE.git"
WEB_INTERFACE_DIR="/var/www/html/admin"

main() {
    prerequisites
    if ! is_repo; then
        make_repo
    fi
    update_repo
}

prerequisites() {

    # must be root to update
    if [[ $EUID -ne 0 ]]; then
        sudo bash "$0" "$@"
        exit $?
    fi

    # web interface must already exist. this is a (lazy)
    # check to make sure pihole is actually installed.
    if [ ! -d "$WEB_INTERFACE_DIR" ]; then
        echo "$WEB_INTERFACE_DIR not found. Exiting."
        exit 1
    fi

    if ! type "git" > /dev/null; then
        apt-get -y install git
    fi
}

is_repo() {
    # if the web interface directory does not have a .git folder
    # it means its using the master.zip archive from the install
    # script.
    if [ ! -d "$WEB_INTERFACE_DIR/.git" ]; then
        return 1
    fi
    return 0
}

# removes the web interface installed from the master.zip archive and
# replaces it with the current master branch from github
make_repo() {
    # remove the non-repod interface and clone the interface
    rm -rf $WEB_INTERFACE_DIR
    git clone "$WEB_INTERFACE_GIT_URL" "$WEB_INTERFACE_DIR"
}

# pulls the latest master branch from github
update_repo() {
    # pull the latest commits
    cd "$WEB_INTERFACE_DIR"
    git pull    
}

main
