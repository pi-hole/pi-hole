''' This file starts with 000 to make it run first '''
import pytest
import testinfra

run_local = testinfra.get_backend(
    "local://"
).get_module("Command").run


@pytest.mark.parametrize("image,tag", [
    ('test/ubuntu_16.Dockerfile', 'pytest_pihole:ubuntu_16'),
    ('test/ubuntu_18.Dockerfile', 'pytest_pihole:ubuntu_18'),
    ('test/ubuntu_20.Dockerfile', 'pytest_pihole:ubuntu_20'),
])
# mark as 'build_stage' so we can ensure images are built first when tests
# are executed in parallel. (not required when tests are executed serially)
@pytest.mark.build_stage
def test_build_pihole_image(image, tag):
    build_cmd = run_local('docker build -f {} -t {} .'.format(image, tag))
    if build_cmd.rc != 0:
        print(build_cmd.stdout)
        print(build_cmd.stderr)
    assert build_cmd.rc == 0
