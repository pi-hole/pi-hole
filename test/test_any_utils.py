def test_key_val_replacement_works(host):
    """Confirms addOrEditKeyValPair either adds or replaces a key value pair in a given file"""
    host.run(
        """
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value1"
    addOrEditKeyValPair "./testoutput" "KEY_TWO" "value2"
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value3"
    addOrEditKeyValPair "./testoutput" "KEY_FOUR" "value4"
    """
    )
    output = host.run(
        """
    cat ./testoutput
    """
    )
    expected_stdout = "KEY_ONE=value3\nKEY_TWO=value2\nKEY_FOUR=value4\n"
    assert expected_stdout == output.stdout


def test_key_addition_works(host):
    """Confirms addKey adds a key (no value) to a file without duplicating it"""
    host.run(
        """
    source /opt/pihole/utils.sh
    addKey "./testoutput" "KEY_ONE"
    addKey "./testoutput" "KEY_ONE"
    addKey "./testoutput" "KEY_TWO"
    addKey "./testoutput" "KEY_TWO"
    addKey "./testoutput" "KEY_THREE"
    addKey "./testoutput" "KEY_THREE"
    """
    )
    output = host.run(
        """
    cat ./testoutput
    """
    )
    expected_stdout = "KEY_ONE\nKEY_TWO\nKEY_THREE\n"
    assert expected_stdout == output.stdout


def test_key_addition_substr(host):
    """Confirms addKey adds substring keys (no value) to a file"""
    host.run(
        """
    source /opt/pihole/utils.sh
    addKey "./testoutput" "KEY_ONE"
    addKey "./testoutput" "KEY_O"
    addKey "./testoutput" "KEY_TWO"
    addKey "./testoutput" "Y_TWO"
    """
    )
    output = host.run(
        """
    cat ./testoutput
    """
    )
    expected_stdout = "KEY_ONE\nKEY_O\nKEY_TWO\nY_TWO\n"
    assert expected_stdout == output.stdout


def test_key_removal_works(host):
    """Confirms removeKey removes a key or key/value pair"""
    host.run(
        """
    source /opt/pihole/utils.sh
    addOrEditKeyValPair "./testoutput" "KEY_ONE" "value1"
    addOrEditKeyValPair "./testoutput" "KEY_TWO" "value2"
    addOrEditKeyValPair "./testoutput" "KEY_THREE" "value3"
    addKey "./testoutput" "KEY_FOUR"
    removeKey "./testoutput" "KEY_TWO"
    removeKey "./testoutput" "KEY_FOUR"
    """
    )
    output = host.run(
        """
    cat ./testoutput
    """
    )
    expected_stdout = "KEY_ONE=value1\nKEY_THREE=value3\n"
    assert expected_stdout == output.stdout


def test_getFTLPIDFile_default(host):
    """Confirms getFTLPIDFile returns the default PID file path"""
    output = host.run(
        """
    source /opt/pihole/utils.sh
    getFTLPIDFile
    """
    )
    expected_stdout = "/run/pihole-FTL.pid\n"
    assert expected_stdout == output.stdout


def test_getFTLPID_default(host):
    """Confirms getFTLPID returns the default value if FTL is not running"""
    output = host.run(
        """
    source /opt/pihole/utils.sh
    getFTLPID
    """
    )
    expected_stdout = "-1\n"
    assert expected_stdout == output.stdout


def test_getFTLPIDFile_and_getFTLPID_custom(host):
    """Confirms getFTLPIDFile returns a custom PID file path"""
    host.run(
        """
    tmpfile=$(mktemp)
    echo "PIDFILE=${tmpfile}" > /etc/pihole/pihole-FTL.conf
    echo "1234" > ${tmpfile}
    """
    )
    output = host.run(
        """
    source /opt/pihole/utils.sh
    FTL_PID_FILE=$(getFTLPIDFile)
    getFTLPID "${FTL_PID_FILE}"
    """
    )
    expected_stdout = "1234\n"
    assert expected_stdout == output.stdout


def test_getFTLConfigValue_getFTLConfigValue(host):
    """
    Confirms getFTLConfigValue works (also assumes setFTLConfigValue works)
    Requires FTL to be installed, so we do that first
    (taken from test_FTL_development_binary_installed_and_responsive_no_errors)
    """
    host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    echo "development-v6" > /etc/pihole/ftlbranch
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )

    output = host.run(
        """
    source /opt/pihole/utils.sh
    setFTLConfigValue "dns.upstreams" '["9.9.9.9"]' > /dev/null
    getFTLConfigValue "dns.upstreams"
    """
    )

    assert "[ 9.9.9.9 ]" in output.stdout
