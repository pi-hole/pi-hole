from .conftest import (
    tick_box,
    info_box,
    mock_command,
)


def test_epel_not_installed_centos_gt7(Pihole):
    '''
    confirms installer does not attempt to install EPEL repository on CentOS 8+
    '''
    distro_check = Pihole.run('''
    source /opt/pihole/basic-install.sh
    distro_check
    ''')
    assert distro_check.stdout == ''

    epel_package = Pihole.package('epel-release')
    assert not epel_package.is_installed
