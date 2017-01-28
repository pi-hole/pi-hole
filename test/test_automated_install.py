import pytest
from textwrap import dedent

SETUPVARS = {
    'PIHOLE_INTERFACE' : 'eth99',
    'IPV4_ADDRESS' : '1.1.1.1',
    'IPV6_ADDRESS' : 'FE80::240:D0FF:FE48:4672',
    'PIHOLE_DNS_1' : '4.2.2.1',
    'PIHOLE_DNS_2' : '4.2.2.2'
}

def test_setupVars_are_sourced_to_global_scope(Pihole):
    ''' currently update_dialogs sources setupVars with a dot,
    then various other functions use the variables.
    This confirms the sourced variables are in scope between functions '''
    setup_var_file = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k,v in SETUPVARS.iteritems():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "EOF\n"
    Pihole.run(setup_var_file)

    script = dedent('''\
    set -e
    printSetupVars() {
        # Currently debug test function only
        echo "Outputting sourced variables"
        echo "PIHOLE_INTERFACE=${PIHOLE_INTERFACE}"
        echo "IPV4_ADDRESS=${IPV4_ADDRESS}"
        echo "IPV6_ADDRESS=${IPV6_ADDRESS}"
        echo "PIHOLE_DNS_1=${PIHOLE_DNS_1}"
        echo "PIHOLE_DNS_2=${PIHOLE_DNS_2}"
    }
    update_dialogs() {
        . /etc/pihole/setupVars.conf
    }
    update_dialogs
    printSetupVars
    ''')

    output = run_script(Pihole, script).stdout

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def test_setupVars_saved_to_file(Pihole):
    ''' confirm saved settings are written to a file for future updates to re-use '''
    set_setup_vars = '\n'  # dedent works better with this and padding matching script below
    for k,v in SETUPVARS.iteritems():
        set_setup_vars += "    {}={}\n".format(k, v)
    Pihole.run(set_setup_vars).stdout

    script = dedent('''\
    set -e
    echo start
    TERM=xterm
    source /opt/pihole/basic-install.sh
    {}
    finalExports
    cat /etc/pihole/setupVars.conf
    '''.format(set_setup_vars))

    output = run_script(Pihole, script).stdout

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def test_configureFirewall_firewalld_running_no_errors(Pihole):
    ''' confirms firewalld rules are applied when firewallD is running '''
    # firewallD returns 'running' as status
    mock_command('firewall-cmd', {'*':('running', 0)}, Pihole)
    # Whiptail dialog returns Ok for user prompt
    mock_command('whiptail', {'*':('', 0)}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Configuring FirewallD for httpd and dnsmasq.'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/firewall-cmd').stdout
    assert 'firewall-cmd --state' in firewall_calls
    assert 'firewall-cmd --permanent --add-port=80/tcp --add-port=53/tcp --add-port=53/udp' in firewall_calls
    assert 'firewall-cmd --reload' in firewall_calls

def test_configureFirewall_firewalld_disabled_no_errors(Pihole):
    ''' confirms firewalld rules are not applied when firewallD is not running '''
    # firewallD returns non-running status
    mock_command('firewall-cmd', {'*':('not running', '1')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'No active firewall detected.. skipping firewall configuration.'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_firewalld_enabled_declined_no_errors(Pihole):
    ''' confirms firewalld rules are not applied when firewallD is running, user declines ruleset '''
    # firewallD returns running status
    mock_command('firewall-cmd', {'*':('running', 0)}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', 1)}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_no_firewall(Pihole):
    ''' confirms firewall skipped no daemon is running '''
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'No active firewall detected'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_IPTables_enabled_declined_no_errors(Pihole):
    ''' confirms IPTables rules are not applied when IPTables is running, user declines ruleset '''
    # iptables command exists
    mock_command('iptables', {'*':('', '0')}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*':('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', '1')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Not installing firewall rulesets.'
    assert expected_stdout in configureFirewall.stdout

def test_configureFirewall_IPTables_enabled_rules_exist_no_errors(Pihole):
    ''' confirms IPTables rules are not applied when IPTables is running and rules exist '''
    # iptables command exists and returns 0 on calls (should return 0 on iptables -C)
    mock_command('iptables', {'-S':('-P INPUT DENY', '0')}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*':('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', '0')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/iptables').stdout
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT' not in firewall_calls
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT' not in firewall_calls
    assert 'iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT' not in firewall_calls

def test_configureFirewall_IPTables_enabled_not_exist_no_errors(Pihole):
    ''' confirms IPTables rules are applied when IPTables is running and rules do not exist '''
    # iptables command and returns 0 on calls (should return 1 on iptables -C)
    mock_command('iptables', {'-S':('-P INPUT DENY', '0'), '-C':('', 1), '-I':('', 0)}, Pihole)
    # modinfo returns always true (ip_tables module check)
    mock_command('modinfo', {'*':('', '0')}, Pihole)
    # Whiptail dialog returns Cancel for user prompt
    mock_command('whiptail', {'*':('', '0')}, Pihole)
    configureFirewall = Pihole.run('''
    source /opt/pihole/basic-install.sh
    configureFirewall
    ''')
    expected_stdout = 'Installing new IPTables firewall rulesets'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/iptables').stdout
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 80 -j ACCEPT' in firewall_calls
    assert 'iptables -I INPUT 1 -p tcp -m tcp --dport 53 -j ACCEPT' in firewall_calls
    assert 'iptables -I INPUT 1 -p udp -m udp --dport 53 -j ACCEPT' in firewall_calls

def test_installPiholeWeb_fresh_install_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed on a fresh build '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    installPiholeWeb
    ''')
    assert 'Installing pihole custom index page...' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'index.js' in web_directory
    assert 'blockingpage.css' in web_directory

def test_installPiholeWeb_empty_directory_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed in an emtpy directory '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    mkdir -p /var/www/html/pihole
    installPiholeWeb
    ''')
    assert 'Installing pihole custom index page...' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' not in installWeb.stdout
    assert 'index.php missing, replacing...' in installWeb.stdout
    assert 'index.js missing, replacing...' in installWeb.stdout
    assert 'blockingpage.css missing, replacing...' in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'index.js' in web_directory
    assert 'blockingpage.css' in web_directory

def test_installPiholeWeb_index_php_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed when necessary '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    mkdir -p /var/www/html/pihole
    touch /var/www/html/pihole/index.php
    installPiholeWeb
    ''')
    assert 'Installing pihole custom index page...' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' not in installWeb.stdout
    assert 'Existing index.php detected, not overwriting' in installWeb.stdout
    assert 'index.js missing, replacing...' in installWeb.stdout
    assert 'blockingpage.css missing, replacing...' in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'index.js' in web_directory
    assert 'blockingpage.css' in web_directory

def test_installPiholeWeb_index_js_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed when necessary '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    mkdir -p /var/www/html/pihole
    touch /var/www/html/pihole/index.js
    installPiholeWeb
    ''')
    assert 'Installing pihole custom index page...' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' not in installWeb.stdout
    assert 'index.php missing, replacing...' in installWeb.stdout
    assert 'Existing index.js detected, not overwriting' in installWeb.stdout
    assert 'blockingpage.css missing, replacing...' in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'index.js' in web_directory
    assert 'blockingpage.css' in web_directory

def test_installPiholeWeb_blockingpage_css_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed when necessary '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    mkdir -p /var/www/html/pihole
    touch /var/www/html/pihole/blockingpage.css
    installPiholeWeb
    ''')
    assert 'Installing pihole custom index page...' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' not in installWeb.stdout
    assert 'index.php missing, replacing...' in installWeb.stdout
    assert 'index.js missing, replacing...' in installWeb.stdout
    assert 'Existing blockingpage.css detected, not overwriting' in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'index.js' in web_directory
    assert 'blockingpage.css' in web_directory

def test_installPiholeWeb_already_populated_no_errors(Pihole):
    ''' confirms all web page assets from Core repo are installed when necessary '''
    installWeb = Pihole.run('''
    source /opt/pihole/basic-install.sh
    mkdir -p /var/www/html/pihole
    touch /var/www/html/pihole/index.php
    touch /var/www/html/pihole/index.js
    touch /var/www/html/pihole/blockingpage.css
    installPiholeWeb
    ''')
    assert 'Installing pihole custom index page...' in installWeb.stdout
    assert 'No default index.lighttpd.html file found... not backing up' not in installWeb.stdout
    assert 'Existing index.php detected, not overwriting' in installWeb.stdout
    assert 'index.php missing, replacing...' not in installWeb.stdout
    assert 'Existing index.js detected, not overwriting' in installWeb.stdout
    assert 'index.js missing, replacing...' not in installWeb.stdout
    assert 'Existing blockingpage.css detected, not overwriting' in installWeb.stdout
    assert 'blockingpage.css missing, replacing... ' not in installWeb.stdout
    web_directory = Pihole.run('ls -r /var/www/html/pihole').stdout
    assert 'index.php' in web_directory
    assert 'index.js' in web_directory
    assert 'blockingpage.css' in web_directory

def test_update_package_cache_success_no_errors(Pihole):
    ''' confirms package cache was updated without any errors'''
    updateCache = Pihole.run('''
    source /opt/pihole/basick-install.sh
    update_pacakge_cache
    ''')
    assert 'Updating local cache of available packages...' in updateCache.stdout
    assert 'done!' in updateCache.stdout

# Helper functions
def mock_command(script, args, container):
    ''' Allows for setup of commands we don't really want to have to run for real in unit tests '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent('''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1" in'''.format(script=script))
    for k, v in args.iteritems():
        case = dedent('''
        {arg})
        echo {res}
        exit {retcode}
        ;;'''.format(arg=k, res=v[0], retcode=v[1]))
        mock_script += case
    mock_script += dedent('''
    esac''')
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path, content=mock_script, scriptlog=script))

def run_script(Pihole, script):
    result = Pihole.run(script)
    assert result.rc == 0
    return result
