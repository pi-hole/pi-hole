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
        echo "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" >/etc/pihole/adlists.list
        pihole -g
    '
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
    refute_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo "file:///etc/pihole/localAdlist.txt" >/etc/pihole/adlists.list
        pihole -g
    '
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

    assert_line --partial "${INFO} Using local file /etc/pihole/localAdlist.txt"
    assert_line --partial "${TICK} Status: Retrieval successful"
    assert_line --partial "${TICK} Parsed 2 exact domains and 1 ABP-style domains (blocking, ignored 1 non-domain entries)"
    assert_line --partial "- strange..domain..com"

    assert_line --partial "${INFO} Number of gravity domains: 3 (3 unique domains)"
    assert_line --partial "${TICK} Done."
    refute_output --partial "${CROSS}"
}

@test "Gravity fails to download invalid protocol" {
    run bash -c '
        echo "dadfasdfsdafsf.com" >/etc/pihole/adlists.list
        pihole -g
    '
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo '<script>alert(0)</script>' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

    assert_line --partial "${INFO} Target: <script>alert(0)</script>"
    assert_line --partial "${CROSS} Invalid Target"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

@test "Gravity fails to download non-resolvable host" {
    run bash -c "
        echo 'https://raw.githubusercontent.df' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo 'http://' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo 'http://localhost:81/list' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo 'http://10.0.0.1/list' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo 'https://localhost/list' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

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
        echo 'file:///etc/shadow' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

    assert_line --partial "${INFO} Target: file:///etc/shadow"
    assert_line --partial "${CROSS} Cannot read file (user 'pihole' lacks read permission)"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}


@test "Gravity fails to read file not accessible by pihole user II" {
    assert_file_exists /etc/shadow

    run bash -c "
        echo 'file:/./etc/shadow' >/etc/pihole/adlists.list
        pihole -g
    "
    assert_success
    assert_line --partial "${INFO} Creating new gravity database"
    refute_line --partial "${INFO} No source list found, or it is empty"
    assert_line --partial "${INFO} Migrating content of /etc/pihole/adlists.list into new database"

    assert_line --partial "${INFO} Target: file:/./etc/shadow"
    assert_line --partial "${CROSS} Cannot read file (user 'pihole' lacks read permission)"
    assert_line --partial "${CROSS} List download failed: no cached list available"

    refute_line --regexp "Parsed [[:digit:]]+ exact domains and [[:digit:]]+ ABP-style domains.*"
    refute_line --partial "Sample of non-domain entries:"
    assert_line --partial "${INFO} Number of gravity domains: 0 (0 unique domains)"
    assert_line --partial "${TICK} Done."
}

