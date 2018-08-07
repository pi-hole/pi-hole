''' This file starts with 000 to make it run first '''
import pytest
import testinfra

run_local = testinfra.get_backend(
    "local://"
).get_module("Command").run


@pytest.mark.parametrize("image,tag", [
    ('test/debian.Dockerfile', 'pytest_pihole:debian'),
    ('test/centos.Dockerfile', 'pytest_pihole:centos'),
    ('test/fedora.Dockerfile', 'pytest_pihole:fedora'),
])
# mark as 'build_stage' so we can ensure images are build first when tests
# are executed in parallel. (not required when tests are executed serially)
@pytest.mark.build_stage
def test_build_pihole_image(image, tag):
    build_cmd = run_local('docker build -f {} -t {} .'.format(image, tag))
    if build_cmd.rc != 0:
        print build_cmd.stdout
        print build_cmd.stderr
    assert build_cmd.rc == 0
