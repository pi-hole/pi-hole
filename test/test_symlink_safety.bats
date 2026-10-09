#!/usr/bin/env bats
# /etc/pihole is owned by the unprivileged "pihole" user, who can therefore
# replace anything in it with a symlink. Root must never act on a path in there
# in a way such a symlink could redirect (GHSA-xch2-4qxw-g5vj), and must not
# trust git repositories that user controls.
# These tests are deterministic: they plant the symlink/ownership up front
# instead of racing the scripts.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'bats_helper.bash'

PRESTART="/etc/.pihole/advanced/Templates/pihole-FTL-prestart.sh"

setup_file() {
    # Install required dependencies and create pihole user
    run bash -c "
        source /opt/pihole/basic-install.sh
        package_manager_detect
        update_package_cache
        build_dependency_package
        install_dependent_packages
        create_pihole_user
    "
    assert_success
}

teardown() {
    rm -rf /etc/pihole/probe
}

@test "prestart does not run its permission fix-up as root" {
    # find builds a list of paths and chmod acts on them afterwards, so if root
    # ran it, the pihole user could swap an entry for a symlink in between.
    # Stub out the ownership change at the top of the script so that the probe
    # stays root-owned: root would chmod it (0700 -> 0755, 0600 -> 0640), the
    # pihole user cannot.
    mkdir -p "${BATS_TEST_TMPDIR}/shim"
    printf '#!/bin/sh\nexit 0\n' > "${BATS_TEST_TMPDIR}/shim/chown"
    chmod +x "${BATS_TEST_TMPDIR}/shim/chown"

    mkdir -p /etc/pihole/probe
    printf 'x' > /etc/pihole/probe/file
    chmod 0700 /etc/pihole/probe
    chmod 0600 /etc/pihole/probe/file
    chown root:root /etc/pihole/probe /etc/pihole/probe/file

    run env PATH="${BATS_TEST_TMPDIR}/shim:${PATH}" sh "${PRESTART}"
    assert_success

    run stat -c '%a' /etc/pihole/probe
    assert_output "700"
    run stat -c '%a' /etc/pihole/probe/file
    assert_output "600"
}
