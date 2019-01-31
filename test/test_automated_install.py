from textwrap import dedent
import re
from conftest import (
    SETUPVARS,
    tick_box,
    info_box,
    cross_box,
    mock_command,
    mock_command_2,
    run_script
)


def test_supported_operating_system(Pihole):
    '''
    confirm installer exists on unsupported distribution
    '''
    # break supported package managers to emulate an unsupported distribution
    Pihole.run('rm -rf /usr/bin/apt-get')
    Pihole.run('rm -rf /usr/bin/rpm')
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = cross_box + ' OS distribution not supported'
    assert expected_stdout in distro_check.stdout
    # assert distro_check.rc == 1


def test_setupVars_are_sourced_to_global_scope(Pihole):
    '''
    currently update_dialogs sources setupVars with a dot,
    then various other functions use the variables.
    This confirms the sourced variables are in scope between functions
    '''
    setup_var_file = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k, v in SETUPVARS.iteritems():
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

    for k, v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output


def test_setupVars_saved_to_file(Pihole):
    '''
    confirm saved settings are written to a file for future updates to re-use
    '''
    # dedent works better with this and padding matching script below
    set_setup_vars = '\n'
    for k, v in SETUPVARS.iteritems():
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
    echo "" > /etc/pihole/pihole-FTL.conf
    finalExports
    cat /etc/pihole/setupVars.conf
    '''.format(set_setup_vars))

    output = run_script(Pihole, script).stdout

    for k, v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output


def test_configureFirewall_firewalld_running_no_errors(Pihole):
    '''
    confirms firewalld rules are applied when firewallD is running
    '''
    # firewallD returns 'running' as status
    mock_command('firewall-cmd', {'*': ('running', 0)}, Pihole)
    # Whiptail dialog returns Ok for user prompt
    mock_command('whiptail', {'*': ('', 0)}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Configuring FirewallD for httpd and pihole-FTL'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/firewall-cmd').stdout
    assert 'firewall-cmd --state' in firewall_calls
    assert ('firewall-cmd '
            '--permanent '
            '--add-service=http '
            '--add-service=dns') in firewall_calls
    assert 'firewall-cmd --reload' in firewall_calls


def test_configureFirewall_firewalld_disabled_no_errors(Pihole):
    '''
    confirms firewalld rules are not applied when firewallD is not running
    '''
    # firewallD returns non-running status
    mock_command('firewall-cmd', {'*': ('not running', '1')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = ('No active firewall detected.. '
                       'skipping firewall configuration')
    assert expected_stdout in configureFirewall.stdout


def test_configureFirewall_firewalld_enabled_declined_no_errors(Pihole):
    '''
    confirms firewalld rules are not applied when firewallD is running, user
    declines ruleset
    '''
    # firewallD returns running status
    mock_command('firewall-cmd', {'*': ('running', 0)}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', 1)}, Pihole)
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
    '''
    confirms IPTables rules are not applied when IPTables is running, user
    declines ruleset
    '''
    # iptables command exists
    mock_command('iptables', {'*': ('', '0')}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*': ('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout


def test_configureFirewall_IPTables_enabled_rules_exist_no_errors(Pihole):
    '''
    confirms IPTables rules are not applied when IPTables is running and rules
    exist
    '''
    # iptables command exists and returns 0 on calls
    # (should return 0 on iptables -C)
    mock_command('iptables', {'-S': ('-P INPUT DENY', '0')}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*': ('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/iptables').stdout
    # General call type occurances
    assert len(re.findall(r'iptables -S', firewall_calls)) == 1
    assert len(re.findall(r'iptables -C', firewall_calls)) == 4
    assert len(re.findall(r'iptables -I', firewall_calls)) == 0

    # Specific port call occurances
    assert len(re.findall(r'tcp --dport 80', firewall_calls)) == 1
    assert len(re.findall(r'tcp --dport 53', firewall_calls)) == 1
    assert len(re.findall(r'udp --dport 53', firewall_calls)) == 1
    assert len(re.findall(r'tcp --dport 4711:4720', firewall_calls)) == 1


def test_configureFirewall_IPTables_enabled_not_exist_no_errors(Pihole):
    '''
    confirms IPTables rules are applied when IPTables is running and rules do
    not exist
    '''
    # iptables command and returns 0 on calls (should return 1 on iptables -C)
    mock_command(
        'iptables',
        {
            '-S': (
                '-P INPUT DENY',
                '0'
            ),
            '-C': (
                '',
                1
            ),
            '-I': (
                '',
                0
            )
        },
        Pihole
    )
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*': ('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/iptables').stdout
    # General call type occurances
    assert len(re.findall(r'iptables -S', firewall_calls)) == 1
    assert len(re.findall(r'iptables -C', firewall_calls)) == 4
    assert len(re.findall(r'iptables -I', firewall_calls)) == 4

    # Specific port call occurances
    assert len(re.findall(r'tcp --dport 80', firewall_calls)) == 2
    assert len(re.findall(r'tcp --dport 53', firewall_calls)) == 2
    assert len(re.findall(r'udp --dport 53', firewall_calls)) == 2
    assert len(re.findall(r'tcp --dport 4711:4720', firewall_calls)) == 2


def test_selinux_enforcing_default_exit(Pihole):
    '''
    confirms installer prompts to exit when SELinux is Enforcing by default
    '''
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': ('Enforcing', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Enforcing'
    assert expected_stdout in check_selinux.stdout
    expected_stdout = 'SELinux Enforcing detected, exiting installer'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 1


def test_selinux_enforcing_continue(Pihole):
    '''
    confirms installer prompts to continue with custom policy warning
    '''
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': ('Enforcing', '0')}, Pihole)
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Enforcing'
    assert expected_stdout in check_selinux.stdout
    expected_stdout = info_box + (' Continuing installation with SELinux '
                                  'Enforcing')
    assert expected_stdout in check_selinux.stdout
    expected_stdout = info_box + (' Please refer to official SELinux '
                                  'documentation to create a custom policy')
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_selinux_permissive(Pihole):
    '''
    confirms installer continues when SELinux is Permissive
    '''
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': ('Permissive', '0')}, Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Permissive'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_selinux_disabled(Pihole):
    '''
    confirms installer continues when SELinux is Disabled
    '''
    mock_command('getenforce', {'*': ('Disabled', '0')}, Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux mode detected: Disabled'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_installPiholeWeb_fresh_install_no_errors(Pihole):
    '''
    confirms all web page assets from Core repo are installed on a fresh build
    '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    installPiholeWeb
    ''')
    expected_stdout = info_box + ' Installing blocking page...'
    assert expected_stdout in installWeb.stdout
    expected_stdout = tick_box + (' Creating directory for blocking page, '
                                  'and copying files')
    assert expected_stdout in installWeb.stdout
    expected_stdout = cross_box + ' Backing up index.lighttpd.html'
    assert expected_stdout in installWeb.stdout
    expected_stdout = ('No default index.lighttpd.html file found... '
                       'not backing up')
    assert expected_stdout in installWeb.stdout
    expected_stdout = tick_box + ' Installing sudoer file'
    assert expected_stdout in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'blockingpage.css' in web_directory


def test_update_package_cache_success_no_errors(Pihole):
    '''
    confirms package cache was updated without any errors
    '''
    updateCache = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    update_package_cache
    ''')
    expected_stdout = tick_box + ' Update local cache of available packages'
    assert expected_stdout in updateCache.stdout
    assert 'error' not in updateCache.stdout.lower()


def test_update_package_cache_failure_no_errors(Pihole):
    '''
    confirms package cache was not updated
    '''
    mock_command('apt-get', {'update': ('', '1')}, Pihole)
    updateCache = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    update_package_cache
    ''')
    expected_stdout = cross_box + ' Update local cache of available packages'
    assert expected_stdout in updateCache.stdout
    assert 'Error: Unable to update package cache.' in updateCache.stdout


def test_FTL_detect_aarch64_no_errors(Pihole):
    '''
    confirms only aarch64 package is downloaded for FTL engine
    '''
    # mock uname to return aarch64 platform
    mock_command('uname', {'-m': ('aarch64', '0')}, Pihole)
    # mock ldd to respond with aarch64 shared library
    mock_command(
        'ldd',
        {
            '/bin/ls': (
                '/lib/ld-linux-aarch64.so.1',
                '0'
            )
        },
        Pihole
    )
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
    '''
    confirms only armv6l package is downloaded for FTL engine
    '''
    # mock uname to return armv6l platform
    mock_command('uname', {'-m': ('armv6l', '0')}, Pihole)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (' Detected ARM-hf architecture '
                                  '(armv6 or lower)')
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv7l_no_errors(Pihole):
    '''
    confirms only armv7l package is downloaded for FTL engine
    '''
    # mock uname to return armv7l platform
    mock_command('uname', {'-m': ('armv7l', '0')}, Pihole)
    # mock ldd to respond with aarch64 shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
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
    '''
    confirms only x86_64 package is downloaded for FTL engine
    '''
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
    mock_command('uname', {'-m': ('mips', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    ''')
    expected_stdout = 'Not able to detect architecture (unknown: mips)'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_download_aarch64_no_errors(Pihole):
    '''
    confirms only aarch64 package is downloaded for FTL engine
    '''
    download_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    binary="pihole-FTL-aarch64-linux-gnu"
    FTLinstall
    ''')
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    assert 'error' not in download_binary.stdout.lower()


def test_FTL_download_unknown_fails_no_errors(Pihole):
    '''
    confirms unknown binary is not downloaded for FTL engine
    '''
    download_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    binary="pihole-FTL-mips"
    FTLinstall
    ''')
    expected_stdout = cross_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    error1 = 'Error: URL https://github.com/pi-hole/FTL/releases/download/'
    assert error1 in download_binary.stdout
    error2 = 'not found'
    assert error2 in download_binary.stdout


def test_FTL_download_binary_unset_no_errors(Pihole):
    '''
    confirms unset binary variable does not download FTL engine
    '''
    download_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLinstall
    ''')
    expected_stdout = cross_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    error1 = 'Error: URL https://github.com/pi-hole/FTL/releases/download/'
    assert error1 in download_binary.stdout
    error2 = 'not found'
    assert error2 in download_binary.stdout


def test_FTL_binary_installed_and_responsive_no_errors(Pihole):
    '''
    confirms FTL binary is copied and functional in installed location
    '''
    installed_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    FTLdetect
    pihole-FTL version
    ''')
    expected_stdout = 'v'
    assert expected_stdout in installed_binary.stdout


# def test_FTL_support_files_installed(Pihole):
#     '''
#     confirms FTL support files are installed
#     '''
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
    '''
    confirms IPv6 blocking is disabled for Link-local address
    '''
    # mock ip -6 address to return Link-local address
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 fe80::d210:52fa:fe00:7ad7/64 scope link',
                '0'
            )
        },
        Pihole
    )
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = ('Unable to find IPv6 ULA/GUA address, '
                       'IPv6 adblocking will not be enabled')
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_only_ULA(Pihole):
    '''
    confirms IPv6 blocking is enabled for ULA addresses
    '''
    # mock ip -6 address to return ULA address
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Pihole
    )
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_only_GUA(Pihole):
    '''
    confirms IPv6 blocking is enabled for GUA addresses
    '''
    # mock ip -6 address to return GUA address
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Pihole
    )
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 GUA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_GUA_ULA_test(Pihole):
    '''
    confirms IPv6 blocking is enabled for GUA and ULA addresses
    '''
    # mock ip -6 address to return GUA and ULA addresses
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global\n'
                'inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Pihole
    )
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_ULA_GUA_test(Pihole):
    '''
    confirms IPv6 blocking is enabled for GUA and ULA addresses
    '''
    # mock ip -6 address to return ULA and GUA addresses
    mock_command_2(
        'ip',
        {
            '-6 address': (
                'inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global\n'
                'inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global',
                '0'
            )
        },
        Pihole
    )
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    useIPv6dialog
    ''')
    expected_stdout = 'Found IPv6 ULA address, using it for blocking IPv6 ads'
    assert expected_stdout in detectPlatform.stdout
