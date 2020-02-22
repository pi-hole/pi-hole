import subprocess

import pytest
import testinfra
from textwrap import dedent

SETUPVARS = {
    'PIHOLE_INTERFACE': 'eth99',
    'IPV4_ADDRESS': '1.1.1.1',
    'IPV6_ADDRESS': 'FE80::240:D0FF:FE48:4672',
    'PIHOLE_DNS_1': '4.2.2.1',
    'PIHOLE_DNS_2': '4.2.2.2'
}

tick_box = "[\x1b[1;32m\xe2\x9c\x93\x1b[0m]"
cross_box = "[\x1b[1;31m\xe2\x9c\x97\x1b[0m]"
info_box = "[i]"


@pytest.fixture
def Pihole(Docker):
    # Docker.run = Docker.check_output
    return Docker


@pytest.fixture(scope='function')
def Docker(request, args, image, cmd):
    '''
    combine our fixtures into a docker run command and setup finalizer to
    cleanup
    '''
    assert 'docker' in subprocess.check_output('id').decode().strip(), (
        "Are you in the docker group?"
    )
    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run'] + args.split(" ") + [image] + cmd.split(" ")).decode().strip()
    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + docker_id)
    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])


@pytest.fixture
def args(request):
    '''
    -t became required when tput began being used
    '''
    return '-t -d'


@pytest.fixture(params=['debian', 'centos', 'fedora'])
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
    result = Pihole.check_output(script)
    assert result.rc == 0
    return result
