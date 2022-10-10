def test_epel_and_remi_not_installed_fedora(host):
    """
    confirms installer does not attempt to install EPEL/REMI repositories
    on Fedora
    """
    package_manager_detect = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    """
    )
    assert package_manager_detect.stdout == ""

    epel_package = host.package("epel-release")
    assert not epel_package.is_installed
