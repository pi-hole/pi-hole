import pytest
import testinfra

DEBUG = []

check_output = testinfra.get_backend(
    "local://"
).get_module("Command").check_output

@pytest.fixture
def Docker(request, args, image, cmd):
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
    return '-d'

@pytest.fixture()
def image(request):
    return 'pytest_pihole'

@pytest.fixture()
def cmd(request):
    return 'tail -f /dev/null'
