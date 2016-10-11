import pytest
import testinfra

check_output = testinfra.get_backend(
    "local://"
).get_module("Command").check_output

@pytest.fixture
def Pihole(Docker):
    ''' used to contain some script stubbing, now pretty much an alias '''
    return Docker

@pytest.fixture
def Docker(request, args, image, cmd):
    ''' combine our fixtures into a docker run command and setup finalizer to cleanup '''
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
    ''' -t became required when tput began being used '''
    return '-t -d'

@pytest.fixture(params=['debian', 'centos'])
def tag(request):
    ''' consumed by image to make the test matrix '''
    return request.param

@pytest.fixture()
def image(request, tag):
    ''' built by test_000_build_containers.py '''
    return 'pytest_pihole:{}'.format(tag)

@pytest.fixture()
def cmd(request):
    ''' default to doing nothing by tailing null, but don't exit '''
    return 'tail -f /dev/null'
