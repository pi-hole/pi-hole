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
    mock_command_passthrough,
    run_script,
)


def test_supported_package_manager(host):
    """
    confirm installer exits when no supported package manager found
    """
    # break supported package managers
    host.run("rm -rf /usr/bin/apt-get")
    host.run("rm -rf /usr/bin/rpm")
    package_manager_detect = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    """
    )
    expected_stdout = cross_box + " No supported package manager found"
    assert expected_stdout in package_manager_detect.stdout
    # assert package_manager_detect.rc == 1


def test_setupVars_are_sourced_to_global_scope(host):
    """
    currently update_dialogs sources setupVars with a dot,
    then various other functions use the variables.
    This confirms the sourced variables are in scope between functions
    """
    setup_var_file = "cat <<EOF> /etc/pihole/setupVars.conf\n"
    for k, v in SETUPVARS.items():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "EOF\n"
    host.run(setup_var_file)

    script = dedent(
        """\
    set -e
    printSetupVars() {
        # Currently debug test function only
        echo "Outputting sourced variables"
        echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
        echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
        echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
    }
    update_dialogs() {
        . /etc/pihole/setupVars.conf
    }
    update_dialogs
    printSetupVars
    """
    )

    output = run_script(host, script).stdout

    for k, v in SETUPVARS.items():
        assert "{}={}".format(k, v) in output


def test_selinux_not_detected(host):
    """
    confirms installer continues when SELinux configuration file does not exist
    """
    check_selinux = host.run(
        """
    rm -f /etc/selinux/config
    source /opt/pihole/basic-install.sh
    checkSelinux
    """
    )
    expected_stdout = info_box + " SELinux not detected"
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def get_directories_recursive(host, directory):
    if directory is None:
        return directory
    # returns all non-hidden subdirs of 'directory'
    dirs_raw = host.run("find {} -type d -not -path '*/.*'".format(directory))
    dirs = list(filter(bool, dirs_raw.stdout.splitlines()))
    return dirs


def test_installPihole_fresh_install_readableFiles(host):
    """
    confirms all necessary files are readable by pihole user
    """
    # dialog returns Cancel for user prompt
    mock_command("dialog", {"*": ("", "0")}, host)
    # mock git pull
    mock_command_passthrough("git", {"pull": ("", "0")}, host)
    # mock systemctl to not start lighttpd and FTL
    mock_command_2(
        "systemctl",
        {
            "enable pihole-FTL": ("", "0"),
            "restart pihole-FTL": ("", "0"),
            "start pihole-FTL": ("", "0"),
            "*": ('echo "systemctl call with $@"', "0"),
        },
        host,
    )
    # try to install man
    host.run("command -v apt-get > /dev/null && apt-get install -qq man")
    host.run("command -v dnf > /dev/null && dnf install -y man")
    host.run("command -v yum > /dev/null && yum install -y man")
    # create configuration file
    setup_var_file = "cat <<EOF> /etc/pihole/setupVars.conf\n"
    for k, v in SETUPVARS.items():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "INSTALL_WEB_INTERFACE=true\n"
    setup_var_file += "EOF\n"
    host.run(setup_var_file)
    install = host.run(
        """
    export TERM=xterm
    export DEBIAN_FRONTEND=noninteractive
    umask 0027
    runUnattended=true
    useUpdateVars=true
    source /opt/pihole/basic-install.sh > /dev/null
    runUnattended=true
    useUpdateVars=true
    main
    """
    )
    assert 0 == install.rc
    maninstalled = True
    if (info_box + " man not installed") in install.stdout:
        maninstalled = False
    if (info_box + " man pages not installed") in install.stdout:
        maninstalled = False
    piholeuser = "pihole"
    exit_status_success = 0
    test_cmd = 'su --shell /bin/bash --command "test -{0} {1}" -p {2}'
    # check files in /etc/pihole for read, write and execute permission
    check_etc = test_cmd.format("r", "/etc/pihole", piholeuser)
    actual_rc = host.run(check_etc).rc
    assert exit_status_success == actual_rc
    check_etc = test_cmd.format("x", "/etc/pihole", piholeuser)
    actual_rc = host.run(check_etc).rc
    assert exit_status_success == actual_rc
    # readable and writable dhcp.leases
    check_leases = test_cmd.format("r", "/etc/pihole/dhcp.leases", piholeuser)
    actual_rc = host.run(check_leases).rc
    assert exit_status_success == actual_rc
    check_leases = test_cmd.format("w", "/etc/pihole/dhcp.leases", piholeuser)
    actual_rc = host.run(check_leases).rc
    # readable dns-servers.conf
    assert exit_status_success == actual_rc
    check_servers = test_cmd.format("r", "/etc/pihole/dns-servers.conf", piholeuser)
    actual_rc = host.run(check_servers).rc
    assert exit_status_success == actual_rc
    # readable install.log
    check_install = test_cmd.format("r", "/etc/pihole/install.log", piholeuser)
    actual_rc = host.run(check_install).rc
    assert exit_status_success == actual_rc
    # readable versions
    check_localversion = test_cmd.format("r", "/etc/pihole/versions", piholeuser)
    actual_rc = host.run(check_localversion).rc
    assert exit_status_success == actual_rc
    # readable logrotate
    check_logrotate = test_cmd.format("r", "/etc/pihole/logrotate", piholeuser)
    actual_rc = host.run(check_logrotate).rc
    assert exit_status_success == actual_rc
    # readable macvendor.db
    check_macvendor = test_cmd.format("r", "/etc/pihole/macvendor.db", piholeuser)
    actual_rc = host.run(check_macvendor).rc
    assert exit_status_success == actual_rc
    # readable and writeable pihole-FTL.conf
    check_FTLconf = test_cmd.format("r", "/etc/pihole/pihole-FTL.conf", piholeuser)
    actual_rc = host.run(check_FTLconf).rc
    assert exit_status_success == actual_rc
    check_FTLconf = test_cmd.format("w", "/etc/pihole/pihole-FTL.conf", piholeuser)
    actual_rc = host.run(check_FTLconf).rc
    assert exit_status_success == actual_rc
    # readable setupVars.conf
    check_setup = test_cmd.format("r", "/etc/pihole/setupVars.conf", piholeuser)
    actual_rc = host.run(check_setup).rc
    assert exit_status_success == actual_rc
    # check readable and executable /etc/init.d/pihole-FTL
    check_init = test_cmd.format("x", "/etc/init.d/pihole-FTL", piholeuser)
    actual_rc = host.run(check_init).rc
    assert exit_status_success == actual_rc
    check_init = test_cmd.format("r", "/etc/init.d/pihole-FTL", piholeuser)
    actual_rc = host.run(check_init).rc
    assert exit_status_success == actual_rc
    # check readable and executable manpages
    if maninstalled is True:
        check_man = test_cmd.format("x", "/usr/local/share/man", piholeuser)
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format("r", "/usr/local/share/man", piholeuser)
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format("x", "/usr/local/share/man/man8", piholeuser)
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format("r", "/usr/local/share/man/man8", piholeuser)
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format("x", "/usr/local/share/man/man5", piholeuser)
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format("r", "/usr/local/share/man/man5", piholeuser)
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            "r", "/usr/local/share/man/man8/pihole.8", piholeuser
        )
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
        check_man = test_cmd.format(
            "r", "/usr/local/share/man/man8/pihole-FTL.8", piholeuser
        )
        actual_rc = host.run(check_man).rc
        assert exit_status_success == actual_rc
    # check not readable sudoers file
    check_sudo = test_cmd.format("r", "/etc/sudoers.d/pihole", piholeuser)
    actual_rc = host.run(check_sudo).rc
    assert exit_status_success != actual_rc
    # check not readable cron file
    check_sudo = test_cmd.format("x", "/etc/cron.d/", piholeuser)
    actual_rc = host.run(check_sudo).rc
    assert exit_status_success == actual_rc
    check_sudo = test_cmd.format("r", "/etc/cron.d/", piholeuser)
    actual_rc = host.run(check_sudo).rc
    assert exit_status_success == actual_rc
    check_sudo = test_cmd.format("r", "/etc/cron.d/pihole", piholeuser)
    actual_rc = host.run(check_sudo).rc
    assert exit_status_success == actual_rc
    directories = get_directories_recursive(host, "/etc/.pihole/")
    for directory in directories:
        check_pihole = test_cmd.format("r", directory, piholeuser)
        actual_rc = host.run(check_pihole).rc
        check_pihole = test_cmd.format("x", directory, piholeuser)
        actual_rc = host.run(check_pihole).rc
        findfiles = 'find "{}" -maxdepth 1 -type f  -exec echo {{}} \\;;'
        filelist = host.run(findfiles.format(directory))
        files = list(filter(bool, filelist.stdout.splitlines()))
        for file in files:
            check_pihole = test_cmd.format("r", file, piholeuser)
            actual_rc = host.run(check_pihole).rc


def test_update_package_cache_success_no_errors(host):
    """
    confirms package cache was updated without any errors
    """
    updateCache = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    update_package_cache
    """
    )
    expected_stdout = tick_box + " Update local cache of available packages"
    assert expected_stdout in updateCache.stdout
    assert "error" not in updateCache.stdout.lower()


def test_update_package_cache_failure_no_errors(host):
    """
    confirms package cache was not updated
    """
    mock_command("apt-get", {"update": ("", "1")}, host)
    updateCache = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    update_package_cache
    """
    )
    expected_stdout = cross_box + " Update local cache of available packages"
    assert expected_stdout in updateCache.stdout
    assert "Error: Unable to update package cache." in updateCache.stdout


def test_FTL_detect_aarch64_no_errors(host):
    """
    confirms only aarch64 package is downloaded for FTL engine
    """
    # mock uname to return aarch64 platform
    mock_command("uname", {"-m": ("aarch64", "0")}, host)
    # mock ldd to respond with aarch64 shared library
    mock_command(
        "ldd",
        {
            "/bin/sh": ("/lib/ld-linux-aarch64.so.1", "0"),
            "/usr/bin/sh": ("/lib/ld-linux-aarch64.so.1", "0"),
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Detected AArch64 (64 Bit ARM) processor"
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv4t_no_errors(host):
    """
    confirms only armv4t package is downloaded for FTL engine
    """
    # mock uname to return armv4t platform
    mock_command("uname", {"-m": ("armv4t", "0")}, host)
    # mock ldd to respond with armv4t shared library
    mock_command(
        "ldd",
        {
            "/bin/sh": ("/lib/ld-linux.so.3", "0"),
            "/usr/bin/sh": ("/lib/ld-linux.so.3", "0"),
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (" Detected ARMv4 processor")
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv5te_no_errors(host):
    """
    confirms only armv5te package is downloaded for FTL engine
    """
    # mock uname to return armv5te platform
    mock_command("uname", {"-m": ("armv5te", "0")}, host)
    # mock ldd to respond with ld-linux shared library
    mock_command(
        "ldd",
        {
            "/bin/sh": ("/lib/ld-linux.so.3", "0"),
            "/usr/bin/sh": ("/lib/ld-linux.so.3", "0"),
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (" Detected ARMv5 (or newer) processor")
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv6l_no_errors(host):
    """
    confirms only armv6l package is downloaded for FTL engine
    """
    # mock uname to return armv6l platform
    mock_command("uname", {"-m": ("armv6l", "0")}, host)
    # mock ldd to respond with ld-linux-armhf shared library
    mock_command(
        "ldd",
        {
            "/bin/sh": ("/lib/ld-linux-armhf.so.3", "0"),
            "/usr/bin/sh": ("/lib/ld-linux-armhf.so.3", "0"),
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (
        " Detected ARMv6 processor " "(with hard-float support)"
    )
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv7l_no_errors(host):
    """
    confirms only armv7l package is downloaded for FTL engine
    """
    # mock uname to return armv7l platform
    mock_command("uname", {"-m": ("armv7l", "0")}, host)
    # mock ldd to respond with ld-linux-armhf shared library
    mock_command(
        "ldd",
        {
            "/bin/sh": ("/lib/ld-linux-armhf.so.3", "0"),
            "/usr/bin/sh": ("/lib/ld-linux-armhf.so.3", "0"),
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + (
        " Detected ARMv7 processor " "(with hard-float support)"
    )
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_armv8a_no_errors(host):
    """
    confirms only armv8a package is downloaded for FTL engine
    """
    # mock uname to return armv8a platform
    mock_command("uname", {"-m": ("armv8a", "0")}, host)
    # mock ldd to respond with ld-linux-armhf shared library
    mock_command(
        "ldd",
        {
            "/bin/sh": ("/lib/ld-linux-armhf.so.3", "0"),
            "/usr/bin/sh": ("/lib/ld-linux-armhf.so.3", "0"),
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Detected ARMv8 (or newer) processor"
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_x86_64_no_errors(host):
    """
    confirms only x86_64 package is downloaded for FTL engine
    """
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = info_box + " FTL Checks..."
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Detected x86_64 processor"
    assert expected_stdout in detectPlatform.stdout
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_detect_unknown_no_errors(host):
    """confirms only generic package is downloaded for FTL engine"""
    # mock uname to return generic platform
    mock_command("uname", {"-m": ("mips", "0")}, host)
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    funcOutput=$(get_binary_name)
    binary="pihole-FTL${funcOutput##*pihole-FTL}"
    theRest="${funcOutput%pihole-FTL*}"
    FTLdetect "${binary}" "${theRest}"
    """
    )
    expected_stdout = "Not able to detect processor (unknown: mips)"
    assert expected_stdout in detectPlatform.stdout


def test_FTL_download_aarch64_no_errors(host):
    """
    confirms only aarch64 package is downloaded for FTL engine
    """
    # mock dialog answers and ensure installer dependencies
    mock_command("dialog", {"*": ("", "0")}, host)
    host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${INSTALLER_DEPS[@]}
    """
    )
    download_binary = host.run(
        """
    source /opt/pihole/basic-install.sh
    create_pihole_user
    FTLinstall "pihole-FTL-aarch64-linux-gnu"
    """
    )
    expected_stdout = tick_box + " Downloading and Installing FTL"
    assert expected_stdout in download_binary.stdout
    assert "error" not in download_binary.stdout.lower()


def test_FTL_binary_installed_and_responsive_no_errors(host):
    """
    confirms FTL binary is copied and functional in installed location
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
    version_check = host.run(
        """
    VERSION=$(pihole-FTL version)
    echo ${VERSION:0:1}
    """
    )
    expected_stdout = "v"
    assert expected_stdout in version_check.stdout


def test_IPv6_only_link_local(host):
    """
    confirms IPv6 blocking is disabled for Link-local address
    """
    # mock ip -6 address to return Link-local address
    mock_command_2(
        "ip",
        {"-6 address": ("inet6 fe80::d210:52fa:fe00:7ad7/64 scope link", "0")},
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    find_IPv6_information
    """
    )
    expected_stdout = "Unable to find IPv6 ULA/GUA address"
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_only_ULA(host):
    """
    confirms IPv6 blocking is enabled for ULA addresses
    """
    # mock ip -6 address to return ULA address
    mock_command_2(
        "ip",
        {
            "-6 address": (
                "inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global",
                "0",
            )
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    find_IPv6_information
    """
    )
    expected_stdout = "Found IPv6 ULA address"
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_only_GUA(host):
    """
    confirms IPv6 blocking is enabled for GUA addresses
    """
    # mock ip -6 address to return GUA address
    mock_command_2(
        "ip",
        {
            "-6 address": (
                "inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global",
                "0",
            )
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    find_IPv6_information
    """
    )
    expected_stdout = "Found IPv6 GUA address"
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_GUA_ULA_test(host):
    """
    confirms IPv6 blocking is enabled for GUA and ULA addresses
    """
    # mock ip -6 address to return GUA and ULA addresses
    mock_command_2(
        "ip",
        {
            "-6 address": (
                "inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global\n"
                "inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global",
                "0",
            )
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    find_IPv6_information
    """
    )
    expected_stdout = "Found IPv6 ULA address"
    assert expected_stdout in detectPlatform.stdout


def test_IPv6_ULA_GUA_test(host):
    """
    confirms IPv6 blocking is enabled for GUA and ULA addresses
    """
    # mock ip -6 address to return ULA and GUA addresses
    mock_command_2(
        "ip",
        {
            "-6 address": (
                "inet6 fda2:2001:5555:0:d210:52fa:fe00:7ad7/64 scope global\n"
                "inet6 2003:12:1e43:301:d210:52fa:fe00:7ad7/64 scope global",
                "0",
            )
        },
        host,
    )
    detectPlatform = host.run(
        """
    source /opt/pihole/basic-install.sh
    find_IPv6_information
    """
    )
    expected_stdout = "Found IPv6 ULA address"
    assert expected_stdout in detectPlatform.stdout


def test_validate_ip(host):
    """
    Tests valid_ip for various IP addresses
    """

    def test_address(addr, success=True):
        output = host.run(
            """
        source /opt/pihole/basic-install.sh
        valid_ip "{addr}"
        """.format(
                addr=addr
            )
        )

        assert output.rc == 0 if success else 1

    test_address("192.168.1.1")
    test_address("127.0.0.1")
    test_address("255.255.255.255")
    test_address("255.255.255.256", False)
    test_address("255.255.256.255", False)
    test_address("255.256.255.255", False)
    test_address("256.255.255.255", False)
    test_address("1092.168.1.1", False)
    test_address("not an IP", False)
    test_address("8.8.8.8#", False)
    test_address("8.8.8.8#0")
    test_address("8.8.8.8#1")
    test_address("8.8.8.8#42")
    test_address("8.8.8.8#888")
    test_address("8.8.8.8#1337")
    test_address("8.8.8.8#65535")
    test_address("8.8.8.8#65536", False)
    test_address("8.8.8.8#-1", False)
    test_address("00.0.0.0", False)
    test_address("010.0.0.0", False)
    test_address("001.0.0.0", False)
    test_address("0.0.0.0#00", False)
    test_address("0.0.0.0#01", False)
    test_address("0.0.0.0#001", False)
    test_address("0.0.0.0#0001", False)
    test_address("0.0.0.0#00001", False)


def test_os_check_fails(host):
    """Confirms install fails on unsupported OS"""
    host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${OS_CHECK_DEPS[@]}
    install_dependent_packages ${INSTALLER_DEPS[@]}
    cat <<EOT > /etc/os-release
ID=UnsupportedOS
VERSION_ID="2"
EOT
    """
    )
    detectOS = host.run(
        """t
    source /opt/pihole/basic-install.sh
    os_check
    """
    )
    expected_stdout = "Unsupported OS detected: UnsupportedOS"
    assert expected_stdout in detectOS.stdout


def test_os_check_passes(host):
    """Confirms OS meets the requirements"""
    host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${OS_CHECK_DEPS[@]}
    install_dependent_packages ${INSTALLER_DEPS[@]}
    """
    )
    detectOS = host.run(
        """
    source /opt/pihole/basic-install.sh
    os_check
    """
    )
    expected_stdout = "Supported OS detected"
    assert expected_stdout in detectOS.stdout


def test_package_manager_has_installer_deps(host):
    """Confirms OS is able to install the required packages for the installer"""
    mock_command("dialog", {"*": ("", "0")}, host)
    output = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${INSTALLER_DEPS[@]}
    """
    )

    assert "No package" not in output.stdout
    assert output.rc == 0


def test_package_manager_has_pihole_deps(host):
    """Confirms OS is able to install the required packages for Pi-hole"""
    mock_command("dialog", {"*": ("", "0")}, host)
    output = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${PIHOLE_DEPS[@]}
    """
    )

    assert "No package" not in output.stdout
    assert output.rc == 0


def test_package_manager_has_web_deps(host):
    """Confirms OS is able to install the required packages for web"""
    mock_command("dialog", {"*": ("", "0")}, host)
    output = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${PIHOLE_WEB_DEPS[@]}
    """
    )

    assert "No package" not in output.stdout
    assert output.rc == 0
