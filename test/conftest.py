import pytest
import testinfra
import testinfra.backend.docker
import subprocess
from textwrap import dedent

IMAGE = "pytest_pihole:test_container"
tick_box = "[✓]"
cross_box = "[✗]"
info_box = "[i]"


# Monkeypatch sh to bash, if they ever support non hard code /bin/sh this can go away
# https://github.com/pytest-dev/pytest-testinfra/blob/master/testinfra/backend/docker.py
def run_bash(self, command, *args, **kwargs):
    cmd = self.get_command(command, *args)
    if self.user is not None:
        out = self.run_local(
            "docker exec -u %s %s /bin/bash -c %s", self.user, self.name, cmd
        )
    else:
        out = self.run_local("docker exec %s /bin/bash -c %s", self.name, cmd)
    out.command = self.encode(cmd)
    return out


testinfra.backend.docker.DockerBackend.run = run_bash


@pytest.fixture
def host():
    # run a container
    docker_id = (
        subprocess.check_output(["docker", "run", "-t", "-d", "--cap-add=ALL", IMAGE])
        .decode()
        .strip()
    )

    # return a testinfra connection to the container
    docker_host = testinfra.get_host("docker://" + docker_id)

    yield docker_host
    # at the end of the test suite, destroy the container
    subprocess.check_call(["docker", "rm", "-f", docker_id])


# Helper functions
def mock_command(script, args, container):
    """
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    """
    full_script_path = "/usr/local/bin/{}".format(script)
    mock_script = dedent(
        r"""\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1" in""".format(
            script=script
        )
    )
    for k, v in args.items():
        case = dedent(
            """
        {arg})
        echo {res}
        exit {retcode}
        ;;""".format(
                arg=k, res=v[0], retcode=v[1]
            )
        )
        mock_script += case
    mock_script += dedent(
        """
    esac"""
    )
    container.run(
        """
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}""".format(
            script=full_script_path, content=mock_script, scriptlog=script
        )
    )


def mock_command_passthrough(script, args, container):
    """
    Per other mock_command* functions, allows intercepting of commands we don't want to run for real
    in unit tests, however also allows only specific arguments to be mocked. Anything not defined will
    be passed through to the actual command.

    Example use-case: mocking `git pull` but still allowing `git clone` to work as intended
    """
    orig_script_path = container.check_output("command -v {}".format(script))
    full_script_path = "/usr/local/bin/{}".format(script)
    mock_script = dedent(
        r"""\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1" in""".format(
            script=script
        )
    )
    for k, v in args.items():
        case = dedent(
            """
        {arg})
        echo {res}
        exit {retcode}
        ;;""".format(
                arg=k, res=v[0], retcode=v[1]
            )
        )
        mock_script += case
    mock_script += dedent(
        r"""
    *)
    {orig_script_path} "\$@"
    ;;""".format(
            orig_script_path=orig_script_path
        )
    )
    mock_script += dedent(
        """
    esac"""
    )
    container.run(
        """
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}""".format(
            script=full_script_path, content=mock_script, scriptlog=script
        )
    )


def mock_command_run(script, args, container):
    """
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    """
    full_script_path = "/usr/local/bin/{}".format(script)
    mock_script = dedent(
        r"""\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1 \$2" in""".format(
            script=script
        )
    )
    for k, v in args.items():
        case = dedent(
            """
        \"{arg}\")
        echo {res}
        exit {retcode}
        ;;""".format(
                arg=k, res=v[0], retcode=v[1]
            )
        )
        mock_script += case
    mock_script += dedent(
        """
    esac"""
    )
    container.run(
        """
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}""".format(
            script=full_script_path, content=mock_script, scriptlog=script
        )
    )


def mock_command_2(script, args, container):
    """
    Allows for setup of commands we don't really want to have to run for real
    in unit tests
    """
    full_script_path = "/usr/local/bin/{}".format(script)
    mock_script = dedent(
        r"""\
    #!/bin/bash -e
    echo "\$0 \$@" >> /var/log/{script}
    case "\$1 \$2" in""".format(
            script=script
        )
    )
    for k, v in args.items():
        case = dedent(
            """
        \"{arg}\")
        echo \"{res}\"
        exit {retcode}
        ;;""".format(
                arg=k, res=v[0], retcode=v[1]
            )
        )
        mock_script += case
    mock_script += dedent(
        """
    esac"""
    )
    container.run(
        """
    cat <<EOF> {script}\n{content}\nEOF
    chmod +x {script}
    rm -f /var/log/{scriptlog}""".format(
            script=full_script_path, content=mock_script, scriptlog=script
        )
    )


def run_script(Pihole, script):
    result = Pihole.run(script)
    assert result.rc == 0
    return result
