#!/usr/bin/env bats
# Core installer tests — package manager, cache, dependencies

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-mock/stub'
load 'bats_helper.bash'

TICK="[✓]"
CROSS="[✗]"
INFO="[i]"



@test "installer exits when no supported package manager found" {
    [[ -e /usr/bin/apt-get ]] && mv /usr/bin/apt-get /usr/bin/apt-get.disabled
    [[ -e /usr/bin/rpm ]]     && mv /usr/bin/rpm /usr/bin/rpm.disabled
    [[ -e /sbin/apk ]]        && mv /sbin/apk /sbin/apk.disabled

    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
    "

    assert_output --partial "${CROSS} No supported package manager found"
    assert_failure

    # Restore package managers for other tests
    [[ -e /usr/bin/apt-get.disabled ]] && mv -f /usr/bin/apt-get.disabled /usr/bin/apt-get || true
    [[ -e /usr/bin/rpm.disabled ]]     && mv -f /usr/bin/rpm.disabled /usr/bin/rpm         || true
    [[ -e /sbin/apk.disabled ]]        && mv -f /sbin/apk.disabled /sbin/apk               || true
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
    stub apt-get "update : return 1"

    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
    "
    assert_output --partial "${CROSS} Update local cache of available packages"
    assert_output --partial "Error: Unable to update package cache."

    unstub apt-get 2>/dev/null || true
}

@test "OS can install required Pi-hole dependency packages" {
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

@test "installLogrotate replaces the raw PID kill in an existing logrotate file" {
    mkdir -p /etc/logrotate.d
    printf '%s\n' '/var/log/pihole/pihole.log {' '    postrotate' \
        '        kill -USR2 $(cat /run/pihole-FTL.pid 2>/dev/null) 2>/dev/null || true' \
        '    endscript' '}' > /etc/logrotate.d/pihole

    run bash -c "
        source /opt/pihole/basic-install.sh
        installLogrotate
    "
    assert_success
    run grep -F 'getFTLPID' /etc/logrotate.d/pihole
    assert_output "$(grep -F -m1 'getFTLPID' /etc/.pihole/advanced/Templates/logrotate)"
    run grep -F 'kill -USR2 $(cat' /etc/logrotate.d/pihole
    assert_failure

    rm -f /etc/logrotate.d/pihole
}

@test "installLogrotate replaces an unmodified v6.4.3 logrotate file with the current template" {
    mkdir -p /etc/logrotate.d
    awk '/^    cat > "\$\{rendered_643\}" << .EOF.$/ {f=1; next} /^EOF$/ {f=0} f' /opt/pihole/basic-install.sh |
        sed "s/# su #/su $(stat -c '%U %G' /var/log)/" > /etc/logrotate.d/pihole
    run grep -c -F 'kill -USR2 $(cat' /etc/logrotate.d/pihole
    assert_output "1"

    run bash -c "
        source /opt/pihole/basic-install.sh
        installLogrotate
    "
    assert_success
    assert_output --partial "Upgraded the unmodified v6.4.3 logrotate file"
    run grep -c -F 'getFTLPID' /etc/logrotate.d/pihole
    assert_output "2"
    run grep -F 'kill -USR2 $(cat' /etc/logrotate.d/pihole
    assert_failure

    rm -f /etc/logrotate.d/pihole
}
