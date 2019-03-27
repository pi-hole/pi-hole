import pytest
from conftest import (
    tick_box,
    info_box,
    cross_box,
    mock_command,
    mock_command_2,
)


@pytest.mark.parametrize("tag", [('fedora'), ])
def test_epel_and_remi_not_installed_fedora(Pihole):
    '''
    confirms installer does not attempt to install EPEL/REMI repositories
    on Fedora
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    assert distro_check.stdout == ''

    epel_package = Pihole.package('epel-release')
    assert not epel_package.is_installed
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed


@pytest.mark.parametrize("tag", [('centos'), ])
def test_release_supported_version_check_centos(Pihole):
    '''
    confirms installer exits on unsupported releases of CentOS
    '''
    # modify /etc/redhat-release to mock an unsupported CentOS release
    Pihole.run('echo "CentOS Linux release 6.9" > /etc/redhat-release')
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = cross_box + (' CentOS 6 is not supported.')
    assert expected_stdout in distro_check.stdout
    expected_stdout = 'Please update to CentOS release 7 or later'
    assert expected_stdout in distro_check.stdout


@pytest.mark.parametrize("tag", [('centos'), ])
def test_enable_epel_repository_centos(Pihole):
    '''
    confirms the EPEL package repository is enabled when installed on CentOS
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    expected_stdout = info_box + (' Enabling EPEL package repository '
                                  '(https://fedoraproject.org/wiki/EPEL)')
    assert expected_stdout in distro_check.stdout
    expected_stdout = tick_box + ' Installed epel-release'
    assert expected_stdout in distro_check.stdout
    epel_package = Pihole.package('epel-release')
    assert epel_package.is_installed
