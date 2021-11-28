def test_epel_and_remi_not_installed_fedora(Pihole):
    '''
    confirms installer does not attempt to install EPEL/REMI repositories
    on Fedora
    '''
    package_manager_detect = Pihole.run('''
    source /opt/pihole/basic-install.sh
    package_manager_detect
    select_rpm_php
    ''')
    assert package_manager_detect.stdout == ''

    epel_package = Pihole.package('epel-release')
    assert not epel_package.is_installed
    remi_package = Pihole.package('remi-release')
    assert not remi_package.is_installed
