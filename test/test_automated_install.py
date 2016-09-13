import pytest

@pytest.fixture
def Pihole(Docker):
    ''' generates stubs of files that normally execute code '''
    return Docker

def test_setupVars_get_read_into_main_scope_level(Pihole):
    vars = { 
        'piholeInterface' : 'eth99',
        'IPv4addr' : '192.168.100.2',
        'piholeIPv6' : 'True',
        'piholeDNS1' : '4.2.2.1',
        'piholeDNS2' : '4.2.2.2' 
    }
    setup_fake_vars = 'cat <<EOF> /etc/pihole/setupVars.conf\n'
    for k,v in vars.iteritems():
        setup_fake_vars += "{}={}\n".format(k, v)
    setup_fake_vars += "EOF\n"
    Pihole.run(setup_fake_vars).stdout
    #print Pihole.run('cat /etc/pihole/setupVars.conf').stdout

    script = '/opt/pihole/stub_basic-install.sh pihole'

    cmd = 'bash -c "\n'
    cmd += 'source {};\n'.format(script)
    cmd += 'env > /tmp/saved_env"\n'
    cmd += '"\n'
    stubbed_script = Pihole.run(cmd)
    env = Pihole.run('cat /tmp/saved_env').stdout
    print stubbed_script.stdout

    assert "::: Importing previous variables for upgrade" in stubbed_script.stdout
    for k,v in vars.iteritems():
        assert "{}={}".format(k, v) in stubbed_script.stdout
        assert "{}={}".format(k, v) in env
