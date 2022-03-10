# Recommended way to run tests

Make sure you have Docker and Python w/pip package manager.

From command line all you need to do is:

- `pip install tox`
- `tox`

Tox handles setting up a virtual environment for python dependencies, installing dependencies, building the docker images used by tests, and finally running tests.  It's an easy way to have travis-ci like build behavior locally.

## Alternative py.test method of running tests

You're responsible for setting up your virtual env and dependencies in this situation.

```
py.test -vv -n auto -m "build_stage"
py.test -vv -n auto -m "not build_stage"
```

The build_stage tests have to run first to create the docker images, followed by the actual tests which utilize said images. Unless you're changing your dockerfiles you shouldn't have to run the build_stage every time - but it's a good idea to rebuild at least once a day in case the base Docker images or packages change.

# How do I debug python?

Highly recommended: Setup PyCharm on a **Docker enabled** machine. Having a python debugger like PyCharm changes your life if you've never used it :)
