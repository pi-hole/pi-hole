#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'bats_helper.bash'

setup() {
    sed -n '/^tailFunc() {$/,/^}$/p' \
        /opt/pihole/pihole > "${BATS_TEST_TMPDIR}/tail-function.sh"

    grep -q '^tailFunc()' "${BATS_TEST_TMPDIR}/tail-function.sh"
}

run_tail_test() {
    run bash -c '
        logfile="$1"

        getFTLConfigValue() {
            case "$1" in
                dns.queryLogging) printf "true\n" ;;
                files.log.dnsmasq) printf "%s\n" "$logfile" ;;
            esac
        }

        tail() {
            [[ "$1" == "-f" ]] || return 2
            shift
            command tail -n 1 "$@"
        }

        source "$2"
        tailFunc "Synthetic"
    ' bash "$1" "${BATS_TEST_TMPDIR}/tail-function.sh"
}

@test "pihole tail reads a conventional logfile path" {
    logfile="${BATS_TEST_TMPDIR}/test.log"
    printf 'Synthetic DNS regression test\n' > "$logfile"

    run_tail_test "$logfile"

    assert_success
    assert_line "Synthetic DNS regression test"
}

@test "pihole tail reads a logfile path containing spaces" {
    logfile="${BATS_TEST_TMPDIR}/test log.txt"
    printf 'Synthetic DNS regression test\n' > "$logfile"

    run_tail_test "$logfile"

    assert_success
    assert_line "Synthetic DNS regression test"
}
