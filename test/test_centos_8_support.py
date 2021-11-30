from .conftest import (
    tick_box,
    info_box,
    mock_command,
)


def test_php_upgrade_default_continue_centos_gte_8(host):
    '''
    confirms the latest version of CentOS continues / does not optout
    (should trigger on CentOS7 only)
    '''
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    unexpected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS.'
                                    ' Deprecated PHP may be in use.')
    assert unexpected_stdout not in package_manager_detect.stdout
    # ensure remi was not installed on latest CentOS
    remi_package = host.package('remi-release')
    assert not remi_package.is_installed


def test_php_upgrade_user_optout_skipped_centos_gte_8(host):
    '''
    confirms installer skips user opt-out of installing PHP7 from REMI on
    latest CentOS (should trigger on CentOS7 only)
    (php not currently installed)
    '''
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, host)
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    unexpected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS.'
                                    ' Deprecated PHP may be in use.')
    assert unexpected_stdout not in package_manager_detect.stdout
    # ensure remi was not installed on latest CentOS
    remi_package = host.package('remi-release')
    assert not remi_package.is_installed


def test_php_upgrade_user_optin_skipped_centos_gte_8(host):
    '''
    confirms installer skips user opt-in to installing PHP7 from REMI on
    latest CentOS (should trigger on CentOS7 only)
    (php not currently installed)
    '''
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, host)
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    assert 'opt-out' not in package_manager_detect.stdout
    unexpected_stdout = info_box + (' Enabling Remi\'s RPM repository '
                                    '(https://rpms.remirepo.net)')
    assert unexpected_stdout not in package_manager_detect.stdout
    unexpected_stdout = tick_box + (' Remi\'s RPM repository has '
                                    'been enabled for PHP7')
    assert unexpected_stdout not in package_manager_detect.stdout
    remi_package = host.package('remi-release')
    assert not remi_package.is_installed
