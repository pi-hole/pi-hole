import pytest
import testinfra
from textwrap import dedent

check_output = testinfra.get_backend(
    "local://"
).get_module("Command").check_output

SETUPVARS = {
    'PIHOLE_INTERFACE': 'eth99',
    'IPV4_ADDRESS': '1.1.1.1',
    'IPV6_ADDRESS': 'FE80::240:D0FF:FE48:4672',
    'PIHOLE_DNS_1': '4.2.2.1',
    'PIHOLE_DNS_2': '4.2.2.2'
}

tick_box = "[\x1b[1;32m\u2713\x1b[0m]"
cross_box = "[\x1b[1;31m\u2717\x1b[0m]"
info_box = "[i]"


@pytest.fixture
def Pihole(Docker):
    '''
    used to contain some script stubbing, now pretty much an alias.
    Also provides bash as the default run function shell
    '''
    def run_bash(self, command, *args, **kwargs):
        cmd = self.get_command(command, *args)
        if self.user is not None:
            out = self.run_local(
                "docker exec -u %s %s /bin/bash -c %s",
                self.user, self.name, cmd)
        else:
            out = self.run_local(
                "docker exec %s /bin/bash -c %s", self.name, cmd)
        out.command = self.encode(cmd)
        return out

    funcType = type(Docker.run)
    Docker.run = funcType(run_bash, Docker)
    return Docker


@pytest.fixture
def Docker(request, args, image, cmd):
    '''
    combine our fixtures into a docker run command and setup finalizer to
    cleanup
    '''
    assert 'docker' in check_output('id'), "Are you in the docker group?"
    docker_run = "docker run {} {} {}".format(args, image, cmd)
    docker_id = check_output(docker_run)

    def teardown():
        check_output("docker rm -f %s", docker_id)
    request.addfinalizer(teardown)

    docker_container = testinfra.get_backend("docker://" + docker_id)
    docker_container.id = docker_id
    return docker_container


@pytest.fixture
def args(request):
    '''
    -t became required when tput began being used
    '''
    return '-t -d'


@pytest.fixture(params=[
    'test_container'
])
def tag(request):
    '''
    consumed by image to make the test matrix
    '''
    return request.param


@pytest.fixture()
def image(request, tag):
    '''
    built by test_000_build_containers.py
    '''
    return 'pytest_pihole:{}'.format(tag)


@pytest.fixture()
def cmd(request):
    '''
    default to doing nothing by tailing null, but don't exit
    '''
    return 'tail -f /dev/null'


# Helper functions
def mock_command(script, args, container):
    '''
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent('''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1" in'''.format(script=script))
    for k, v in args.items():
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
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path,
                                         content=mock_script,
                                         scriptlog=script))


def mock_command_2(script, args, container):
    '''
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent('''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1 \$2" in'''.format(script=script))
    for k, v in args.items():
        case = dedent('''
        \"{arg}\")
        echo \"{res}\"
        exit {retcode}
        ;;'''.format(arg=k, res=v[0], retcode=v[1]))
        mock_script += case
    mock_script += dedent('''
    esac''')
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path,
                                         content=mock_script,
                                         scriptlog=script))


def run_script(Pihole, script):
    result = Pihole.run(script)
    assert result.rc == 0
    return result
