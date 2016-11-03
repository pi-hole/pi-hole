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
    #!/bin/bash -e
    printSetupVars() {
        # Currently debug test function only
        echo "Outputting sourced variables"
        echo "PIHOLE_INTERFACE=\${PIHOLE_INTERFACE}"
        echo "IPV4_ADDRESS=\${IPV4_ADDRESS}"
        echo "IPV6_ADDRESS=\${IPV6_ADDRESS}"
        echo "PIHOLE_DNS_1=\${PIHOLE_DNS_1}"
        echo "PIHOLE_DNS_2=\${PIHOLE_DNS_2}"
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
    #!/bin/bash -e
    echo start
    TERM=xterm
    PHTEST=TRUE
    source /opt/pihole/basic-install.sh
    {}
    finalExports
    cat /etc/pihole/setupVars.conf
    '''.format(set_setup_vars))

    output = run_script(Pihole, script).stdout

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def test_configureFirewall_firewalld_no_errors(Pihole):
    ''' confirms firewalld rules are applied when appopriate '''
    mock_command('firewall-cmd', '0', Pihole)
    configureFirewall = Pihole.run('''
    bash -c "
    PHTEST=TRUE
    source /opt/pihole/basic-install.sh
    configureFirewall
    " ''')
    expected_stdout = '::: Configuring firewalld for httpd and dnsmasq.'
    assert expected_stdout in configureFirewall.stdout
    firewall_calls = Pihole.run('cat /var/log/firewall-cmd').stdout
    assert 'firewall-cmd --state' in firewall_calls
    assert 'firewall-cmd --permanent --add-port=80/tcp' in firewall_calls
    assert 'firewall-cmd --permanent --add-port=53/tcp' in firewall_calls
    assert 'firewall-cmd --permanent --add-port=53/udp' in firewall_calls
    assert 'firewall-cmd --reload' in firewall_calls


# Helper functions
def mock_command(script, result, container):
    ''' Allows for setup of commands we don't really want to have to run for real in unit tests '''
    ''' TODO: support array of results that enable the results to change over multiple executions of a command '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent('''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    exit {retcode}
    '''.format(script=script, retcode=result))
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    '''.format(script=full_script_path, content=mock_script))
    print container.run('cat {}'.format(full_script_path)).stdout


def run_script(Pihole, script, file="/test.sh"):
    _write_test_script(Pihole, script, file=file)
    result = Pihole.run(file)
    assert result.rc == 0
    return result

def _write_test_script(Pihole, script, file):
    ''' Running the test script blocks directly can behave differently with regard to global vars '''
    ''' this is a cheap work around to that until all functions no longer rely on global variables '''
    Pihole.run('cat <<EOF> {file}\n{script}\nEOF'.format(file=file, script=script))
    Pihole.run('chmod +x {}'.format(file))
