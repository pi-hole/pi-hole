import pytest
from .conftest import (
    tick_box,
    info_box,
    cross_box,
    mock_command,
)


def mock_selinux_config(state, Pihole):
    '''
    Creates a mock SELinux config file with expected content
    '''
    # validate state string
    valid_states = ['enforcing', 'permissive', 'disabled']
    assert state in valid_states
    # getenforce returns the running state of SELinux
    mock_command('getenforce', {'*': (state.capitalize(), '0')}, Pihole)
    # create mock configuration with desired content
    Pihole.run('''
    mkdir /etc/selinux
    echo "SELINUX={state}" > /etc/selinux/config
    '''.format(state=state.lower()))


@pytest.mark.parametrize("tag", [('fedora_31'), ('fedora_32'), ])
def test_selinux_enforcing_exit(Pihole):
    '''
    confirms installer prompts to exit when SELinux is Enforcing by default
    '''
    mock_selinux_config("enforcing", Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = cross_box + ' Current SELinux: Enforcing'
    assert expected_stdout in check_selinux.stdout
    expected_stdout = 'SELinux Enforcing detected, exiting installer'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 1


@pytest.mark.parametrize("tag", [('fedora_31'), ('fedora_32'), ])
def test_selinux_permissive(Pihole):
    '''
    confirms installer continues when SELinux is Permissive
    '''
    mock_selinux_config("permissive", Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = tick_box + ' Current SELinux: Permissive'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


@pytest.mark.parametrize("tag", [('fedora_31'), ('fedora_32'), ])
def test_selinux_disabled(Pihole):
    '''
    confirms installer continues when SELinux is Disabled
    '''
    mock_selinux_config("disabled", Pihole)
    check_selinux = Pihole.run('''
    source /opt/pihole/basic-install.sh
    checkSelinux
    ''')
    expected_stdout = tick_box + ' Current SELinux: Disabled'
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


@pytest.mark.parametrize("tag", [('fedora_31'), ('fedora_32'), ])
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



