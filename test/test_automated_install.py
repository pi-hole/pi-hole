from textwrap import dedent
import re
from .conftest import (
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
    for k, v in SETUPVARS.items():
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

    for k, v in SETUPVARS.items():
        assert "{}={}".format(k, v) in output


def test_setupVars_saved_to_file(Pihole):
    '''
    confirm saved settings are written to a file for future updates to re-use
    '''
    # dedent works better with this and padding matching script below
    set_setup_vars = '\n'
    for k, v in SETUPVARS.items():
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

    for k, v in SETUPVARS.items():
        assert "{}={}".format(k, v) in output


def test_selinux_not_detected(Pihole):
    '''
    confirms installer continues when SELinux configuration file does not exist
    '''
    check_selinux = Pihole.run('''
    rm -f /etc/selinux/config
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = info_box + ' SELinux not detected'
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
    expected_stdout = info_box + ' Backing up index.lighttpd.html'
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
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected AArch64 (64 Bit ARM) processor'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv4t_no_errors(Pihole):
    '''
    confirms only armv4t package is downloaded for FTL engine
    '''
    # mock uname to return armv4t platform
    mock_command('uname', {'-m': ('armv4t', '0')}, Pihole)
    # mock ldd to respond with ld-linux shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (' Detected ARMv4 processor')
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv5te_no_errors(Pihole):
    '''
    confirms only armv5te package is downloaded for FTL engine
    '''
    # mock uname to return armv5te platform
    mock_command('uname', {'-m': ('armv5te', '0')}, Pihole)
    # mock ldd to respond with ld-linux shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (' Detected ARMv5 (or newer) processor')
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv6l_no_errors(Pihole):
    '''
    confirms only armv6l package is downloaded for FTL engine
    '''
    # mock uname to return armv6l platform
    mock_command('uname', {'-m': ('armv6l', '0')}, Pihole)
    # mock ldd to respond with ld-linux-armhf shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (' Detected ARMv6 processor '
                                  '(with hard-float support)')
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv7l_no_errors(Pihole):
    '''
    confirms only armv7l package is downloaded for FTL engine
    '''
    # mock uname to return armv7l platform
    mock_command('uname', {'-m': ('armv7l', '0')}, Pihole)
    # mock ldd to respond with ld-linux-armhf shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (' Detected ARMv7 processor '
                                  '(with hard-float support)')
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv8a_no_errors(Pihole):
    '''
    confirms only armv8a package is downloaded for FTL engine
    '''
    # mock uname to return armv8a platform
    mock_command('uname', {'-m': ('armv8a', '0')}, Pihole)
    # mock ldd to respond with ld-linux-armhf shared library
    mock_command('ldd', {'/bin/ls': ('/lib/ld-linux-armhf.so.3', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected ARMv8 (or newer) processor'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_x86_64_no_errors(Pihole):
    '''
    confirms only x86_64 package is downloaded for FTL engine
    '''
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = info_box + ' FTL Checks...'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Detected x86_64 processor'
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_unknown_no_errors(Pihole):
    ''' confirms only generic package is downloaded for FTL engine '''
    # mock uname to return generic platform
    mock_command('uname', {'-m': ('mips', '0')}, Pihole)
    detectPlatform = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = 'Not able to detect processor (unknown: mips)'
    assert expected_stdout in detectPlatform.stdout


def test_FTL_download_aarch64_no_errors(Pihole):
    '''
    confirms only aarch64 package is downloaded for FTL engine
    '''
    # mock whiptail answers and ensure installer dependencies
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    install_dependent_packages ${INSTALLER_DEPS[@]}
    ''')
    download_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    FTLinstall "pihole-FTL-aarch64-linux-gnu"
    ''')
    expected_stdout = tick_box + ' Downloading and Installing FTL'
    assert expected_stdout in download_binary.stdout
    assert 'error' not in download_binary.stdout.lower()


def test_FTL_binary_installed_and_responsive_no_errors(Pihole):
    '''
    confirms FTL binary is copied and functional in installed location
    '''
    installed_binary = Pihole.run('''
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
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


def test_validate_ip_valid(Pihole):
    '''
    Given a valid IP address, valid_ip returns success
    '''

    output = Pihole.run('''
    source /opt/pihole/basic-install.sh
    valid_ip "192.168.1.1"
    ''')

    assert output.rc == 0


def test_validate_ip_invalid_octet(Pihole):
    '''
    Given an invalid IP address (large octet), valid_ip returns an error
    '''

    output = Pihole.run('''
    source /opt/pihole/basic-install.sh
    valid_ip "1092.168.1.1"
    ''')

    assert output.rc == 1


def test_validate_ip_invalid_letters(Pihole):
    '''
    Given an invalid IP address (contains letters), valid_ip returns an error
    '''

    output = Pihole.run('''
    source /opt/pihole/basic-install.sh
    valid_ip "not an IP"
    ''')

    assert output.rc == 1


def test_os_check_fails(Pihole):
    ''' Confirms install fails on unsupported OS '''
    Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    install_dependent_packages ${INSTALLER_DEPS[@]}
    cat <<EOT > /etc/os-release
    ID=UnsupportedOS
    VERSION_ID="2"
    EOT
    ''')
    detectOS = Pihole.run('''t
    source /opt/pihole/basic-install.sh
    os_check
    ''')
    expected_stdout = 'Unsupported OS detected: UnsupportedOS'
    assert expected_stdout in detectOS.stdout


def test_os_check_passes(Pihole):
    ''' Confirms OS meets the requirements '''
    Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    install_dependent_packages ${INSTALLER_DEPS[@]}
    ''')
    detectOS = Pihole.run('''
    source /opt/pihole/basic-install.sh
    os_check
    ''')
    expected_stdout = 'Supported OS detected'
    assert expected_stdout in detectOS.stdout
