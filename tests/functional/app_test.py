import pytest

from python_multiversion_dependency_management_demo.app import app


@pytest.fixture()
def client():
    return app.test_client()


def test_request_example(client):
    response = client.get("/")

    assert b"<p>Hello, World!</p>" in response.data
