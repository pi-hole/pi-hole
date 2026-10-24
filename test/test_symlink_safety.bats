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

setup() {
    git config --system --unset-all safe.directory || true
}

teardown() {
    git config --system --unset-all safe.directory || true
    rm -rf /etc/pihole/probe
    rm -f /etc/pihole/versions /etc/pihole/dhcp.leases
}

# Create a git repository owned by root, readable by everyone
make_repo() {
    git init -q "${1}"
    chmod 0755 "${1}" "${1}/.git"
}

# Run the installer's mark_repos_safe for the given Core and Web repository paths
run_mark_repos_safe() {
    run bash -c "
        source /opt/pihole/basic-install.sh
        PI_HOLE_LOCAL_REPO='${1}'
        webInterfaceDir='${2}'
        mark_repos_safe
    "
    assert_success
}

# One safe.directory entry per line
trusted_dirs() {
    git config --system --get-all safe.directory || true
}

@test "mark_repos_safe trusts the root-owned Core and Web repositories" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/web"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web"

    run trusted_dirs
    assert_line "${BATS_TEST_TMPDIR}/core"
    assert_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe trusts the resolved path, not the symlink pointing at it" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/real-web"
    ln -s "${BATS_TEST_TMPDIR}/real-web" "${BATS_TEST_TMPDIR}/web-link"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web-link"

    run trusted_dirs
    assert_line "${BATS_TEST_TMPDIR}/real-web"
    refute_line "${BATS_TEST_TMPDIR}/web-link"
}

@test "mark_repos_safe does not trust a repository owned by the pihole user" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/web"
    chown -R pihole "${BATS_TEST_TMPDIR}/web"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web"

    run trusted_dirs
    assert_line "${BATS_TEST_TMPDIR}/core"
    refute_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe does not trust a root-owned directory with a pihole-owned .git" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/web"
    chown -R pihole "${BATS_TEST_TMPDIR}/web/.git"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web"

    run trusted_dirs
    refute_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe does not trust a world-writable directory" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/web"
    chmod 0777 "${BATS_TEST_TMPDIR}/web"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web"

    run trusted_dirs
    refute_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe leaves the system git config readable for the pihole user under a restrictive umask" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    rm -f /etc/gitconfig

    run bash -c "
        umask 0027
        source /opt/pihole/basic-install.sh
        PI_HOLE_LOCAL_REPO='${BATS_TEST_TMPDIR}/core'
        webInterfaceDir=''
        mark_repos_safe
    "
    assert_success

    # git ignores a system config its user cannot read, so ask as that user
    run su -s /bin/sh pihole -c "git config --system --get-all safe.directory"
    assert_output "${BATS_TEST_TMPDIR}/core"
}

@test "mark_repos_safe ignores missing and empty paths and adds nothing twice" {
    make_repo "${BATS_TEST_TMPDIR}/core"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/does-not-exist"
    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" ""

    run trusted_dirs
    assert_output "${BATS_TEST_TMPDIR}/core"
}

@test "prestart does not follow symlinks at the version and DHCP lease file paths" {
    # Root-only files the pihole user must not be able to influence
    printf 'secret' > "${BATS_TEST_TMPDIR}/secret-a"
    printf 'secret' > "${BATS_TEST_TMPDIR}/secret-b"
    chmod 0600 "${BATS_TEST_TMPDIR}/secret-a" "${BATS_TEST_TMPDIR}/secret-b"
    chown root:root "${BATS_TEST_TMPDIR}/secret-a" "${BATS_TEST_TMPDIR}/secret-b"

    ln -sf "${BATS_TEST_TMPDIR}/secret-a" /etc/pihole/versions
    ln -sf "${BATS_TEST_TMPDIR}/secret-b" /etc/pihole/dhcp.leases

    run sh "${PRESTART}"
    assert_success

    for f in secret-a secret-b; do
        run stat -c '%a %U' "${BATS_TEST_TMPDIR}/${f}"
        assert_output "600 root"
    done
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

@test "prestart drops privileges without opening a PAM session" {
    # su's logind session waits for remote-fs.target at boot, setpriv opens none
    setpriv --reuid=pihole --regid=pihole --init-groups true 2>/dev/null || skip "setpriv cannot change the user here"
    mkdir -p "${BATS_TEST_TMPDIR}/shim"
    printf '#!/bin/sh\ntouch %s/su-called\nexit 1\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/shim/su"
    chmod +x "${BATS_TEST_TMPDIR}/shim/su"
    rm -f /etc/pihole/versions

    run env PATH="${BATS_TEST_TMPDIR}/shim:${PATH}" sh "${PRESTART}"
    assert_success

    assert [ ! -e "${BATS_TEST_TMPDIR}/su-called" ]
    run stat -c '%a %U' /etc/pihole/versions
    assert_output "644 pihole"
}
