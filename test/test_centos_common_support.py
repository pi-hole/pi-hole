import pytest
from .conftest import (
    tick_box,
    info_box,
    cross_box,
    mock_command,
)


def test_enable_epel_repository_centos(host):
    """
    confirms the EPEL package repository is enabled when installed on CentOS
    """
    package_manager_detect = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    """
    )
    expected_stdout = info_box + (
        " Enabling EPEL package repository " "(https://fedoraproject.org/wiki/EPEL)"
    )
    assert expected_stdout in package_manager_detect.stdout
    expected_stdout = tick_box + " Installed"
    assert expected_stdout in package_manager_detect.stdout
    epel_package = host.package("epel-release")
    assert epel_package.is_installed
