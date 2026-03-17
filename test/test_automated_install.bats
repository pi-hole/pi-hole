#!/usr/bin/env bats
# Tests for basic-install.sh — translated from test_any_automated_install.py

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

# ---------------------------------------------------------------------------
# FTL architecture detection — one @test per arch (replaces parametrize)
# ---------------------------------------------------------------------------

_test_ftl_arch() {
    local arch="$1" detected_string="$2" supported="$3"

    mock_command "$CID" uname "-m" "$arch" "0"
    mock_command_2 "$CID" readelf \
        "-A /bin/sh"     "Tag_CPU_arch: ${arch}" "0" \
        "-A /usr/bin/sh" "Tag_CPU_arch: ${arch}" "0" \
        "-A /usr/sbin/sh" "Tag_CPU_arch: ${arch}" "0"
    docker exec "$CID" bash -c "echo '${FTL_BRANCH}' > /etc/pihole/ftlbranch"

    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "

    if [[ "$supported" == "true" ]]; then
        assert_output --partial "${INFO} FTL Checks..."
        assert_output --partial "${TICK} Detected ${detected_string} architecture"
        assert_output --partial "${TICK} Downloading and Installing FTL"
    else
        assert_output --partial "Not able to detect architecture (unknown: ${detected_string})"
    fi
}

@test "FTL detects aarch64 architecture" {
    _test_ftl_arch "aarch64" "AArch64 (64 Bit ARM)" "true"
}

@test "FTL detects ARMv6 architecture" {
    _test_ftl_arch "armv6" "ARMv6" "true"
}

@test "FTL detects ARMv7l architecture" {
    _test_ftl_arch "armv7l" "ARMv7 (or newer)" "true"
}

@test "FTL detects ARMv7 architecture" {
    _test_ftl_arch "armv7" "ARMv7 (or newer)" "true"
}

@test "FTL detects ARMv8a architecture" {
    _test_ftl_arch "armv8a" "ARMv7 (or newer)" "true"
}

@test "FTL detects x86_64 architecture" {
    _test_ftl_arch "x86_64" "x86_64" "true"
}

@test "FTL detects riscv64 architecture" {
    _test_ftl_arch "riscv64" "riscv64" "true"
}

@test "FTL reports unsupported architecture" {
    _test_ftl_arch "mips" "mips" "false"
}

@test "FTL development binary is installed and responsive" {
    docker exec "$CID" bash -c "echo '${FTL_BRANCH}' > /etc/pihole/ftlbranch"
    docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        create_pihole_user
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "
    run docker exec "$CID" bash -c '
        VERSION=$(pihole-FTL version)
        echo "${VERSION:0:1}"
    '
    assert_output --partial "v"
}

# ---------------------------------------------------------------------------
# IPv6 detection
# ---------------------------------------------------------------------------

@test "IPv6 link-local only: blocking disabled" {
    mock_command_2 "$CID" ip \
        "-6 address" "inet6 fe80::d210:52fa:fe00:7ad7/64 scope link" "0"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        find_IPv6_information
    "
    assert_output --partial "Unable to find IPv6 ULA/GUA address"
}

@test "IPv6 ULA only: blocking enabled" {
    mock_command_2 "$CID" ip \
        "-6 address" "inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global" "0"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        find_IPv6_information
    "
    assert_output --partial "Found IPv6 ULA address"
}

@test "IPv6 GUA only: blocking enabled" {
    mock_command_2 "$CID" ip \
        "-6 address" "inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global" "0"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        find_IPv6_information
    "
    assert_output --partial "Found IPv6 GUA address"
}

@test "IPv6 GUA + ULA: ULA takes precedence" {
    mock_command_2 "$CID" ip \
        "-6 address" "inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global
inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global" "0"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        find_IPv6_information
    "
    assert_output --partial "Found IPv6 ULA address"
}

@test "IPv6 ULA + GUA: ULA takes precedence" {
    mock_command_2 "$CID" ip \
        "-6 address" "inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global
inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global" "0"
    run docker exec "$CID" bash -c "
        source /opt/pihole/basic-install.sh
        find_IPv6_information
    "
    assert_output --partial "Found IPv6 ULA address"
}

# ---------------------------------------------------------------------------
# IP address validation
# ---------------------------------------------------------------------------

@test "valid_ip accepts and rejects addresses correctly" {
    _valid() {
        run docker exec "$CID" bash -c "source /opt/pihole/basic-install.sh; valid_ip '${1}'"
        assert_success
    }
    _invalid() {
        run docker exec "$CID" bash -c "source /opt/pihole/basic-install.sh; valid_ip '${1}'"
        assert_failure
    }

    _valid  "192.168.1.1"
    _valid  "127.0.0.1"
    _valid  "255.255.255.255"
    _invalid "255.255.255.256"
    _invalid "255.255.256.255"
    _invalid "255.256.255.255"
    _invalid "256.255.255.255"
    _invalid "1092.168.1.1"
    _invalid "not an IP"
    _invalid "8.8.8.8#"
    _valid  "8.8.8.8#0"
    _valid  "8.8.8.8#1"
    _valid  "8.8.8.8#42"
    _valid  "8.8.8.8#888"
    _valid  "8.8.8.8#1337"
    _valid  "8.8.8.8#65535"
    _invalid "8.8.8.8#65536"
    _invalid "8.8.8.8#-1"
    _invalid "00.0.0.0"
    _invalid "010.0.0.0"
    _invalid "001.0.0.0"
    _invalid "0.0.0.0#00"
    _invalid "0.0.0.0#01"
    _invalid "0.0.0.0#001"
    _invalid "0.0.0.0#0001"
    _invalid "0.0.0.0#00001"
}

# ---------------------------------------------------------------------------
# Package dependency installation
# ---------------------------------------------------------------------------

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
