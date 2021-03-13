from .conftest import (
    tick_box,
    info_box,
    mock_command,
)


def test_epel_installed_centos_7(Pihole):
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
