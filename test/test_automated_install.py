import pytest
from textwrap import dedent
import re
from .conftest import (
    SETUPVARS,
    tick_box,
    info_box,
    cross_box,
    mock_command,
    mock_command_run,
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
    umask 0027
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


def get_directories_recursive(Pihole, directory):
    if directory is None:
        return directory
    ls = Pihole.run('ls -d {}'.format(directory + '/*/'))
    directories = list(filter(bool, ls.stdout.splitlines()))
    dirs = directories
    for directory in directories:
        dir_rec = get_directories_recursive(Pihole, directory)
        if isinstance(dir_rec, str):
            dirs.extend([dir_rec])
        else:
            dirs.extend(dir_rec)
    return dirs


def test_installPihole_fresh_install_readableFiles(Pihole):
    '''
    confirms all neccessary files are readable by pihole user
    '''
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    # mock systemctl to not start lighttpd and FTL
    mock_command_2(
        'systemctl',
        {
            'enable lighttpd': (
                '',
                '0'
            ),
            'restart lighttpd': (
                '',
                '0'
            ),
            'start lighttpd': (
                '',
                '0'
            ),
            'enable pihole-FTL': (
                '',
                '0'
            ),
            'restart pihole-FTL': (
                '',
                '0'
            ),
            'start pihole-FTL': (
                '',
                '0'
            ),
            '*': (
                'echo "systemctl call with $@"',
                '0'
            ),
        },
        Pihole
    )
    # try to install man
    Pihole.run('command -v apt-get > /dev/null && apt-get install -qq man')
    Pihole.run('command -v dnf > /dev/null && dnf install -y man')
    Pihole.run('command -v yum > /dev/null && yum install -y man')
    # create configuration file
    setup_var_file = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k, v in SETUPVARS.items():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "INSTALL_WEB_SERVER=true\n"
    setup_var_file += "INSTALL_WEB_INTERFACE=true\n"
    setup_var_file += "EOF\n"
    Pihole.run(setup_var_file)
    install = Pihole.run('''
    export TERM=xterm
    export DEBIAN_FRONTEND=noninteractive
    umask 0027
    runUnattended=true
    useUpdateVars=true
    source /opt/pihole/basic-install.sh > /dev/null
    runUnattended=true
    useUpdateVars=true
    main
    ''')
    assert 0 == install.rc
    maninstalled = True
    if (info_box + ' man not installed') in install.stdout:
        maninstalled = False
    piholeuser = 'pihole'
    exit_status_success = 0
    test_cmd = 'su --shell /bin/bash --command "test -{0} {1}" -p {2}'
    # check files in /etc/pihole for read, write and execute permission
    check_etc = test_cmd.format('r', '/etc/pihole', piholeuser)
    actual_rc = Pihole.run(check_etc).rc
    assert exit_status_success == actual_rc
    check_etc = test_cmd.format('x', '/etc/pihole', piholeuser)
    actual_rc = Pihole.run(check_etc).rc
    assert exit_status_success == actual_rc
    # readable and writable dhcp.leases
    check_leases = test_cmd.format('r', '/etc/pihole/dhcp.leases', piholeuser)
    actual_rc = Pihole.run(check_leases).rc
    assert exit_status_success == actual_rc
    check_leases = test_cmd.format('w', '/etc/pihole/dhcp.leases', piholeuser)
    actual_rc = Pihole.run(check_leases).rc
    # readable dns-servers.conf
    assert exit_status_success == actual_rc
    check_servers = test_cmd.format(
        'r', '/etc/pihole/dns-servers.conf', piholeuser)
    actual_rc = Pihole.run(check_servers).rc
    assert exit_status_success == actual_rc
    # readable GitHubVersions
    check_version = test_cmd.format(
        'r', '/etc/pihole/GitHubVersions', piholeuser)
    actual_rc = Pihole.run(check_version).rc
    assert exit_status_success == actual_rc
    # readable install.log
    check_install = test_cmd.format(
        'r', '/etc/pihole/install.log', piholeuser)
    actual_rc = Pihole.run(check_install).rc
    assert exit_status_success == actual_rc
    # readable localbranches
    check_localbranch = test_cmd.format(
        'r', '/etc/pihole/localbranches', piholeuser)
    actual_rc = Pihole.run(check_localbranch).rc
    assert exit_status_success == actual_rc
    # readable localversions
    check_localversion = test_cmd.format(
        'r', '/etc/pihole/localversions', piholeuser)
    actual_rc = Pihole.run(check_localversion).rc
    assert exit_status_success == actual_rc
    # readable logrotate
    check_logrotate = test_cmd.format(
        'r', '/etc/pihole/logrotate', piholeuser)
    actual_rc = Pihole.run(check_logrotate).rc
    assert exit_status_success == actual_rc
    # readable macvendor.db
    check_macvendor = test_cmd.format(
        'r', '/etc/pihole/macvendor.db', piholeuser)
    actual_rc = Pihole.run(check_macvendor).rc
    assert exit_status_success == actual_rc
    # readable and writeable pihole-FTL.conf
    check_FTLconf = test_cmd.format(
        'r', '/etc/pihole/pihole-FTL.conf', piholeuser)
    actual_rc = Pihole.run(check_FTLconf).rc
    assert exit_status_success == actual_rc
    check_FTLconf = test_cmd.format(
        'w', '/etc/pihole/pihole-FTL.conf', piholeuser)
    actual_rc = Pihole.run(check_FTLconf).rc
    assert exit_status_success == actual_rc
    # readable setupVars.conf
    check_setup = test_cmd.format(
        'r', '/etc/pihole/setupVars.conf', piholeuser)
    actual_rc = Pihole.run(check_setup).rc
    assert exit_status_success == actual_rc
    # check dnsmasq files
    # readable /etc/dnsmasq.conf
    check_dnsmasqconf = test_cmd.format(
        'r', '/etc/dnsmasq.conf', piholeuser)
    actual_rc = Pihole.run(check_dnsmasqconf).rc
    assert exit_status_success == actual_rc
    # readable /etc/dnsmasq.d/01-pihole.conf
    check_dnsmasqconf = test_cmd.format(
        'r', '/etc/dnsmasq.d', piholeuser)
    actual_rc = Pihole.run(check_dnsmasqconf).rc
    assert exit_status_success == actual_rc
    check_dnsmasqconf = test_cmd.format(
        'x', '/etc/dnsmasq.d', piholeuser)
    actual_rc = Pihole.run(check_dnsmasqconf).rc
    assert exit_status_success == actual_rc
    check_dnsmasqconf = test_cmd.format(
        'r', '/etc/dnsmasq.d/01-pihole.conf', piholeuser)
    actual_rc = Pihole.run(check_dnsmasqconf).rc
    assert exit_status_success == actual_rc
    # check readable and executable /etc/init.d/pihole-FTL
    check_init = test_cmd.format(
        'x', '/etc/init.d/pihole-FTL', piholeuser)
    actual_rc = Pihole.run(check_init).rc
    assert exit_status_success == actual_rc
    check_init = test_cmd.format(
        'r', '/etc/init.d/pihole-FTL', piholeuser)
    actual_rc = Pihole.run(check_init).rc
    assert exit_status_success == actual_rc
    # check readable /etc/lighttpd/lighttpd.conf
    check_lighttpd = test_cmd.format(
        'r', '/etc/lighttpd/lighttpd.conf', piholeuser)
    actual_rc = Pihole.run(check_lighttpd).rc
    assert exit_status_success == actual_rc
    # check readable and executable manpages
    if maninstalled is True:
        check_man = test_cmd.format(
            'x', '/usr/local/share/man', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'r', '/usr/local/share/man', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'x', '/usr/local/share/man/man8', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'r', '/usr/local/share/man/man8', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'x', '/usr/local/share/man/man5', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'r', '/usr/local/share/man/man5', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'r', '/usr/local/share/man/man8/pihole.8', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'r', '/usr/local/share/man/man8/pihole-FTL.8', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            'r', '/usr/local/share/man/man5/pihole-FTL.conf.5', piholeuser)
        actual_rc = Pihole.run(check_man).rc
        assert exit_status_success == actual_rc
    # check not readable sudoers file
    # TODO: directory may be readable?
    # check_sudo = test_cmd.format(
    #     'x', '/etc/sudoers.d/', piholeuser)
    # actual_rc = Pihole.run(check_sudo).rc
    # assert exit_status_success != actual_rc
    # check_sudo = test_cmd.format(
    #     'r', '/etc/sudoers.d/', piholeuser)
    # actual_rc = Pihole.run(check_sudo).rc
    # assert exit_status_success != actual_rc
    check_sudo = test_cmd.format(
        'r', '/etc/sudoers.d/pihole', piholeuser)
    actual_rc = Pihole.run(check_sudo).rc
    assert exit_status_success != actual_rc
    # check not readable cron file
    check_sudo = test_cmd.format(
        'x', '/etc/cron.d/', piholeuser)
    actual_rc = Pihole.run(check_sudo).rc
    assert exit_status_success == actual_rc
    check_sudo = test_cmd.format(
        'r', '/etc/cron.d/', piholeuser)
    actual_rc = Pihole.run(check_sudo).rc
    assert exit_status_success == actual_rc
    check_sudo = test_cmd.format(
        'r', '/etc/cron.d/pihole', piholeuser)
    actual_rc = Pihole.run(check_sudo).rc
    assert exit_status_success == actual_rc
    directories = get_directories_recursive(Pihole, '/etc/.pihole/')
    for directory in directories:
        check_pihole = test_cmd.format('r', directory, piholeuser)
        actual_rc = Pihole.run(check_pihole).rc
        check_pihole = test_cmd.format('x', directory, piholeuser)
        actual_rc = Pihole.run(check_pihole).rc
        findfiles = 'find "{}" -maxdepth 1 -type f  -exec echo {{}} \\;;'
        filelist = Pihole.run(findfiles.format(directory))
        files = list(filter(bool, filelist.stdout.splitlines()))
        for file in files:
            check_pihole = test_cmd.format('r', file, piholeuser)
            actual_rc = Pihole.run(check_pihole).rc


@pytest.mark.parametrize("test_webpage", [True])
def test_installPihole_fresh_install_readableBlockpage(Pihole, test_webpage):
    '''
    confirms all web page assets from Core repo are readable
    by $LIGHTTPD_USER on a fresh build
    '''
    # TODO: also add IP address from setupVars?
    # TODO: pi.hole can not be resolved because of some error in FTL or resolved
    piholeWebpage = [
        "http://127.0.0.1/admin",
        "http://pi.hole/admin"
    ]
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    # mock systemctl to start lighttpd and FTL
    ligthttpdcommand = dedent(r'''\"\"
        echo 'starting lighttpd with {}'
        if [ command -v "apt-get" >/dev/null 2>&1 ]; then
            LIGHTTPD_USER="www-data"
            LIGHTTPD_GROUP="www-data"
        else
            LIGHTTPD_USER="lighttpd"
            LIGHTTPD_GROUP="lighttpd"
        fi
        mkdir -p "{run}"
        chown {usergroup} "{run}"
        mkdir -p "{cache}"
        chown {usergroup} "/var/cache"
        chown {usergroup} "{cache}"
        mkdir -p "{compress}"
        chown {usergroup} "{compress}"
        mkdir -p "{uploads}"
        chown {usergroup} "{uploads}"
        # TODO: changing these permissions might be wrong
        chmod 0777 /var
        chmod 0777 /var/cache
        chmod 0777 "{cache}"
        find "{run}" -type d -exec chmod 0777 {chmodarg} \;;
        find "{run}" -type f -exec chmod 0666 {chmodarg} \;;
        find "{compress}" -type d -exec chmod 0777 {chmodarg} \;;
        find "{compress}" -type f -exec chmod 0666 {chmodarg} \;;
        find "{uploads}" -type d -exec chmod 0777 {chmodarg} \;;
        find "{uploads}" -type f -exec chmod 0666 {chmodarg} \;;
        /usr/sbin/lighttpd -tt -f '{config}'
        /usr/sbin/lighttpd -f '{config}'
        echo \"\"'''.format(
            '{}',
            usergroup='${{LIGHTTPD_USER}}:${{LIGHTTPD_GROUP}}',
            chmodarg='{{}}',
            config='/etc/lighttpd/lighttpd.conf',
            run='/var/run/lighttpd',
            cache='/var/cache/lighttpd',
            uploads='/var/cache/lighttpd/uploads',
            compress='/var/cache/lighttpd/compress'
        )
    )
    FTLcommand = dedent('''\"\"
        set -x
        /etc/init.d/pihole-FTL restart
        echo \"\"''')
    mock_command_run(
        'systemctl',
        {
            'enable lighttpd': (
                '',
                '0'
            ),
            'restart lighttpd': (
                ligthttpdcommand.format('restart'),
                '0'
            ),
            'start lighttpd': (
                ligthttpdcommand.format('start'),
                '0'
            ),
            'enable pihole-FTL': (
                '',
                '0'
            ),
            'restart pihole-FTL': (
                FTLcommand,
                '0'
            ),
            'start pihole-FTL': (
                FTLcommand,
                '0'
            ),
            '*': (
                'echo "systemctl call with $@"',
                '0'
            ),
        },
        Pihole
    )
    # create configuration file
    setup_var_file = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k, v in SETUPVARS.items():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "INSTALL_WEB_SERVER=true\n"
    setup_var_file += "INSTALL_WEB_INTERFACE=true\n"
    setup_var_file += "IPV4_ADDRESS=127.0.0.1\n"
    setup_var_file += "EOF\n"
    Pihole.run(setup_var_file)
    installWeb = Pihole.run('''
    export TERM=xterm
    export DEBIAN_FRONTEND=noninteractive
    umask 0027
    runUnattended=true
    useUpdateVars=true
    source /opt/pihole/basic-install.sh > /dev/null
    runUnattended=true
    useUpdateVars=true
    main
    echo "LIGHTTPD_USER=${LIGHTTPD_USER}"
    echo "webroot=${webroot}"
    echo "INSTALL_WEB_INTERFACE=${INSTALL_WEB_INTERFACE}"
    echo "INSTALL_WEB_SERVER=${INSTALL_WEB_SERVER}"
    ''')
    assert 0 == installWeb.rc
    b = Pihole.run('cat /etc/resolv.conf');
    print(b.stdout)
    b = Pihole.run('ls -la /etc/pihole');
    print(b.stdout)
    b = Pihole.run('ls -la /etc/sudoers.d');
    print(b.stdout)
    b = Pihole.run('command -v apt-get && apt-get install -qq --no-install-recommends e2fsprogs');
    print(b.stdout)
    b = Pihole.run('command -v dnf && dnf install -y e2fsprogs');
    print(b.stdout)
    b = Pihole.run('command -v yum && yum install -y e2fsprogs');
    print(b.stdout)
    b = Pihole.run('ls -la $(which pihole-FTL)');
    print(b.stdout)
    b = Pihole.run('lsattr $(which pihole-FTL)');
    print(b.stdout)
    b = Pihole.run('lsattr $(which pihole-FTL)/../');
    print(b.stdout)
    b = Pihole.run('chmod a+x $(which pihole-FTL)');
    print(b.stdout)
    b = Pihole.run('pihole-FTL version');
    print(b.stdout)
    b = Pihole.run('pihole-FTL tag');
    print(b.stdout)
    b = Pihole.run('pihole-FTL branch');
    print(b.stdout)
    b = Pihole.run('pihole-FTL test');
    print(b.stdout)
    b = Pihole.run('ldd $(which pihole-FTL)');
    print(b.stdout)
    b = Pihole.run('LD_DEBUG=help pihole-FTL version');
    print(b.stdout)
    b = Pihole.run('file pihole-FTL');
    print(b.stdout)
    b = Pihole.run('cat /var/log/pihole.log');
    print(b.stdout)
    b = Pihole.run('cat /etc/pihole/install.log');
    print(b.stdout)
    piholeuser = 'pihole'
    webuser = ''
    user = re.findall(
        r"^\s*LIGHTTPD_USER=.*$", installWeb.stdout, re.MULTILINE)
    for match in user:
        webuser = match.replace('LIGHTTPD_USER=', '').strip()
    webroot = ''
    user = re.findall(
        r"^\s*webroot=.*$", installWeb.stdout, re.MULTILINE)
    for match in user:
        webroot = match.replace('webroot=', '').strip()
    if not webroot.strip():
        webroot = '/var/www/html'
    installWebInterface = True
    interface = re.findall(
        r"^\s*INSTALL_WEB_INTERFACE=.*$", installWeb.stdout, re.MULTILINE)
    for match in interface:
        testvalue = match.replace('INSTALL_WEB_INTERFACE=', '').strip().lower()
        if not testvalue.strip():
            installWebInterface = testvalue == "true"
    installWebServer = True
    server = re.findall(
        r"^\s*INSTALL_WEB_SERVER=.*$", installWeb.stdout, re.MULTILINE)
    for match in server:
        testvalue = match.replace('INSTALL_WEB_SERVER=', '').strip().lower()
        if not testvalue.strip():
            installWebServer = testvalue == "true"
    # if webserver install was not requested
    # at least pihole must be able to read files
    if installWebServer is False:
        webuser = piholeuser
    exit_status_success = 0
    test_cmd = 'su --shell /bin/bash --command "test -{0} {1}" -p {2}'
    # check files that need a running FTL to be created
    # readable and writeable pihole-FTL.db
    # TODO: is created by FTL and if downloading fails this fails too?
    check_FTLconf = test_cmd.format(
        'r', '/etc/pihole/pihole-FTL.db', piholeuser)
    actual_rc = Pihole.run(check_FTLconf).rc
    assert exit_status_success == actual_rc
    check_FTLconf = test_cmd.format(
        'w', '/etc/pihole/pihole-FTL.db', piholeuser)
    actual_rc = Pihole.run(check_FTLconf).rc
    assert exit_status_success == actual_rc
    # check directories above $webroot for read and execute permission
    check_var = test_cmd.format('r', '/var', webuser)
    actual_rc = Pihole.run(check_var).rc
    assert exit_status_success == actual_rc
    check_var = test_cmd.format('x', '/var', webuser)
    actual_rc = Pihole.run(check_var).rc
    assert exit_status_success == actual_rc
    check_www = test_cmd.format('r', '/var/www', webuser)
    actual_rc = Pihole.run(check_www).rc
    assert exit_status_success == actual_rc
    check_www = test_cmd.format('x', '/var/www', webuser)
    actual_rc = Pihole.run(check_www).rc
    assert exit_status_success == actual_rc
    check_html = test_cmd.format('r', '/var/www/html', webuser)
    actual_rc = Pihole.run(check_html).rc
    assert exit_status_success == actual_rc
    check_html = test_cmd.format('x', '/var/www/html', webuser)
    actual_rc = Pihole.run(check_html).rc
    assert exit_status_success == actual_rc
    # check directories below $webroot for read and execute permission
    check_admin = test_cmd.format('r', webroot + '/admin', webuser)
    actual_rc = Pihole.run(check_admin).rc
    assert exit_status_success == actual_rc
    check_admin = test_cmd.format('x', webroot + '/admin', webuser)
    actual_rc = Pihole.run(check_admin).rc
    assert exit_status_success == actual_rc
    directories = get_directories_recursive(Pihole, webroot + '/admin/*/')
    for directory in directories:
        check_pihole = test_cmd.format('r', directory, webuser)
        actual_rc = Pihole.run(check_pihole).rc
        check_pihole = test_cmd.format('x', directory, webuser)
        actual_rc = Pihole.run(check_pihole).rc
        findfiles = 'find "{}" -maxdepth 1 -type f  -exec echo {{}} \\;;'
        filelist = Pihole.run(findfiles.format(directory))
        files = list(filter(bool, filelist.stdout.splitlines()))
        for file in files:
            check_pihole = test_cmd.format('r', file, webuser)
            actual_rc = Pihole.run(check_pihole).rc
    # TODO: which other files have to be checked?
    # check web interface files
    # change nameserver to pi-hole
    # setting nameserver in /etc/resolv.conf to pi-hole does
    # not work here because of the way docker uses this file
    ns = Pihole.run("sed -i 's/nameserver.*/nameserver 127.0.0.1/' /etc/resolv.conf")
    pihole_is_ns = ns.rc == 0
    if installWebInterface is True:
        # TODO: login into admin interface?
        passwordcommand = 'grep "WEBPASSWORD" -c "/etc/pihole/setupVars.conf"'
        passwd = Pihole.run(passwordcommand)
        webpassword = passwd.stdout.strip()
        check_pihole = test_cmd.format('r', webroot + '/pihole', webuser)
        actual_rc = Pihole.run(check_pihole).rc
        assert exit_status_success == actual_rc
        check_pihole = test_cmd.format('x', webroot + '/pihole', webuser)
        actual_rc = Pihole.run(check_pihole).rc
        assert exit_status_success == actual_rc
        # check most important files in $webroot for read permission
        check_index = test_cmd.format(
            'r', webroot + '/pihole/index.php', webuser)
        actual_rc = Pihole.run(check_index).rc
        assert exit_status_success == actual_rc
        check_blockpage = test_cmd.format(
            'r', webroot + '/pihole/blockingpage.css', webuser)
        actual_rc = Pihole.run(check_blockpage).rc
        assert exit_status_success == actual_rc
        if test_webpage is True:
            # check webpage for unreadable files
            noPHPfopen = re.compile(
                (r"PHP Error(%d+):\s+fopen([^)]+):\s+" +
                    r"failed to open stream: " +
                    r"Permission denied in"),
                re.I)
            # using cURL option --dns-servers is not possible
            status = (
                'curl -s --head "{}" | ' +
                'head -n 1 | ' +
                'grep "HTTP/1.[01] [23].." > /dev/null')
            pagecontent = 'curl --verbose -L "{}"'
            for page in piholeWebpage:
                # d = Pihole.run("echo {} | sed -e 's|http://||' -e 's|/.*||'".format(page))
                # print(d.stdout)
                dig = Pihole.run("dig @127.0.0.1 $(echo {} | sed -e 's|http://||' -e 's|/.*||')".format(page))
                print(dig.stdout)
                dig = Pihole.run("nslookup $(echo {} | sed -e 's|http://||' -e 's|/.*||') 127.0.0.1 | grep '^Address:' | head -n 2 | sed -e 's/Address: *//'".format(page))
                print(dig.stdout)
                if dig.rc == 0 or pihole_is_ns:
                    # check HTTP status of blockpage
                    actual_rc = Pihole.run(status.format(page))
                    assert exit_status_success == actual_rc.rc
                    actual_output = Pihole.run(pagecontent.format(page))
                    assert noPHPfopen.match(actual_output.stdout) is None


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
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
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
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
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
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
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
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    ''')
    expected_stdout = 'Not able to detect architecture (unknown: mips)'
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
