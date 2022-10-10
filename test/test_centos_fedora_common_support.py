from .conftest import (
    tick_box,
    cross_box,
    mock_command,
)


def mock_selinux_config(state, host):
    """
    Creates a mock SELinux config file with expected content
    """
    # validate state string
    valid_states = ["enforcing", "permissive", "disabled"]
    assert state in valid_states
    # getenforce returns the running state of SELinux
    mock_command("getenforce", {"*": (state.capitalize(), "0")}, host)
    # create mock configuration with desired content
    host.run(
        """
    mkdir /etc/selinux
    echo "SELINUX={state}" > /etc/selinux/config
    """.format(
            state=state.lower()
        )
    )


def test_selinux_enforcing_exit(host):
    """
    confirms installer prompts to exit when SELinux is Enforcing by default
    """
    mock_selinux_config("enforcing", host)
    check_selinux = host.run(
        """
    source /opt/pihole/basic-install.sh
    checkSelinux
    """
    )
    expected_stdout = cross_box + " Current SELinux: enforcing"
    assert expected_stdout in check_selinux.stdout
    expected_stdout = "SELinux Enforcing detected, exiting installer"
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 1


def test_selinux_permissive(host):
    """
    confirms installer continues when SELinux is Permissive
    """
    mock_selinux_config("permissive", host)
    check_selinux = host.run(
        """
    source /opt/pihole/basic-install.sh
    checkSelinux
    """
    )
    expected_stdout = tick_box + " Current SELinux: permissive"
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0


def test_selinux_disabled(host):
    """
    confirms installer continues when SELinux is Disabled
    """
    mock_selinux_config("disabled", host)
    check_selinux = host.run(
        """
    source /opt/pihole/basic-install.sh
    checkSelinux
    """
    )
    expected_stdout = tick_box + " Current SELinux: disabled"
    assert expected_stdout in check_selinux.stdout
    assert check_selinux.rc == 0
