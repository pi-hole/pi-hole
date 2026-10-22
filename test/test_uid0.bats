#!/usr/bin/env bats
# docker-pi-hole can run with PIHOLE_UID=0, which makes the "pihole" user an
# alias for root. Scripts that hand over to the pihole user when started as root
# must then carry on as they are: su/sudo cannot drop anything, so re-running
# the script would hit the same branch again and recurse until the host runs
# out of memory.
# These tests fake a UID 0 pihole user with an `id` shim and put recording
# stubs in front of su/sudo, so a script that still tries to hand over is
# caught immediately instead of looping.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'bats_helper.bash'

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

setup() {
    SHIM="${BATS_TEST_TMPDIR}/shim"
    HANDOVER_LOG="${BATS_TEST_TMPDIR}/handover.log"
    REAL_ID="$(command -v id)"
    mkdir -p "${SHIM}"

    # Report the pihole user as UID 0, leave everything else alone
    cat > "${SHIM}/id" <<EOF
#!/bin/sh
if [ "\$1" = "-u" ] && [ "\$2" = "pihole" ]; then
    echo 0
else
    exec "${REAL_ID}" "\$@"
fi
EOF

    # Record any attempt to hand over to the pihole user, and do nothing
    for cmd in su sudo; do
        cat > "${SHIM}/${cmd}" <<EOF
#!/bin/sh
echo "${cmd} \$*" >> "${HANDOVER_LOG}"
exit 0
EOF
    done
    chmod +x "${SHIM}"/*
}

teardown() {
    rm -f /etc/pihole/versions
}

@test "the id shim reports pihole as UID 0 and everyone else unchanged" {
    run env PATH="${SHIM}:${PATH}" id -u pihole
    assert_output "0"

    run env PATH="${SHIM}:${PATH}" id -u
    assert_output "0"

    run env PATH="${SHIM}:${PATH}" id -un
    assert_output "root"
}

@test "gravity.sh does not hand over to itself when the pihole user is UID 0" {
    run timeout 60 env PATH="${SHIM}:${PATH}" bash /opt/pihole/gravity.sh --help
    assert_success
    assert_output --partial "Show this help dialog"
    assert_not_exist "${HANDOVER_LOG}"
}

@test "updatecheck.sh does not hand over to itself when the pihole user is UID 0" {
    # What it does after the guard does not matter here, only that it got there
    run timeout 120 env PATH="${SHIM}:${PATH}" bash /opt/pihole/updatecheck.sh
    assert_not_exist "${HANDOVER_LOG}"
}

@test "updatecheck.sh still hands over to the pihole user when it is not UID 0" {
    # Without the id shim, the pihole user has its own UID
    run env PATH="${SHIM}:${PATH}" bash -c 'rm "${0}/id"; exec bash /opt/pihole/updatecheck.sh' "${SHIM}"
    assert_success
    run cat "${HANDOVER_LOG}"
    assert_line --regexp "^su -s /bin/sh pihole -c /opt/pihole/updatecheck.sh"
}

@test "gravity.sh still hands over to the pihole user when it is not UID 0" {
    run env PATH="${SHIM}:${PATH}" bash -c 'rm "${0}/id"; exec bash /opt/pihole/gravity.sh --help' "${SHIM}"
    assert_success
    run cat "${HANDOVER_LOG}"
    assert_line --regexp "^sudo -u pihole bash /opt/pihole/gravity.sh --help"
}
