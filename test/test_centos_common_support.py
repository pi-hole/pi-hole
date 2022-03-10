import pytest
from .conftest import (
    tick_box,
    info_box,
    cross_box,
    mock_command,
)


def test_release_supported_version_check_centos(host):
    '''
    confirms installer exits on unsupported releases of CentOS
    '''
    # modify /etc/redhat-release to mock an unsupported CentOS release
    host.run('echo "CentOS Linux release 6.9" > /etc/redhat-release')
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    expected_stdout = cross_box + (' CentOS 6 is not supported.')
    assert expected_stdout in package_manager_detect.stdout
    expected_stdout = 'Please update to CentOS release 7 or later'
    assert expected_stdout in package_manager_detect.stdout


def test_enable_epel_repository_centos(host):
    '''
    confirms the EPEL package repository is enabled when installed on CentOS
    '''
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    expected_stdout = info_box + (' Enabling EPEL package repository '
                                  '(https://fedoraproject.org/wiki/EPEL)')
    assert expected_stdout in package_manager_detect.stdout
    expected_stdout = tick_box + ' Installed epel-release'
    assert expected_stdout in package_manager_detect.stdout
    epel_package = host.package('epel-release')
    assert epel_package.is_installed


def test_php_version_lt_7_detected_upgrade_default_optout_centos(host):
    '''
    confirms the default behavior to opt-out of upgrading to PHP7 from REMI
    '''
    # first we will install the default php version to test installer behavior
    php_install = host.run('yum install -y php')
    assert php_install.rc == 0
    php_package = host.package('php')
    default_centos_php_version = php_package.version.split('.')[0]
    if int(default_centos_php_version) >= 7:  # PHP7 is supported/recommended
        pytest.skip("Test deprecated . Detected default PHP version >= 7")
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in package_manager_detect.stdout
    remi_package = host.package('remi-release')
    assert not remi_package.is_installed


def test_php_version_lt_7_detected_upgrade_user_optout_centos(host):
    '''
    confirms installer behavior when user opt-out to upgrade to PHP7 via REMI
    '''
    # first we will install the default php version to test installer behavior
    php_install = host.run('yum install -y php')
    assert php_install.rc == 0
    php_package = host.package('php')
    default_centos_php_version = php_package.version.split('.')[0]
    if int(default_centos_php_version) >= 7:  # PHP7 is supported/recommended
        pytest.skip("Test deprecated . Detected default PHP version >= 7")
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, host)
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in package_manager_detect.stdout
    remi_package = host.package('remi-release')
    assert not remi_package.is_installed


def test_php_version_lt_7_detected_upgrade_user_optin_centos(host):
    '''
    confirms installer behavior when user opt-in to upgrade to PHP7 via REMI
    '''
    # first we will install the default php version to test installer behavior
    php_install = host.run('yum install -y php')
    assert php_install.rc == 0
    php_package = host.package('php')
    default_centos_php_version = php_package.version.split('.')[0]
    if int(default_centos_php_version) >= 7:  # PHP7 is supported/recommended
        pytest.skip("Test deprecated . Detected default PHP version >= 7")
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, host)
    package_manager_detect = host.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    install_dependent_packages PIHOLE_WEB_DEPS[@]
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout not in package_manager_detect.stdout
    expected_stdout = info_box + (' Enabling Remi\'s RPM repository '
                                  '(https://rpms.remirepo.net)')
    assert expected_stdout in package_manager_detect.stdout
    expected_stdout = tick_box + (' Remi\'s RPM repository has '
                                  'been enabled for PHP7')
    assert expected_stdout in package_manager_detect.stdout
    remi_package = host.package('remi-release')
    assert remi_package.is_installed
    updated_php_package = host.package('php')
    updated_php_version = updated_php_package.version.split('.')[0]
    assert int(updated_php_version) == 7
