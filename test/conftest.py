import pytest
import testinfra
import subprocess
from testinfra.backend import base
from textwrap import dedent


SETUPVARS = {
    'PIHOLE_INTERFACE': 'eth99',
    'PIHOLE_DNS_1': '4.2.2.1',
    'PIHOLE_DNS_2': '4.2.2.2'
}

IMAGE = 'pytest_pihole:test_container'

tick_box = "[\x1b[1;32m\u2713\x1b[0m]"
cross_box = "[\x1b[1;31m\u2717\x1b[0m]"
info_box = "[i]"


@pytest.fixture
def host():

    # run a container
    docker_id = subprocess.check_output(
        ['docker', 'run', '-t', '-d', '--cap-add=ALL', IMAGE]).decode().strip()

    # return a testinfra connection to the container
    docker_host = testinfra.get_host("docker://" + docker_id)

    # Can we override the host.run function here to use /bin/bash instead of /bin/sh?
    # So far this works if I run "pytest -vv -n auto test/test_automated_install.py" locally
    # but with the caveat that I manually changed "\home\adam\.local\lib\python3.8\site-packages\testinfra\backend\docker.py"
    # to use /bin/bash instead of /bin/sh
    # this is not ideal!

    yield docker_host
    # at the end of the test suite, destroy the container
    subprocess.check_call(['docker', 'rm', '-f', docker_id])



# Helper functions
def mock_command(script, args, container):
    '''
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent(r'''\
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


def mock_command_passthrough(script, args, container):
    '''
    Per other mock_command* functions, allows intercepting of commands we don't want to run for real
    in unit tests, however also allows only specific arguments to be mocked. Anything not defined will
    be passed through to the actual command.

    Example use-case: mocking `git pull` but still allowing `git clone` to work as intended
    '''
    orig_script_path = container.check_output('which {}'.format(script))
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent(r'''\
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
    mock_script += dedent(r'''
    *)
    {orig_script_path} "\$@"
    ;;'''.format(orig_script_path=orig_script_path))
    mock_script += dedent('''
    esac''')
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path,
                                         content=mock_script,
                                         scriptlog=script))


def mock_command_run(script, args, container):
    '''
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent(r'''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1 \$2" in'''.format(script=script))
    for k, v in args.items():
        case = dedent('''
        \"{arg}\")
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


def mock_command_passthrough(script, args, container):
    '''
    Per other mock_command* functions, allows intercepting of commands we don't want to run for real
    in unit tests, however also allows only specific arguments to be mocked. Anything not defined will
    be passed through to the actual command.

    Example use-case: mocking `git pull` but still allowing `git clone` to work as intended
    '''
    orig_script_path = container.check_output('which {}'.format(script))
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent(r'''\
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
    mock_script += dedent(r'''
    *)
    {orig_script_path} "\$@"
    ;;'''.format(orig_script_path=orig_script_path))
    mock_script += dedent('''
    esac''')
    container.run('''
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}'''.format(script=full_script_path,
                                         content=mock_script,
                                         scriptlog=script))


def mock_command_run(script, args, container):
    '''
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    '''
    full_script_path = '/usr/local/bin/{}'.format(script)
    mock_script = dedent(r'''\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1 \$2" in'''.format(script=script))
    for k, v in args.items():
        case = dedent('''
        \"{arg}\")
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
    mock_script = dedent(r'''\
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
