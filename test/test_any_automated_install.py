import pytest
from textwrap import dedent
import re
from .conftest import (
    SETUPVARS,
    tick_box,
    info_box,
    cross_box,
    mock_command,
    mock_command_run,
    mock_command_2,
    mock_command_passthrough,
    run_script,
)


def test_lighttpd_lua_support(host):
    """Confirms lighttpd installed has LUA support"""
    mock_command("dialog", {"*": ("", "0")}, host)
    output = host.run(
        """
    source /opt/pihole/basic-install.sh
    package_manager_detect
    install_dependent_packages ${PIHOLE_WEB_DEPS[@]}
    """
    )

    assert "No package" not in output.stdout
    assert output.rc == 0

    lua_support = host.run(
        """
    /usr/sbin/lighttpd -V | grep -o '+ LUA support'
    """
    )
    expected_stdout = "+ LUA support"
    assert expected_stdout in lua_support.stdout
