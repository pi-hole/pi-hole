#!/usr/bin/env bats
# Full-install test — runs in a dedicated container so no teardown is needed.
# Verifies that all files written by the installer are readable by the pihole user.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'libs/bats-mock/stub'
load 'bats_helper.bash'

INFO="[i]"
FTL_BRANCH="development"

@test "fresh install: all necessary files are readable by pihole user" {
    # bats-mock prepends $BATS_MOCK_BINDIR to PATH at load time but only
    # creates the directory on the first stub call.  We write scripts directly
    # so create it ourselves.
    mkdir -p "${BATS_MOCK_BINDIR}"

    # dialog — suppress any TUI calls; with a TTY allocated an uncaught dialog
    # invocation would block the test waiting for input
    printf '#!/bin/bash\nexit 0\n' > "${BATS_MOCK_BINDIR}/dialog"
    chmod +x "${BATS_MOCK_BINDIR}/dialog"

    # git — let every subcommand run for real except 'pull', which we suppress
    # so the test has no dependency on outbound network access
    local real_git
    real_git="$(type -P git)"
    cat > "${BATS_MOCK_BINDIR}/git" <<EOF
#!/bin/bash
case "\$1" in
    pull) exit 0 ;;
    *)                    exec "${real_git}" "\$@" ;;
esac
EOF
    chmod +x "${BATS_MOCK_BINDIR}/git"

    # systemctl / rc-service — accept any service-management call silently
    printf '#!/bin/bash\nexit 0\n' > "${BATS_MOCK_BINDIR}/systemctl"
    chmod +x "${BATS_MOCK_BINDIR}/systemctl"
    printf '#!/bin/bash\nexit 0\n' > "${BATS_MOCK_BINDIR}/rc-service"
    chmod +x "${BATS_MOCK_BINDIR}/rc-service"

    command -v apt-get > /dev/null && apt-get install -qq man || true
    command -v dnf > /dev/null && dnf install -y man || true
    command -v yum > /dev/null && yum install -y man || true
    command -v apk > /dev/null && apk add mandoc man-pages || true

    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch

    run bash -c "
        export TERM=xterm
        export DEBIAN_FRONTEND=noninteractive
        umask 0027
        source /opt/pihole/basic-install.sh > /dev/null
        runUnattended=true
        main
        /opt/pihole/pihole-FTL-prestart.sh
    "
    assert_success

    local maninstalled=true
    if [[ "${output}" == *"${INFO} man not installed"* ]] || [[ "${output}" == *"${INFO} man pages not installed"* ]]; then
        maninstalled=false
    fi

    # Verify files exist before checking user-level read permission.
    assert_dir_exists  /etc/pihole
    assert_file_exists /etc/pihole/dhcp.leases
    assert_file_exists /etc/pihole/install.log
    assert_file_exists /etc/pihole/versions
    assert_file_exists /etc/pihole/macvendor.db
    assert_file_exists /etc/init.d/pihole-FTL

    if [[ "${maninstalled}" == "true" ]]; then
        assert_dir_exists  /usr/local/share/man
        assert_dir_exists  /usr/local/share/man/man8
        assert_file_exists /usr/local/share/man/man8/pihole.8
    fi

    assert_file_exists /etc/cron.d/pihole

    # Verify the pihole user can actually read the files (bats-file checks as
    # the current process user; _check_perm runs the test as the pihole user).
    local piholeuser="pihole"
    _check_perm() { su -s /bin/bash -c "test -${1} ${2}" -p ${piholeuser}; }

    run _check_perm r /etc/pihole; assert_success
    run _check_perm x /etc/pihole; assert_success
    run _check_perm r /etc/pihole/dhcp.leases; assert_success
    run _check_perm r /etc/pihole/install.log; assert_success
    run _check_perm r /etc/pihole/versions; assert_success
    # pihole -v reads the versions file as the calling user, so it has to be
    # readable by all users, not only by the pihole user
    run su -s /bin/bash -c "test -r /etc/pihole/versions" -p nobody; assert_success
    run _check_perm r /etc/pihole/macvendor.db; assert_success
    run _check_perm x /etc/init.d/pihole-FTL; assert_success
    run _check_perm r /etc/init.d/pihole-FTL; assert_success

    if [[ "${maninstalled}" == "true" ]]; then
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
        [[ -z "${dir}" ]] && continue
        assert_dir_exists "${dir}"
        run _check_perm r "${dir}"; assert_success
        run _check_perm x "${dir}"; assert_success
        local files
        files=$(find "${dir}" -maxdepth 1 -type f -exec echo {} \; 2>/dev/null || true)
        while IFS= read -r file; do
            [[ -z "${file}" ]] && continue
            assert_file_exists "${file}"
            run _check_perm r "${file}"; assert_success
        done <<< "${files}"
    done <<< "${dirs}"
}
