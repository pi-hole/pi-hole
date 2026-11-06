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
    rm -f /etc/pihole/pihole.toml /var/log/pihole/FTL.log /var/log/pihole/pihole_debug.log
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

# piholeDebug.sh (pihole -d) runs as root and reads and writes files in
# /etc/pihole and /var/log/pihole (GHSA-jvg9-fm8x-2jqq). Its functions are
# tested directly: the script is sourced without the list of steps at its end,
# which needs a running pihole-FTL.
debug_fn() {
    sed '/^# Run through all the functions we made$/,$d' /opt/pihole/piholeDebug.sh > "${BATS_TEST_TMPDIR}/debug-functions.sh"
    run bash -c "
        source '${BATS_TEST_TMPDIR}/debug-functions.sh' 2>/dev/null
        make_temporary_log
        ${1}
    "
}

# Directory layout as left by pihole-FTL-prestart.sh, plus a root-only file
setup_debug_dirs() {
    mkdir -p /etc/pihole /var/log/pihole
    chown pihole:pihole /etc/pihole /var/log/pihole
    printf 'root:CANARY-SECRET:0:0\n' > "${BATS_TEST_TMPDIR}/secret"
    chmod 0600 "${BATS_TEST_TMPDIR}/secret"
    chown root:root "${BATS_TEST_TMPDIR}/secret"
}

@test "piholeDebug.sh shows the content of a regular log in /var/log/pihole" {
    setup_debug_dirs
    printf 'FTL started\n' > /var/log/pihole/FTL.log
    chown pihole:pihole /var/log/pihole/FTL.log
    chmod 0640 /var/log/pihole/FTL.log

    debug_fn 'head_tail_log /var/log/pihole/FTL.log 35'
    assert_success
    assert_output --partial "FTL started"
}

@test "piholeDebug.sh does not follow a symlink when reading a log in /var/log/pihole" {
    setup_debug_dirs
    ln -s "${BATS_TEST_TMPDIR}/secret" /var/log/pihole/FTL.log
    chown -h pihole:pihole /var/log/pihole/FTL.log

    debug_fn 'head_tail_log /var/log/pihole/FTL.log 35'
    refute_output --partial "CANARY-SECRET"
}

@test "piholeDebug.sh does not follow a symlink when reading a file in /etc/pihole" {
    setup_debug_dirs
    ln -s "${BATS_TEST_TMPDIR}/secret" /etc/pihole/pihole.toml
    chown -h pihole:pihole /etc/pihole/pihole.toml

    debug_fn 'make_array_from_file /etc/pihole/pihole.toml'
    refute_output --partial "CANARY-SECRET"
}

@test "piholeDebug.sh does not follow a symlink at the debug log path" {
    setup_debug_dirs
    ln -s "${BATS_TEST_TMPDIR}/secret" /var/log/pihole/pihole_debug.log
    chown -h pihole:pihole /var/log/pihole/pihole_debug.log

    debug_fn 'log_write "debug output"; copy_to_debug_log'
    assert_success

    # The target is untouched
    run cat "${BATS_TEST_TMPDIR}/secret"
    assert_output "root:CANARY-SECRET:0:0"
    run stat -c '%a %U:%G' "${BATS_TEST_TMPDIR}/secret"
    assert_output "600 root:root"

    # The symlink has been replaced by a new log readable by the pihole group
    run stat -c '%F %a %U:%G' /var/log/pihole/pihole_debug.log
    assert_output "regular file 640 pihole:pihole"
    run cat /var/log/pihole/pihole_debug.log
    assert_output --partial "debug output"
}

@test "piholeDebug.sh replaces a root-owned debug log left by an older version" {
    setup_debug_dirs
    printf 'old log\n' > /var/log/pihole/pihole_debug.log
    chown root:pihole /var/log/pihole/pihole_debug.log
    chmod 0640 /var/log/pihole/pihole_debug.log

    debug_fn 'log_write "new log"; copy_to_debug_log'
    assert_success

    run cat /var/log/pihole/pihole_debug.log
    assert_output --partial "new log"
    refute_output --partial "old log"
}

@test "piholeDebug.sh uploads the debug log as the pihole user" {
    setup_debug_dirs
    # curl stand-in: report who runs it and which file it was given
    mkdir -p "${BATS_TEST_TMPDIR}/shim"
    printf '#!/bin/sh\nfor a; do f="$a"; [ "$prev" = "--upload-file" ] && file="$a"; prev="$a"; done\necho "https://tricorder.pi-hole.net/$(id -un):${file}"\n' > "${BATS_TEST_TMPDIR}/shim/curl"
    chmod 0755 "${BATS_TEST_TMPDIR}/shim" "${BATS_TEST_TMPDIR}/shim/curl"
    # BATS_TEST_TMPDIR may not be traversable by the pihole user
    cp -a "${BATS_TEST_TMPDIR}/shim" /opt/pihole-test-shim

    debug_fn 'PATH="/opt/pihole-test-shim:${PATH}"; curl_to_tricorder; echo "token=${tricorder_token}"'
    rm -rf /opt/pihole-test-shim
    assert_output --partial "token=https://tricorder.pi-hole.net/pihole:/var/log/pihole/pihole_debug.log"
}

@test "piholeDebug.sh does not log the password hashes or the TOTP secret" {
    setup_debug_dirs
    # As written by pihole-FTL, with a value-changed marker on one line
    cat > /etc/pihole/pihole.toml <<'EOF'
[webserver.api]
  # Password hash
  pwhash = "$BALLOON-SHA256$v=1$s=1024,t=32$CANARY-PWHASH" ### CHANGED, default = ""
  totp_secret = "CANARY-TOTP"
  app_pwhash = ""
  app_sudo = false
EOF
    chown pihole:pihole /etc/pihole/pihole.toml

    debug_fn 'make_array_from_file /etc/pihole/pihole.toml'
    refute_output --partial "CANARY"
    assert_output --partial 'pwhash = "<removed>"'
    assert_output --partial 'totp_secret = "<removed>"'
    # Empty values and other keys are kept
    assert_output --partial 'app_pwhash = ""'
    assert_output --partial "app_sudo = false"
}
