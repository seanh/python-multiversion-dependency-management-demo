from python_multiversion_dependency_management_demo.app import hello_world


def test_it():
    assert hello_world().startswith("<p>Hello, Python")
