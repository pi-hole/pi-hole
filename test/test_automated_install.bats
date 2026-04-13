#!/usr/bin/env bats
# Core installer tests — package manager, cache, fresh install, dependencies

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'helpers/mocks'

TICK="[✓]"
CROSS="[✗]"
INFO="[i]"
FTL_BRANCH="development"

setup() {
    rm -f /usr/local/bin/dialog /usr/local/bin/git /usr/local/bin/systemctl /usr/local/bin/rc-service /usr/local/bin/apt-get
    rm -f /var/log/dialog /var/log/git /var/log/systemctl /var/log/rc-service /var/log/apt-get

    # Restore any package managers disabled by tests.
    [[ -e /usr/bin/apt-get.disabled ]] && mv -f /usr/bin/apt-get.disabled /usr/bin/apt-get || true
    [[ -e /usr/bin/rpm.disabled ]] && mv -f /usr/bin/rpm.disabled /usr/bin/rpm || true
    [[ -e /sbin/apk.disabled ]] && mv -f /sbin/apk.disabled /sbin/apk || true
}

teardown() {
    rm -f /usr/local/bin/dialog /usr/local/bin/git /usr/local/bin/systemctl /usr/local/bin/rc-service /usr/local/bin/apt-get
    rm -f /var/log/dialog /var/log/git /var/log/systemctl /var/log/rc-service /var/log/apt-get

    [[ -e /usr/bin/apt-get.disabled ]] && mv -f /usr/bin/apt-get.disabled /usr/bin/apt-get || true
    [[ -e /usr/bin/rpm.disabled ]] && mv -f /usr/bin/rpm.disabled /usr/bin/rpm || true
    [[ -e /sbin/apk.disabled ]] && mv -f /sbin/apk.disabled /sbin/apk || true
}

@test "installer exits when no supported package manager found" {
    [[ -e /usr/bin/apt-get ]] && mv /usr/bin/apt-get /usr/bin/apt-get.disabled
    [[ -e /usr/bin/rpm ]] && mv /usr/bin/rpm /usr/bin/rpm.disabled
    [[ -e /sbin/apk ]] && mv /sbin/apk /sbin/apk.disabled

    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
    "

    assert_output --partial "${CROSS} No supported package manager found"
    assert_failure
}

@test "installer continues when SELinux config file does not exist" {
    run bash -c "
        rm -f /etc/selinux/config
        source /opt/pihole/basic-install.sh
        checkSelinux
    "
    assert_output --partial "${INFO} SELinux not detected"
    assert_success
}

@test "fresh install: all necessary files are readable by pihole user" {
    mock_command dialog "*" "" "0"
    mock_command_passthrough git "pull" "" "0"
    mock_command_2 systemctl \
        "enable pihole-FTL"  "" "0" \
        "restart pihole-FTL" "" "0" \
        "start pihole-FTL"   "" "0"
    mock_command_2 rc-service \
        "pihole-FTL enable"  "" "0" \
        "pihole-FTL restart" "" "0" \
        "pihole-FTL start"   "" "0"

    command -v apt-get > /dev/null && apt-get install -qq man || true
    command -v dnf > /dev/null && dnf install -y man || true
    command -v yum > /dev/null && yum install -y man || true
    command -v apk > /dev/null && apk add mandoc man-pages || true

    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch

    run bash -c "
        export TERM=xterm
        export DEBIAN_FRONTEND=noninteractive
        umask 0027
        runUnattended=true
        source /opt/pihole/basic-install.sh > /dev/null
        runUnattended=true
        main
        /opt/pihole/pihole-FTL-prestart.sh
    "
    assert_success

    local maninstalled=true
    if [[ "$output" == *"${INFO} man not installed"* ]] || [[ "$output" == *"${INFO} man pages not installed"* ]]; then
        maninstalled=false
    fi

    local piholeuser="pihole"
    _check_perm() { su -s /bin/bash -c "test -${1} ${2}" -p ${piholeuser}; }

    run _check_perm r /etc/pihole; assert_success
    run _check_perm x /etc/pihole; assert_success
    run _check_perm r /etc/pihole/dhcp.leases; assert_success
    run _check_perm r /etc/pihole/install.log; assert_success
    run _check_perm r /etc/pihole/versions; assert_success
    run _check_perm r /etc/pihole/macvendor.db; assert_success
    run _check_perm x /etc/init.d/pihole-FTL; assert_success
    run _check_perm r /etc/init.d/pihole-FTL; assert_success

    if [[ "$maninstalled" == "true" ]]; then
        run _check_perm x /usr/local/share/man; assert_success
        run _check_perm r /usr/local/share/man; assert_success
        run _check_perm x /usr/local/share/man/man8; assert_success
        run _check_perm r /usr/local/share/man/man8; assert_success
        run _check_perm r /usr/local/share/man/man8/pihole.8; assert_success
    fi

    run _check_perm x /etc/cron.d/; assert_success
    run _check_perm r /etc/cron.d/; assert_success
    run _check_perm r /etc/cron.d/pihole; assert_success

    local dirs
    dirs=$(find /etc/.pihole/ -type d -not -path '*/.*' 2>/dev/null || true)
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        run _check_perm r "$dir"; assert_success
        run _check_perm x "$dir"; assert_success
        local files
        files=$(find "$dir" -maxdepth 1 -type f -exec echo {} \; 2>/dev/null || true)
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            run _check_perm r "$file"; assert_success
        done <<< "$files"
    done <<< "$dirs"
}

@test "package cache update succeeds without errors" {
    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
    "
    assert_output --partial "${TICK} Update local cache of available packages"
    refute_output --partial "error"
}

@test "package cache update reports failure correctly" {
    mock_command apt-get "update" "" "1"

    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
    "
    assert_output --partial "${CROSS} Update local cache of available packages"
    assert_output --partial "Error: Unable to update package cache."
}

@test "OS can install required Pi-hole dependency packages" {
    mock_command dialog "*" "" "0"

    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
        build_dependency_package
        install_dependent_packages
    "
    refute_output --partial "No package"
    assert_success
}

@test "OS can install and uninstall the Pi-hole meta package" {
    mock_command dialog "*" "" "0"

    run bash -c "
        export DEBIAN_FRONTEND=noninteractive
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
        build_dependency_package
        install_dependent_packages
    "
    assert_success

    run bash -c "
        export DEBIAN_FRONTEND=noninteractive
        source /opt/pihole/basic-install.sh
        package_manager_detect
        eval \"\${PKG_REMOVE}\" pihole-meta
    "
    assert_success
}
