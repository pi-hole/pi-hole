import pytest
import testinfra

run_local = testinfra.get_backend(
    "local://"
).get_module("Command").run

def test_scripts_pass_shellcheck_update_sh():
    ''' Make sure shellcheck does not find anything wrong with our shell scripts '''
    shellcheck = "find . -type f -name 'update.sh' | while read file; do shellcheck -x \"$file\" -e SC1090,SC1091; done;"
    results = run_local(shellcheck)
    print results.stdout
    assert '' == results.stdout

def test_scripts_pass_shellcheck_version_sh():
    ''' Make sure shellcheck does not find anything wrong with our shell scripts '''
    shellcheck = "find . -type f -name 'version.sh' | while read file; do shellcheck -x \"$file\" -e SC1090,SC1091; done;"
    results = run_local(shellcheck)
    print results.stdout
    assert '' == results.stdout
