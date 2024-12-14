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


def test_setFTLConfigValue_getFTLConfigValue(host):
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
    echo "development" > /etc/pihole/ftlbranch
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
