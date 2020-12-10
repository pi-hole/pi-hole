from .conftest import (
    tick_box,
    info_box,
    mock_command,
)


def test_php_upgrade_default_optout_centos_eq_7(Pihole):
    '''
    confirms the default behavior to opt-out of installing PHP7 from REMI
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


def test_php_upgrade_user_optout_centos_eq_7(Pihole):
    '''
    confirms installer behavior when user opt-out of installing PHP7 from REMI
    (php not currently installed)
    '''
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*': ('', '1')}, Pihole)
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' User opt-out of PHP 7 upgrade on CentOS. '
                                  'Deprecated PHP may be in use.')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


def test_php_upgrade_user_optin_centos_eq_7(Pihole):
    '''
    confirms installer behavior when user opt-in to installing PHP7 from REMI
    (php not currently installed)
    '''
    # Whiptail dialog returns Continue for user prompt
    mock_command('whiptail', {'*': ('', '0')}, Pihole)
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    assert 'opt-out' not in distro_check.stdout
    expected_stdout = info_box + (' Enabling Remi\'s RPM repository '
                                  '(https://rpms.remirepo.net)')
    assert expected_stdout in distro_check.stdout
    expected_stdout = tick_box + (' Remi\'s RPM repository has '
                                  'been enabled for PHP7')
    assert expected_stdout in distro_check.stdout
    remi_package = Pihole.package('remi-release')
    assert remi_package.is_installed
