import pytest

@pytest.fixture
def Pihole(Docker):
    ''' generates stubs of files that normally execute code '''
    ''' (moved to Dockerfile in some cases) '''
    return Docker

SETUPVARS = {
    'piholeInterface' : 'eth99',
    'IPv4addr' : '192.168.100.2',
    'piholeIPv6' : 'True',
    'piholeDNS1' : '4.2.2.1',
    'piholeDNS2' : '4.2.2.2'
}

def test_setupVars_are_sourced_to_global_scope(Pihole):
    ''' one function imports, other functions read these variables '''
    setup_var_file = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k,v in SETUPVARS.iteritems():
        setup_var_file += "{}={}\n".format(k, v)
    setup_var_file += "EOF\n"
    Pihole.run(setup_var_file).stdout

    script = '''#!/bin/bash -e
. /opt/pihole/stub_basic-install.sh
readSetupVarsIfPresent pihole
printSetupVars'''

    write_test_script(Pihole, script)
    output = Pihole.run('bash /test').stdout
    print output

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def test_setupVars_saved_to_file(Pihole):
    ''' one function imports, other functions read these variables '''
    set_setup_vars = ''
    for k,v in SETUPVARS.iteritems():
        set_setup_vars += "{}={}\n".format(k, v)
    Pihole.run(set_setup_vars).stdout

    script = '''#!/bin/bash -e
. /opt/pihole/stub_basic-install.sh
{}
finalExports
cat /etc/pihole/setupVars.conf'''.format(set_setup_vars)

    write_test_script(Pihole, script)
    output = Pihole.run('bash /test').stdout
    print output

    for k,v in SETUPVARS.iteritems():
        assert "{}={}".format(k, v) in output

def write_test_script(Pihole, script):
    Pihole.run('cat <<EOF> /test\n{}\nEOF'.format(script))
    Pihole.run('chmod +x /test')
    #print Pihole.run('cat /test; ls -lat /test').stdout
