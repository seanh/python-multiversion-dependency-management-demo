.PHONY: help
help:
	@echo "make help              Show this help message"
	@echo "make dev               Run the app"
	@echo "make lint              Run the code linter(s) and print any warnings"
	@echo "make format            Correctly format the code"
	@echo "make checkformatting   Crash if the code isn't correctly formatted"
	@echo "make test              Run all unit tests"
	@echo "make functests         Run the functional tests"
	@echo "make coverage          Print the unit test coverage report"
	@echo "make sure              Make sure that the formatter, linter, tests, etc all pass"
	@echo "make requirements      Re-compile all the requirements/*.txt files"
	@echo "make clean             Delete development artefacts (cached files, "
	@echo "                       dependencies, etc)"

.PHONY: dev
dev: python
	pyenv exec tox -e py310-dev

.PHONY: lint
lint: python
	pyenv exec tox -e lint

.PHONY: format
format: python
	pyenv exec tox -e format

.PHONY: checkformatting
checkformatting: python
	pyenv exec tox -e checkformatting

.PHONY: test
test: python
	pyenv exec tox

.PHONY: functests
functests: python
	pyenv exec tox -e py310-functests

.PHONY: coverage
coverage: python
	pyenv exec tox -e coverage

.PHONY: sure
sure: checkformatting lint test coverage functests
	pyenv exec tox -e py39-tests
	pyenv exec tox -e py38-tests
	pyenv exec tox -e py39-functests
	pyenv exec tox -e py38-functests

.PHONY: requirements
requirements:
	bin/make_requirements

.PHONY: clean
clean:
	rm -rf build dist .tox
	find . -path '*/__pycache__*' -delete
	find . -path '*.egg-info*' -delete

.PHONY: python
python:
	bin/make_python
