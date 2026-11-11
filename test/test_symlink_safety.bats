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
    rm -rf /etc/pihole/probe /etc/pihole/migration_backup_v6 /etc/pihole/hosts
    rm -f /etc/pihole/versions /etc/pihole/dhcp.leases /etc/pihole/install.log
    rm -f /etc/dnsmasq.d/01-pihole.conf /etc/dnsmasq.d/06-rfc6761.conf
}

# A root-owned directory the pihole user must not be able to write into
make_root_dir() {
    mkdir -p "${1}"
    chmod 0755 "${1}"
    chown root:root "${1}"
}

# Plant the v5 dnsmasq configs that move_old_dnsmasq_ftl_configs migrates
make_v5_dnsmasq_configs() {
    mkdir -p /etc/dnsmasq.d
    printf 'v5\n' > /etc/dnsmasq.d/01-pihole.conf
    printf 'v5\n' > /etc/dnsmasq.d/06-rfc6761.conf
    chmod 0644 /etc/dnsmasq.d/01-pihole.conf /etc/dnsmasq.d/06-rfc6761.conf
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
    refute_output --partial "is not owned by root or is world-writable"

    run trusted_dirs
    assert_line "${BATS_TEST_TMPDIR}/core"
    assert_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe trusts the resolved path, not the symlink pointing at it" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/real-web"
    ln -sf "${BATS_TEST_TMPDIR}/real-web" "${BATS_TEST_TMPDIR}/web-link"

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
    assert_output --partial "${BATS_TEST_TMPDIR}/web is not owned by root or is world-writable"

    run trusted_dirs
    assert_line "${BATS_TEST_TMPDIR}/core"
    refute_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe does not trust a root-owned directory with a pihole-owned .git" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/web"
    chown -R pihole "${BATS_TEST_TMPDIR}/web/.git"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web"
    assert_output --partial "${BATS_TEST_TMPDIR}/web is not owned by root or is world-writable"

    run trusted_dirs
    refute_line "${BATS_TEST_TMPDIR}/web"
}

@test "mark_repos_safe does not trust a world-writable directory" {
    make_repo "${BATS_TEST_TMPDIR}/core"
    make_repo "${BATS_TEST_TMPDIR}/web"
    chmod 0777 "${BATS_TEST_TMPDIR}/web"

    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" "${BATS_TEST_TMPDIR}/web"
    assert_output --partial "${BATS_TEST_TMPDIR}/web is not owned by root or is world-writable"

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
    refute_output --partial "is not owned by root or is world-writable"
    run_mark_repos_safe "${BATS_TEST_TMPDIR}/core" ""
    refute_output --partial "is not owned by root or is world-writable"

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

# A root-owned file the pihole user can reach but not change or delete
setup_root_secret() {
    mkdir -p /etc/pihole /opt/pihole-test-root
    chown pihole:pihole /etc/pihole
    chmod 0755 /opt/pihole-test-root
    printf 'root:CANARY-SECRET:0:0\n' > /opt/pihole-test-root/secret
    chmod 0644 /opt/pihole-test-root/secret
    chown root:root /opt/pihole-test-root /opt/pihole-test-root/secret
}

# piholeCheckout.sh (pihole checkout) runs as root and writes
# /etc/pihole/ftlbranch (GHSA-5w4v-f65m-323f)
checkout_fn() {
    run bash -c "
        source /opt/pihole/piholeCheckout.sh
        ${1}
    "
}

@test "piholeCheckout.sh does not follow a symlink at the ftlbranch path" {
    setup_root_secret
    ln -sf /opt/pihole-test-root/secret /etc/pihole/ftlbranch
    chown -h pihole:pihole /etc/pihole/ftlbranch

    checkout_fn 'set_ftl_branch development'
    assert_success

    run cat /opt/pihole-test-root/secret
    assert_output "root:CANARY-SECRET:0:0"
    run stat -c '%F %a %U:%G' /etc/pihole/ftlbranch
    assert_output "regular file 644 pihole:pihole"
    run cat /etc/pihole/ftlbranch
    assert_output "development"

    rm -rf /opt/pihole-test-root /etc/pihole/ftlbranch
}

@test "piholeCheckout.sh replaces a root-owned ftlbranch left by an older version" {
    mkdir -p /etc/pihole
    chown pihole:pihole /etc/pihole
    printf 'master\n' > /etc/pihole/ftlbranch
    chown root:root /etc/pihole/ftlbranch
    chmod 0644 /etc/pihole/ftlbranch

    checkout_fn 'set_ftl_branch new/feature'
    assert_success

    run cat /etc/pihole/ftlbranch
    assert_output "new/feature"

    rm -f /etc/pihole/ftlbranch
}

# uninstall.sh runs as root and deletes paths taken from pihole.toml
# (GHSA-5w4v-f65m-323f). Its functions are tested directly: the script is sourced
# without its confirmation prompt, its config reads and its list of steps.
uninstall_fn() {
    sed -n '/^removeMetaPackage() {$/,/^######### SCRIPT/p' /opt/pihole/uninstall.sh > "${BATS_TEST_TMPDIR}/uninstall-functions.sh"
    run bash -c "
        source /opt/pihole/COL_TABLE
        SKIP_INSTALL=true
        source /opt/pihole/basic-install.sh
        source '${BATS_TEST_TMPDIR}/uninstall-functions.sh'
        ${1}
    "
}

@test "uninstall.sh removes the web interface checkout" {
    make_repo "${BATS_TEST_TMPDIR}/admin"
    git -C "${BATS_TEST_TMPDIR}/admin" remote add origin https://github.com/pi-hole/web.git

    uninstall_fn "ADMIN_INTERFACE_DIR='${BATS_TEST_TMPDIR}/admin/'; removeWebInterface"
    assert_success
    assert_not_exists "${BATS_TEST_TMPDIR}/admin"
}

@test "uninstall.sh does not remove a configured web interface path that is not the web interface" {
    # Another root-owned repository (e.g. /etc under etckeeper), a subdirectory
    # of one, a plain directory, and a symlink to the real web interface
    make_repo "${BATS_TEST_TMPDIR}/other"
    git -C "${BATS_TEST_TMPDIR}/other" remote add origin https://example.com/etc.git
    make_repo "${BATS_TEST_TMPDIR}/admin"
    git -C "${BATS_TEST_TMPDIR}/admin" remote add origin https://github.com/pi-hole/web.git
    mkdir -p "${BATS_TEST_TMPDIR}/admin/sub" "${BATS_TEST_TMPDIR}/plain"
    ln -sf "${BATS_TEST_TMPDIR}/admin" "${BATS_TEST_TMPDIR}/link"

    for dir in other admin/sub plain link; do
        uninstall_fn "ADMIN_INTERFACE_DIR='${BATS_TEST_TMPDIR}/${dir}/'; removeWebInterface"
        assert_success
        assert_output --partial "Not removing"
        assert_exists "${BATS_TEST_TMPDIR}/${dir}"
    done
}

@test "uninstall.sh deletes the configured databases as the pihole user" {
    setup_root_secret
    printf 'db\n' > /etc/pihole/custom-gravity.db
    chown pihole:pihole /etc/pihole/custom-gravity.db

    # rm fails for the root-owned file, so the status is not checked
    uninstall_fn "PIHOLE_DB=/opt/pihole-test-root/secret; GRAVITY_DB=/etc/pihole/custom-gravity.db; MACVENDOR_DB=''; removeDatabases"

    # A pihole-owned database is removed, a root-owned file is not
    assert_not_exists /etc/pihole/custom-gravity.db
    run cat /opt/pihole-test-root/secret
    assert_output "root:CANARY-SECRET:0:0"

    rm -rf /opt/pihole-test-root
}

@test "move_old_dnsmasq_ftl_configs moves the v5 configs into a pihole-owned migration directory" {
    chown pihole:pihole /etc/pihole
    make_v5_dnsmasq_configs

    run bash -c "
        source /opt/pihole/basic-install.sh
        move_old_dnsmasq_ftl_configs
    "
    assert_success

    run stat -c '%U' /etc/pihole/migration_backup_v6
    assert_output "pihole"
    assert_file_exists /etc/pihole/migration_backup_v6/01-pihole.conf
    assert_file_exists /etc/pihole/migration_backup_v6/06-rfc6761.conf
    assert_file_not_exists /etc/dnsmasq.d/01-pihole.conf
    assert_file_not_exists /etc/dnsmasq.d/06-rfc6761.conf
}

@test "move_old_dnsmasq_ftl_configs does not follow a symlink at the migration directory" {
    chown pihole:pihole /etc/pihole
    make_v5_dnsmasq_configs
    make_root_dir "${BATS_TEST_TMPDIR}/target"
    ln -s "${BATS_TEST_TMPDIR}/target" /etc/pihole/migration_backup_v6

    run bash -c "
        source /opt/pihole/basic-install.sh
        move_old_dnsmasq_ftl_configs
    "

    run stat -c '%a %U' "${BATS_TEST_TMPDIR}/target"
    assert_output "755 root"
    run ls -A "${BATS_TEST_TMPDIR}/target"
    assert_output ""
    # Nothing was copied, so the originals must stay where they are
    assert_file_exists /etc/dnsmasq.d/01-pihole.conf
    assert_file_exists /etc/dnsmasq.d/06-rfc6761.conf
}

@test "installConfigs does not create custom.list through a symlink at hosts/" {
    make_root_dir "${BATS_TEST_TMPDIR}/target"
    ln -s "${BATS_TEST_TMPDIR}/target" /etc/pihole/hosts

    run bash -c "
        source /opt/pihole/basic-install.sh
        installConfigs
    "
    assert_output --partial "Unable to initialize configuration file"

    run ls -A "${BATS_TEST_TMPDIR}/target"
    assert_output ""
}

@test "copy_to_install_log does not follow a symlink at the install log path" {
    chown pihole:pihole /etc/pihole
    printf 'secret' > "${BATS_TEST_TMPDIR}/secret"
    chmod 0600 "${BATS_TEST_TMPDIR}/secret"
    chown root:root "${BATS_TEST_TMPDIR}/secret"
    ln -sf "${BATS_TEST_TMPDIR}/secret" /etc/pihole/install.log

    run bash -c "
        source /opt/pihole/basic-install.sh
        exec 3< <(printf 'installer output\n')
        copy_to_install_log
    "

    run stat -c '%a %U' "${BATS_TEST_TMPDIR}/secret"
    assert_output "600 root"
    run cat "${BATS_TEST_TMPDIR}/secret"
    assert_output "secret"
}

@test "copy_to_install_log writes a world-readable log owned by pihole" {
    chown pihole:pihole /etc/pihole
    rm -f /etc/pihole/install.log

    run bash -c "
        umask 0077
        source /opt/pihole/basic-install.sh
        exec 3< <(printf 'installer output\n')
        copy_to_install_log
    "
    assert_success

    run stat -c '%a %U' /etc/pihole/install.log
    assert_output "644 pihole"
    run cat /etc/pihole/install.log
    assert_output "installer output"
}
