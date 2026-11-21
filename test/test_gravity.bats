#!/usr/bin/env bats
# Gravity tests

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/bats-file/load'
load 'bats_helper.bash'

FTL_BRANCH="development"

TICK="[✓]"
CROSS="[✗]"
INFO="[i]"

# Depending on the curl version, a specific error messages can be returned in case of failure
curlVersion=$(curl --version | awk '{print $2;exit}')

# Compare dotted versions semantically
version_ge() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

if version_ge "${curlVersion}" "8.21.0"; then
    curl821=true
elif version_ge "${curlVersion}" "7.75.0"; then
    curl775=true
fi

# Really old curl versions miss a fix for using --etag-save and --etag-compare together (https://github.com/curl/curl/pull/5180)
# Fixed in curl 7.70.0 - April 29 2020
if version_ge "${curlVersion}" "7.70.0"; then
    curl_etag_support=true
fi

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

    # Install pihole-FTL binary
    echo "${FTL_BRANCH}" > /etc/pihole/ftlbranch
    run bash -c "
        source /opt/pihole/basic-install.sh
        funcOutput=\$(get_binary_name)
        binary=\"pihole-FTL\${funcOutput##*pihole-FTL}\"
        theRest=\"\${funcOutput%pihole-FTL*}\"
        FTLdetect \"\${binary}\" \"\${theRest}\"
    "
    assert_success
}

teardown() {
    # Remove gravity database after each test
    rm -f /etc/pihole/gravity.db
}

@test "Gravity creates new database on first run" {
    run bash -c "
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    assert_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Default adlist is successfully added to gravity database" {
    run bash -c '
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        pihole -g
    '
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${TICK} Status: Retrieval successful"
    assert_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"

    refute_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --regexp "Number of gravity domains: [[:digit:]]+ \([[:digit:]]+ unique domains\)"
    assert_line --partial "${TICK} Done."
    refute_output --partial "${CROSS}"

    run bash -c "
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    if [ "${curl_etag_support}" = true ]; then
        assert_line --partial "${TICK} Status: No changes detected"
    else
        assert_line --partial "${TICK} Status: Retrieval successful"
    fi
    assert_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"

    refute_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --regexp "Number of gravity domains: [[:digit:]]+ \([[:digit:]]+ unique domains\)"
    assert_line --partial "${TICK} Done."
    refute_output --partial "${CROSS}"

}

@test "Local adlist is successfully added to gravity database" {
    run bash -c "
        echo -e 'badsite.com\nadsite.com\n||subdomain.domain.tld^\nstrange..domain..com' > /etc/pihole/localAdlist.txt
    "
    assert_success

    run bash -c "
        cat /etc/pihole/localAdlist.txt
    "
    assert_line --partial "badsite.com"
    assert_line --partial "adsite.com"
    assert_line --partial "||subdomain.domain.tld^"
    assert_line --partial "strange..domain..com"
    run bash -c '
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist "file:///etc/pihole/localAdlist.txt"
        pihole -g
    '
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Using local file /etc/pihole/localAdlist.txt"
    assert_line --partial "${TICK} Status: Retrieval successful"
    assert_line --partial "${TICK} Parsed 2 exact domains and 1 ABP-style domains (blocking, ignored 1 non-domain entries)"
    refute_output --partial "strange..domain..com"

    assert_line --partial "${INFO} Number of gravity domains: 3 (3 unique domains)"
    assert_line --partial "${TICK} Done."
    refute_output --partial "${CROSS}"
}

@test "Gravity fails to download invalid protocol" {
    run bash -c '
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist "dadfasdfsdafsf.com"
        pihole -g
    '
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${CROSS} Status: Invalid protocol specified. Ignoring list."
    assert_line --partial "Ensure your URL starts with a valid protocol like http:// , https:// or file:// ."
    assert_line --partial "${CROSS} Status: Invalid protocol specified. Ignoring list."
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to download invalid target" {
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist '<script>alert(0)</script>'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: <script>alert(0)</script>"
    assert_line --partial "${CROSS} Invalid Target"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to download non-resolvable host" {
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'https://raw.githubusercontent.df'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: https://raw.githubusercontent.df"
    if [ "${curl775}" = true ] || [ "${curl821}" = true ]; then
        assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=6 Msg: Could not resolve host: raw.githubusercontent.df"
    else
        assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=6 Msg: No message available. Non supported curl version.)"
    fi

    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to download without host part in URL" {
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'http://'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: http://"
    assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=3 Msg:"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to connect to non-existing host (URL)" {
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'http://localhost:81/list'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: http://localhost:81/list"
    if [ "${curl821}" = true ]; then
        assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=7 Msg: Failed to connect to localhost:81"
    elif [ "${curl775}" = true ]; then
        assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=7 Msg: Failed to connect to localhost port 81"
    else
        assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=7 Msg: No message available. Non supported curl version.)"
    fi

    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to connect to non-existing host (IP)" {
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'http://10.0.0.1/list'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: http://10.0.0.1/list"
    assert_line --partial "${CROSS} Status: Retrieval failed (exit_code=28 Msg:"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to connect to non-SSL host for HTTPS URL" {
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'https://localhost/list'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: https://localhost/list"
    assert_line --partial "${CROSS} Status: Retrieval failed"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}


@test "Gravity fails to read file not accessible by pihole user I" {
    assert_file_exists /etc/shadow

    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'file:///etc/shadow'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: file:///etc/shadow"
    assert_line --partial "${CROSS} Cannot read file (current user 'pihole' lacks read permission)"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}


@test "Gravity fails to read file not accessible by pihole user II" {
    assert_file_exists /etc/shadow

    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'file:/./etc/shadow'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"

    assert_line --partial "${INFO} Target: file:/./etc/shadow"
    assert_line --partial "${CROSS} Cannot read file (current user 'pihole' lacks read permission)"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}


@test "Gravity reads local file the pihole user was checked against" {
    assert_file_exists /etc/shadow

    run bash -c "
        mkdir -p /lf/a/b /lf/etc
        ln -s /lf/a/b /lf/l
        echo 'decoy.example.com' >/lf/etc/shadow
        chmod 644 /lf/etc/shadow
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'file:///lf/l/../../etc/shadow'
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Using local file /lf/l/../../etc/shadow"
    assert_line --partial "${TICK} Status: Retrieval successful"
    assert_line --partial "${TICK} Parsed 1 exact domains and 0 ABP-style domains (blocking, ignored 0 non-domain entries)"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 1 (1 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity keeps list changes made while it runs" {
    # The second run waits for the connect timeout of its download, the lists are changed meanwhile
    run bash -c "
        /opt/pihole/gravity.sh --newdb
        /opt/pihole/gravity.sh --addadlist 'http://10.0.0.1/list'
        pihole -g >/dev/null
        pihole-FTL sqlite3 /etc/pihole/gravity.db \"INSERT INTO domainlist (type, domain) VALUES (1, 'removed.during.gravity'); UPDATE adlist SET number = 42, status = 0;\"
        pihole -g >/tmp/gravity.out 2>&1 &
        for i in \$(seq 1 100); do grep -q 'Target: http://10.0.0.1/list' /tmp/gravity.out && break; sleep 0.1; done
        pihole-FTL sqlite3 /etc/pihole/gravity.db \"INSERT INTO domainlist (type, domain) VALUES (1, 'added.during.gravity'); DELETE FROM domainlist WHERE domain = 'removed.during.gravity'; INSERT INTO [group] (name) VALUES ('added during gravity'); UPDATE adlist SET comment = 'changed during gravity';\"
        wait
        cat /tmp/gravity.out
        rm -f /tmp/gravity.out
    "
    assert_success
    assert_line --partial "${TICK} Done."
    refute_line --partial "Unable to take over list changes"

    run pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT domain FROM domainlist JOIN domainlist_by_group ON domainlist_id = id;"
    assert_output "added.during.gravity"

    run pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT name FROM [group] WHERE id > 0;"
    assert_output "added during gravity"

    # The comment is taken over, number and status are what this run found
    run pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT comment, number, status FROM adlist;"
    assert_output "changed during gravity|0|4"
}

@test "Gravity does not start while another gravity run holds the lock" {
    # Hold the lock on another file descriptor, like a concurrent gravity run would
    run bash -c "
        touch /etc/pihole/gravity.lock
        chown pihole:pihole /etc/pihole/gravity.lock
        (
            flock -n 9 || exit 99
            pihole -g
        ) 9>>/etc/pihole/gravity.lock
    "
    assert_failure 1
    assert_line --partial "${CROSS} Another gravity run is in progress, not starting a second one"
    refute_line --partial "Neutrino emissions detected"
    assert_file_not_exists /etc/pihole/gravity.db

    # The lock is released once the other run is gone
    run bash -c "
        pihole -g
    "
    assert_success
    assert_line --partial "${TICK} Done."
}

@test "Gravity restores the database from a backup if copying the old data fails" {
    # Create a client with a custom group, keep it in backup no. 1, then break the current database
    run bash -c "
        rm -rf /etc/pihole/gravity_backups
        pihole -g >/dev/null
        pihole-FTL sqlite3 /etc/pihole/gravity.db \"INSERT INTO [group] (name) VALUES ('restore test'); INSERT INTO client (ip) VALUES ('10.1.2.3'); INSERT INTO client_by_group (client_id, group_id) SELECT c.id, g.id FROM client c, [group] g WHERE c.ip = '10.1.2.3' AND g.name = 'restore test';\"
        pihole -g >/dev/null
        pihole-FTL sqlite3 /etc/pihole/gravity.db 'DROP TABLE client_by_group;'
        pihole -g
    "
    assert_success
    assert_line --partial "${CROSS} Unable to copy data from /etc/pihole/gravity.db to /etc/pihole/gravity.db_temp"
    assert_line --partial "${INFO} Attempting to restore previous database from backup no. 1"
    assert_line --partial "${TICK} Successfully restored from backup (/etc/pihole/gravity_backups/gravity.db.1 at"
    assert_line --partial "${TICK} Done."

    run pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT g.name FROM client_by_group cg JOIN client c ON c.id = cg.client_id JOIN [group] g ON g.id = cg.group_id WHERE c.ip = '10.1.2.3' AND g.id > 0;"
    assert_output "restore test"

    run pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT value FROM info WHERE property = 'gravity_restored';"
    refute_output "failed"
    assert_output --regexp "^[0-9]{4}-[0-9]{2}-[0-9]{2} "
}

@test "Gravity tries the next backup if restoring a backup fails" {
    # Keep the client in backups no. 1 and no. 2, then break the current database and backup no. 1
    run bash -c "
        rm -rf /etc/pihole/gravity_backups
        pihole -g >/dev/null
        pihole-FTL sqlite3 /etc/pihole/gravity.db \"INSERT INTO [group] (name) VALUES ('restore test'); INSERT INTO client (ip) VALUES ('10.1.2.3'); INSERT INTO client_by_group (client_id, group_id) SELECT c.id, g.id FROM client c, [group] g WHERE c.ip = '10.1.2.3' AND g.name = 'restore test';\"
        pihole -g >/dev/null
        pihole -g >/dev/null
        pihole-FTL sqlite3 /etc/pihole/gravity.db 'DROP TABLE client_by_group;'
        pihole-FTL sqlite3 /etc/pihole/gravity_backups/gravity.db.1 'DROP TABLE client_by_group;'
        pihole -g
    "
    assert_success
    assert_line --partial "${CROSS} Unable to copy data from /etc/pihole/gravity.db to /etc/pihole/gravity.db_temp"
    assert_line --partial "${INFO} Attempting to restore previous database from backup no. 1"
    assert_line --partial "${CROSS} Unable to copy data from backup no. 1 to /etc/pihole/gravity.db_temp"
    assert_line --partial "${INFO} Attempting to restore previous database from backup no. 2"
    assert_line --partial "${TICK} Successfully restored from backup (/etc/pihole/gravity_backups/gravity.db.2 at"
    assert_line --partial "${TICK} Done."

    run pihole-FTL sqlite3 /etc/pihole/gravity.db "SELECT g.name FROM client_by_group cg JOIN client c ON c.id = cg.client_id JOIN [group] g ON g.id = cg.group_id WHERE c.ip = '10.1.2.3' AND g.id > 0;"
    assert_output "restore test"
}
