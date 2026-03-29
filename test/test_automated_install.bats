#!/usr/bin/env bats
# Core installer tests — package manager, cache, fresh install, dependencies

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'helpers/mocks'

TICK="[✓]"
CROSS="[✗]"
INFO="[i]"

FTL_BRANCH="development"

CID=""

setup() {
    CID=$(docker run -d -t --cap-add=ALL "$IMAGE_TAG")
}

teardown() {
    if [[ -n "$CID" ]]; then
        docker rm -f "$CID" > /dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------

@test "installer exits when no supported package manager found" {
    docker exec "$CID" bash -c "rm -rf /usr/bin/apt-get /usr/bin/rpm /sbin/apk"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
    "
    assert_output --partial "${CROSS} No supported package manager found"
    assert_failure
}

@test "installer continues when SELinux config file does not exist" {
    run docker exec "$CID" bash -c "
        rm -f /etc/selinux/config
        source /opt/pihole/basic-install.sh
        checkSelinux
    "
    assert_output --partial "${INFO} SELinux not detected"
    assert_success
}

@test "fresh install: all necessary files are readable by pihole user" {
    mock_command "$CID" dialog "*" "" "0"
    mock_command_passthrough "$CID" git "pull" "" "0"
    mock_command_2 "$CID" systemctl \
        "enable pihole-FTL"  "" "0" \
        "restart pihole-FTL" "" "0" \
        "start pihole-FTL"   "" "0"
    mock_command_2 "$CID" rc-service \
        "pihole-FTL enable"  "" "0" \
        "pihole-FTL restart" "" "0" \
        "pihole-FTL start"   "" "0"

    # Install man pages if available (best-effort)
    docker exec "$CID" bash -c "command -v apt-get > /dev/null && apt-get install -qq man" || true
    docker exec "$CID" bash -c "command -v dnf > /dev/null && dnf install -y man" || true
    docker exec "$CID" bash -c "command -v yum > /dev/null && yum install -y man" || true
    docker exec "$CID" bash -c "command -v apk > /dev/null && apk add mandoc man-pages" || true

    docker exec "$CID" bash -c "echo '${FTL_BRANCH}' > /etc/pihole/ftlbranch"

    run docker exec "$CID" bash -c "
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

    # Detect whether man was installed
    local maninstalled=true
    if [[ "$output" == *"${INFO} man not installed"* ]] || [[ "$output" == *"${INFO} man pages not installed"* ]]; then
        maninstalled=false
    fi

    local piholeuser="pihole"
    _check_perm() { docker exec "$CID" bash -c "su -s /bin/bash -c 'test -${1} ${2}' -p ${piholeuser}"; }

    # /etc/pihole
    run _check_perm r /etc/pihole; assert_success
    run _check_perm x /etc/pihole; assert_success

    # /etc/pihole/dhcp.leases
    run _check_perm r /etc/pihole/dhcp.leases; assert_success

    # /etc/pihole/install.log
    run _check_perm r /etc/pihole/install.log; assert_success

    # /etc/pihole/versions
    run _check_perm r /etc/pihole/versions; assert_success

    # /etc/pihole/macvendor.db
    run _check_perm r /etc/pihole/macvendor.db; assert_success

    # /etc/init.d/pihole-FTL
    run _check_perm x /etc/init.d/pihole-FTL; assert_success
    run _check_perm r /etc/init.d/pihole-FTL; assert_success

    # man pages (if installed)
    if [[ "$maninstalled" == "true" ]]; then
        run _check_perm x /usr/local/share/man;      assert_success
        run _check_perm r /usr/local/share/man;      assert_success
        run _check_perm x /usr/local/share/man/man8; assert_success
        run _check_perm r /usr/local/share/man/man8; assert_success
        run _check_perm r /usr/local/share/man/man8/pihole.8; assert_success
    fi

    # /etc/cron.d
    run _check_perm x /etc/cron.d/;      assert_success
    run _check_perm r /etc/cron.d/;      assert_success
    run _check_perm r /etc/cron.d/pihole; assert_success

    # All files and directories under /etc/.pihole/
    local dirs
    dirs=$(docker exec "$CID" bash -c "find /etc/.pihole/ -type d -not -path '*/.*'" 2>/dev/null || true)
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        run _check_perm r "$dir"; assert_success
        run _check_perm x "$dir"; assert_success
        local files
        files=$(docker exec "$CID" bash -c "find '${dir}' -maxdepth 1 -type f -exec echo {} \\;" 2>/dev/null || true)
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            run _check_perm r "$file"; assert_success
        done <<< "$files"
    done <<< "$dirs"
}

@test "package cache update succeeds without errors" {
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
    "
    assert_output --partial "${TICK} Update local cache of available packages"
    refute_output --partial "error"
}

@test "package cache update reports failure correctly" {
    mock_command "$CID" apt-get "update" "" "1"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
    "
    assert_output --partial "${CROSS} Update local cache of available packages"
    assert_output --partial "Error: Unable to update package cache."
}

@test "OS can install required Pi-hole dependency packages" {
    mock_command "$CID" dialog "*" "" "0"
    run docker exec "$CID" bash -c "
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
    mock_command "$CID" dialog "*" "" "0"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
        build_dependency_package
        install_dependent_packages
    "
    assert_success

    run docker exec "$CID" bash -c "
        source /opt/pihole/uninstall.sh
        removeMetaPackage
    "
    assert_success
}
