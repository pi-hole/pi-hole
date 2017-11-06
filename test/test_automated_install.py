import pytest
from textwrap import dedent

SETUPVARS = {
    'PIHOLE_INTERFACE' : 'eth99',
    'IPV4_ADDRESS' : '1.1.1.1',
    'IPV6_ADDRESS' : 'FE80::240:D0FF:FE48:4672',
    'PIHOLE_DNS_1' : '4.2.2.1',
    'PIHOLE_DNS_2' : '4.2.2.2'
}

tick_box="[\x1b[1;32m\xe2\x9c\x93\x1b[0m]".decode("utf-8")
cross_box="[\x1b[1;31m\xe2\x9c\x97\x1b[0m]".decode("utf-8")
info_box="[i]".decode("utf-8")

def test_setupVars_are_sourced_to_global_scope(Pihole):
    ''' currently update_dialogs sources setupVars with a dot,
    then various other functions use the variables.
    This confirms the sourced variables are in scope between functions '''
    setup_var_file = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k,v in SETUPVARS.iteritems():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "EOF\n"
    Pihole.run(setup_var_file)

    script = dedent('''\
    set -e
    printSetupVars() {
        # Currently debug test function only
        echo "Outputting sourced variables"
        echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
        echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
        echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
        echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
        echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
    }
    update_dialogs() {
        . /etc/pihole/setupVars.conf
    }
    update_dialogs
    printSetupVars
    ''')

    output = run_script(Pihole, script).stdout

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def test_setupVars_saved_to_file(Pihole):
    ''' confirm saved settings are written to a file for future updates to re-use '''
    set_setup_vars = '\n'  # dedent works better with this and padding matching script below
    for k,v in SETUPVARS.iteritems():
        set_setup_vars += "    {}={}\n".format(k, v)
    Pihole.run(set_setup_vars).stdout

    script = dedent('''\
    set -e
    echo start
    TERM=xterm
    source /opt/pihole/basic-install.sh
    {}
    mkdir -p /etc/dnsmasq.d
    version_check_dnsmasq
    finalExports
    cat /etc/pihole/setupVars.conf
    '''.format(set_setup_vars))

    output = run_script(Pihole, script).stdout

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def test_configureFirewall_firewalld_running_no_errors(Pihole):
    ''' confirms firewalld rules are applied when firewallD is running '''
    # firewallD returns 'running' as status
    mock_command('firewall-cmd', {'*':('running', 0)}, Pihole)
    # Whiptail dialog returns Ok for user prompt
    mock_command('whiptail', {'*':('', 0)}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Configuring FirewallD for httpd and dnsmasq'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/firewall-cmd').stdout
    assert 'firewall-cmd --state' in firewall_calls
    assert 'firewall-cmd --permanent --add-service=http --add-service=dns' in firewall_calls
    assert 'firewall-cmd --reload' in firewall_calls

def test_configureFirewall_firewalld_disabled_no_errors(Pihole):
    ''' confirms firewalld rules are not applied when firewallD is not running '''
    # firewallD returns non-running status
    mock_command('firewall-cmd', {'*':('not running', '1')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'No active firewall detected.. skipping firewall configuration'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_firewalld_enabled_declined_no_errors(Pihole):
    ''' confirms firewalld rules are not applied when firewallD is running, user declines ruleset '''
    # firewallD returns running status
    mock_command('firewall-cmd', {'*':('running', 0)}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', 1)}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_no_firewall(Pihole):
    ''' confirms firewall skipped no daemon is running '''
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'No active firewall detected'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_IPTables_enabled_declined_no_errors(Pihole):
    ''' confirms IPTables rules are not applied when IPTables is running, user declines ruleset '''
    # iptables command exists
    mock_command('iptables', {'*':('', '0')}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*':('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', '1')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_IPTables_enabled_rules_exist_no_errors(Pihole):
    ''' confirms IPTables rules are not applied when IPTables is running and rules exist '''
    # iptables command exists and returns 0 on calls (should return 0 on iptables -C)
    mock_command('iptables', {'-S':('-P INPUT DENY', '0')}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*':('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', '0')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/iptables').stdout
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT' not in firewall_calls
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT' not in firewall_calls
    assert 'iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT' not in firewall_calls

def test_configureFirewall_IPTables_enabled_not_exist_no_errors(Pihole):
    ''' confirms IPTables rules are applied when IPTables is running and rules do not exist '''
    # iptables command and returns 0 on calls (should return 1 on iptables -C)
    mock_command('iptables', {'-S':('-P INPUT DENY', '0'), '-C':('', 1), '-I':('', 0)}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*':('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', '0')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/iptables').stdout
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT' in firewall_calls
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT' in firewall_calls
    assert 'iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT' in firewall_calls

def test_installPiholeWeb_fresh_install_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed on a fresh build '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    installPiholeWeb
    ''')
    assert info_box + ' Installing blocking page...' in installWeb.stdout
    assert tick_box + ' Creating directory for blocking page, and copying files' in installWeb.stdout
    assert cross_box + ' Backing up index.lighttpd.html' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' in installWeb.stdout
    assert tick_box + ' Installing sudoer file' in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'blockingpage.css' in web_directory

def test_update_package_cache_success_no_errors(Pihole):
    ''' confirms package cache was updated without any errors'''
    updateCache = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    update_package_cache
    ''')
    assert tick_box + ' Update local cache of available packages' in updateCache.stdout
    assert 'Error: Unable to update package cache.' not in updateCache.stdout

def test_update_package_cache_failure_no_errors(Pihole):
    ''' confirms package cache was not updated'''
    mock_command('apt-get', {'update':('', '1')}, Pihole)
    updateCache = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    update_package_cache
    ''')
    assert cross_box + ' Update local cache of available packages' in updateCache.stdout
    assert 'Error: Unable to update package cache.' in updateCache.stdout

def test_FTL_detect_aarch64_no_errors(Pihole):
    ''' confirms only aarch64 package is downloaded for FTL engine '''
    # mock uname to return aarch64 platform
    mock_command('uname', {'-m':('aarch64', '0')}, Pihole)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls':('/lib/ld-linux-aarch64.so.1', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected ARM-aarch64 architecture'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout

def test_FTL_detect_armv6l_no_errors(Pihole):
    ''' confirms only armv6l package is downloaded for FTL engine '''
    # mock uname to return armv6l platform
    mock_command('uname', {'-m':('armv6l', '0')}, Pihole)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls':('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected ARM-hf architecture (armv6 or lower)'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout

def test_FTL_detect_armv7l_no_errors(Pihole):
    ''' confirms only armv7l package is downloaded for FTL engine '''
    # mock uname to return armv7l platform
    mock_command('uname', {'-m':('armv7l', '0')}, Pihole)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls':('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected ARM-hf architecture (armv7+)'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout

def test_FTL_detect_x86_64_no_errors(Pihole):
    ''' confirms only x86_64 package is downloaded for FTL engine '''
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected x86_64 architecture'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout

def test_FTL_detect_unknown_no_errors(Pihole):
    ''' confirms only generic package is downloaded for FTL engine '''
    # mock uname to return generic platform
    mock_command('uname', {'-m':('mips', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = 'Not able to detect architecture (unknown: mips)'
    assert expected_stdout in detectPlatform.stdout

def test_FTL_download_aarch64_no_errors(Pihole):
    ''' confirms only aarch64 package is downloaded for FTL engine '''
    # mock uname to return generic platform
    download_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLinstall pihole-FTL-aarch64-linux-gnu
    ''')
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    error = 'Error: Download of binary from Github failed'
    assert error not in download_binary.stdout
    error = 'Error: URL not found'
    assert error not in download_binary.stdout

def test_FTL_download_unknown_fails_no_errors(Pihole):
    ''' confirms unknown binary is not downloaded for FTL engine '''
    # mock uname to return generic platform
    download_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLinstall pihole-FTL-mips
    ''')
    expected_stdout = cross_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    error = 'Error: URL not found'
    assert error in download_binary.stdout

def test_FTL_binary_installed_and_responsive_no_errors(Pihole):
    ''' confirms FTL binary is copied and functional in installed location '''
    installed_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    pihole-FTL version
    ''')
    expected_stdout = 'v'
    assert expected_stdout in installed_binary.stdout

# def test_FTL_support_files_installed(Pihole):
#     ''' confirms FTL support files are installed '''
#     support_files = Pihole.run('''
#     source /opt/pihole/basic-install.sh
#     FTLdetect
#     stat -c '%a %n' /var/log/pihole-FTL.log
#     stat -c '%a %n' /run/pihole-FTL.port
#     stat -c '%a %n' /run/pihole-FTL.pid
#     ls -lac /run
#     ''')
#     assert '644 /run/pihole-FTL.port' in support_files.stdout
#     assert '644 /run/pihole-FTL.pid' in support_files.stdout
#     assert '644 /var/log/pihole-FTL.log' in support_files.stdout

def test_IPv6_only_link_local(Pihole):
    ''' confirms IPv6 blocking is disabled for Link-local address '''
    # mock ip -6 address to return Link-local address
    mock_command_2('ip', {'-6 address':('inet6 fe80::d210:52fa:fe00:7ad7/64 scope link', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Unable to find IPv6 ULA/GUA address, IPv6 adblocking will not be enabled'
    assert expected_stdout in detectPlatform.stdout

def test_IPv6_only_ULA(Pihole):
    ''' confirms IPv6 blocking is enabled for ULA addresses '''
    # mock ip -6 address to return ULA address
    mock_command_2('ip', {'-6 address':('inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout

def test_IPv6_only_GUA(Pihole):
    ''' confirms IPv6 blocking is enabled for GUA addresses '''
    # mock ip -6 address to return GUA address
    mock_command_2('ip', {'-6 address':('inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 GUA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout

def test_IPv6_GUA_ULA_test(Pihole):
    ''' confirms IPv6 blocking is enabled for GUA and ULA addresses '''
    # mock ip -6 address to return GUA and ULA addresses
    mock_command_2('ip', {'-6 address':('inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global\ninet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout

def test_IPv6_ULA_GUA_test(Pihole):
    ''' confirms IPv6 blocking is enabled for GUA and ULA addresses '''
    # mock ip -6 address to return ULA and GUA addresses
    mock_command_2('ip', {'-6 address':('inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global\ninet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout

# Helper functions
def mock_command(script, args, container):
    ''' Allows for setup of commands we don't really want to have to run for real in unit tests '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent('''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1" in'''.format(script=script))
    for k, v in args.iteritems():
        case = dedent('''
        {arg})
        echo {res}
        exit {retcode}
        ;;'''.format(arg=k, res=v[0], retcode=v[1]))
        mock_script += case
    mock_script += dedent('''
    esac''')
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path, content=mock_script, scriptlog=script))

def mock_command_2(script, args, container):
    ''' Allows for setup of commands we don't really want to have to run for real in unit tests '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent('''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1 \$2" in'''.format(script=script))
    for k, v in args.iteritems():
        case = dedent('''
        \"{arg}\")
        echo \"{res}\"
        exit {retcode}
        ;;'''.format(arg=k, res=v[0], retcode=v[1]))
        mock_script += case
    mock_script += dedent('''
    esac''')
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path, content=mock_script, scriptlog=script))

def run_script(Pihole, script):
    result = Pihole.run(script)
    assert result.rc == 0
    return result
