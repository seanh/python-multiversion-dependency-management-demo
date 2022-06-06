Python Multi-version Dependency Pinning Demo
============================================

A demonstration of the problems with pinning Python dependencies while also
supporting multiple versions of Python.

TLDR: This is ultimately impossible to do with pip-tools because Dependabot
can't understand different requirements files for different versions of Python.
I think you could do it if you use Poetry instead of pip-tools but it would
have other downsides.

How it works
------------

### pyenv and `make python`

As with all our projects developers need to install [pyenv](https://github.com/pyenv/pyenv)
manually and then we have a little scripting that uses pyenv to install the
necessary versions of Python so that developers don't need to do that
themselves:

* The [`.python-version` file](.python-version) lists all the versions of Python
  that the project needs.

* `make python` calls [`bin/make_python`](bin/make_python) (called
  `install-python` in our other projects) which loops over all the Python
  versions listed in the `.python-version` file and installs each version in
  pyenv if it isn't installed already. It also installs tox in pyenv.

One tweak I made is that the [`Makefile`](Makefile) runs `pyenv exec tox ...`
instead of just running `tox` directly. This means that developers just have
to have pyenv installed, they don't need to have pyenv's shell integration
("shims") set up
(see [Using pyenv without shims](https://github.com/pyenv/pyenv#using-pyenv-without-shims)).

### `pip-compile` and `make requirements`

If you want to support multiple versions of Python you need **separate
requirements.txt files for each version of Python** because, given the same set
of input requirements, `pip-compile` can produce different output for different
Python versions.

There's all sorts of ways that a Python package's dependencies can vary
depending on what Python version it's being installed in.
Its requirements can contain [PEP 508 environment markers](https://peps.python.org/pep-0508/#environment-markers)
like `argparse;python_version<"2.7"`, or the project can have
[a `setup.py` that varies the dependencies dynamically](https://dustingram.com/articles/2018/03/05/why-pypi-doesnt-know-dependencies/).

Even worse: **some of our requirements.in files depend on other requirements.txt files**.
For example `tests.in` imports `prod.txt` with `-r prod.txt`.
But which `prod.txt` file should `tests.in` import?
There isn't a single `prod.txt` file. There's one for each version of Python:
`py310-prod.txt`, `py39-prod.txt`, etc.
The requirements.in files are manually maintained so we don't want to multiply them
(`py310-tests.in`, `py39-tests.in`, ...), but how can a single `tests.in` file
depend on `py310-prod.txt` in Python 3.10 but `py39-prod.txt` in Python 3.9 and so on?

You can't solve this by using conditional dependencies in the requirements.in files.
Environment markers don't seem to work with `-r` lines.
`-r py310-prod.txt; python_version=="3.10"` doesn't work (it will install
`py310-prod.txt` unconditionally, for every Python version).
Even if this did work it'd be a pain to maintain: each time we added or removed
a version of Python we'd have to update the imports at the top of each
requirements file.

This repo contains a solution based on symlinks:

    requirements/
      coverage.in
      dev.in        # Contains -r prod.txt
      format.in
      functests.in  # Contains -r prod.txt
      lint.in       # Contains -r tests.txt and -r functests.txt
      tests.in      # Contains -r prod.txt
      py310/
        coverage.in  -> ../coverage.in
        dev.in       -> ../dev.in
        format.in    -> ../format.in
        functests.in -> ../functests.in
        lint.in      -> ../lint.in
        tests.in     -> ../tests.in
        coverage.txt
        dev.txt
        format.txt
        functests.txt
        lint.txt
        tests.txt
        prod.txt     # Compiled from setup.cfg
      py39/
        dev.in       -> ../coverage.in
        functests.in -> ../functests.in
        tests.in     -> ../tests.in
        dev.txt
        functests.txt
        tests.txt
        prod.txt     # Compiled from setup.cfg
      py38/
        ...

In this setup the six `requirements/*.in` files  are the master set of manually
maintained base requirements (along with the unpinned production requirements
which live in the `install_requires` setting in the `setup.cfg` file).
The `pyXY` subdirs contain the _generated_ requirements files
compiled from the six `requirements/*.in`'s and the `setup.cfg` file.
The trick is that each `pyXY` subdir also contains symlinks back up to the
`requirements/*.in` files: `py310/tests.in -> ../tests.in` etc.
You don't compile `requirements/tests.in`, instead you compile each of the
`requirements/pyXY/tests.in`'s: for example
`pip-compile requirements/py310/tests.in` produces the `requirements/py310/tests.txt` file.
The single `-r prod.txt` in `requirements/tests.in` will refer to
`requirements/py310/prod.txt` when the `py310/tests.in` symlink is being compiled
and to `py39/prod.txt` when `py39/tests.in` is being compiled and so on.

This trick enables you to maintain a single set of `requirements/*.in` files
(and a `setup.cfg` file) and from those compile separate sets of pinned
requirements files for each version of Python.

The [`make requirements`](bin/make_requirements) script automates this: it
loops over the Python versions in the `.python_version` file, creates the
`requirements/pyXY` subdirs, deletes any `requirements/pyXY` subdirs that're no
longer in the `.python_version` file, creates the symlinks, and compiles the
requirements.txt files. You just maintain your `.python_version`, `setup.cfg`,
and single set of `requirements/*.in` files, and re-run `make requirements`
after making any changes.

A couple of other things to notice:

* The `requirements/pyXY` subdir for the first version of Python (`py310`)
  contains more requirements files than those for the other versions of Python.
  This is because we only use the first version of Python to do the formatting
  and linting and to produce the coverage report.
  There's no point in formatting the code for each version of Python,
  and I judged that the costs of linting the code for each version would outweight the benefits.
  Coverage is combined across all versions of Python but we only need to use
  one version of Python produce the _coverage report_, which is what
  `coverage.in` and `coverage.txt` are used for.
* You can still have conditional dependencies:
  just use an environment marker like `foo ;python_version<"2.7"` in one of your
  `requirements/*.in` files. You don't need separate requirements.in files for
  each version of Python to do this.
* `bin/make_requirements` runs `pip-compile` in pyenv because you need to run
  `pip-compile` with the version of Python that you're compiling for.
  But it _does not_ run `pip-compile` in tox: it's not necessary to install and
  run `pip-compile` in the actual venv.
* It's not really necessary to use symlinks. `make requirements` could just *copy*
  the requirements.in files into the subdirs. But then I'd worry about Dependabot
  sending PRs that update those copied requirements.in files and get them out of
  sync with the master ones.

### Makefile

[The `Makefile`](Makefile) is little more than a collection of handy aliases
for running the project's most common commands. Of particular interest are:

* `make lint format test functests` runs the linting,
  code formatting, unit tests and functional tests,
  all **with the first version of Python only**.
* `make sure` runs the linting, code formatting, unit tests
  and functional tests with the first version of Python only and then
  **runs the unit and functional tests with each other version of Python**,
  and also runs the coverage report (which reports the combined coverage of the
  unit tests across all versions of Python)
* `make help` prints a list of all the `make` commands

Unlike our other projects the `Makefile` in this project runs tox _without_ the
`-q` / `--quiet` argument so there's a little bit more output but users aren't
left staring at a blank terminal while pyenv installs versions of Python or tox
installs the project's dependencies.

### Coverage

`make test coverage` will fail if you have some code that's not executed in the
first version of Python because those lines won't be covered. The project
measures coverage across all versions of Python and combines the results. To
get the full coverage report you have to run `make sure`.
Or to run just the unit tests (not everything else):
`tox -e '{py310,py39,py38}-tests,coverage'`.

### TODO: GitHub Actions

### TODO: Deal with duplication of the Python versions

The list of Python versions is duplicated in several places:

* The `.python_version` file lists them all (in full format: `3.10.4` etc)

* The `Makefile` contains them in tox's short format because
  it contains lots of tox commands like `tox -e py39-tests`. For example
  this is `make sure`:

  ```make
  .PHONY: sure
  sure: checkformatting lint test functests
      pyenv exec tox -e py39-tests
      pyenv exec tox -e py38-tests
      pyenv exec tox -e coverage
      pyenv exec tox -e py39-functests
      pyenv exec tox -e py38-functests
  ```
* The `tox.ini` file contains `py310-tests` as the default `envlist` and it
  also uses the different Python versions to refer to the requirements files:

  ```ini
  deps =
      lint: -r requirements/py310/lint.txt
      {format,checkformatting}: -r requirements/py310/format.txt
      coverage: -r requirements/py310/coverage.txt
      py310-dev: -r requirements/py310/dev.txt
      py310-tests: -r requirements/py310/tests.txt
      py310-functests: -r requirements/py310/functests.txt
      py39-dev: -r requirements/py39/dev.txt
      py39-tests: -r requirements/py39/tests.txt
      py39-functests: -r requirements/py39/functests.txt
      py38-dev: -r requirements/py38/dev.txt
      py38-tests: -r requirements/py38/tests.txt
      py38-functests: -r requirements/py38/functests.txt
  ```

* The GitHub Actions workflow

I think the way to deal with all this is by **templating** all of these files
using cookiecutter.
The single source of truth for the list of Python versions will be in the
template variables and templates will produce `.python_version`, `Makefile`,
`tox.ini`, and other files based on these variables.
Changing the project's Python versions will involve changing the template
variables (these are currently stored in a `.cookiecutter.json` file if using
h-cookiecutter-pypackage and the `hdev template` command) and then re-running
the cookiecutter.

Allowing yourself to have repetitive, duplicative stuff in all these files
really frees you up: the various files can be much simpler, and you're free
from the difficult task of avoiding duplication or repetitiveness across a
variety of different file formats.

### tox-pip-sync

Is broken?

### Dependabot :(

### Operating system-dependent requirements :(

What about Pipenv and Poetry?
-----------------------------
