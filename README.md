Python Multi-version Dependency Pinning Demo
============================================

A failed attempt to figure out how a Python project can pin its dependencies
while also supporting multiple versions of Python, using
[pip-tools](https://pip-tools.readthedocs.io/) and Dependabot.

This ultimately fails because Dependabot doesn't support compiling different
requirements files with different versions of Python when using `pip-compile`.
I'm not sure it supports compiling the `prod.txt` file from `setup.cfg` (rather
than `prod.in`) either.

I think you might be able to do pinned requirements for multiple versions of
Python if using Poetry and Dependabot rather than pip-tools, see below.

How it works
------------

### pyenv and `make python`

You need to install [pyenv](https://github.com/pyenv/pyenv) but the `Makefile`
will handle calling pyenv to install the necessary versions of Python for you:

* The [`.python-version` file](.python-version) lists all the versions of Python
  that the project needs

* `make python` calls [`bin/make_python`](bin/make_python) which loops over all
  the Python versions listed in the `.python-version` file and installs each
  version in pyenv if it isn't installed already. It also installs tox in
  pyenv

The `Makefile` then runs tox commands with `pyenv exec tox ...` instead of just
running `tox` directly so that you don't need to have pyenv's shell integration
("shims") set up (see
[Using pyenv without shims](https://github.com/pyenv/pyenv#using-pyenv-without-shims)).

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

* The `requirements/py*/prod.txt` files are compiled from the
  `install_requires` dependencies in `setup.cfg` which contains only the
  top-level production dependencies, unpinned.

  This is necessary if you want your project to be an installable Python package:
  the dependencies need to be in the setuptools `install_requires` setting.
  It's not possible to get the `setup.cfg` file to read the `install_requires` dependencies from a file
  (see for example <https://github.com/pypa/setuptools/issues/1951> and <https://github.com/pypa/setuptools/issues/1074>).
  There is [a setuptools plugin to enable it](https://pypi.org/project/setuptools-declarative-requirements/)
  or you can hack it yourself using a `setup.py` file
  ([example](https://github.com/ppb/ppb-vector/blob/canon/setup.py#L5-L22),
  [another example](https://github.com/jsiverskog/pc-nrfutil/blob/fe735bbf606156bcf8222f894efcd004514cb6fe/setup.py),
  [another example](https://stackoverflow.com/questions/49689880/proper-way-to-parse-requirements-file-after-pip-upgrade-to-pip-10-x-x/59971236#59971236)).
  But a better approach is to go the other way: `pip-compile` can read the
  input dependencies from a `setup.cfg` file and write out a requirements.txt
  file with a command like this:
  `pip-compile --output-file requirements/py310/prod.txt setup.cfg`.

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

* The `pip-compile` commands in `make_requirements` use
  [`pip-compile`'s `--generate-hashes` option](https://github.com/jazzband/pip-tools#using-hashes)
  to generate requirements.txt files using [pip's hash-checking mode](https://pip.pypa.io/en/stable/topics/secure-installs/#hash-checking-mode)
  to protect against remote tampering and networking issues.

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
  unit tests across all versions of Python).

  `make sure` uses tox to run everything in parallel which is much faster.
  This does require your different tox environments to be capable of running in
  parallel with each other.  For example if your tests use a test database then
  it might not be possible to run multiple instances of the tests (for
  different versions of Python) at the same time if they're all going to be
  using the same test DB.

  This could perhaps be handled by using tox's [`depends` setting](https://tox.wiki/en/latest/config.html#conf-depends).
  Something like this should prevent tox from running more than one instance of
  the unit tests or functests at once while still retaining as much parallelism
  as possible:

  ```ini
  depends =
      py310-tests: {py39,py38}-tests
      py39-tests: {py310,py38}-tests
      py38-tests: {py310,py39}-tests
      py310-functests: {py39,py38}-functests
      py39-functests: {py310,py38}-functests
      py38-functests: {py310,py39}-functests
      coverage: {py310,py39,py38}-tests
  ```

### Coverage

`make test coverage` will fail if you have some code that's not executed in the
first version of Python because those lines won't be covered. The project
measures coverage across all versions of Python and combines the results. To
get the full coverage report you have to run `make sure`. Or to run just the
unit tests (not everything else): `tox -e '{py310,py39,py38}-tests,coverage'`.

### `tox.ini`

Some notes:

* You always have to specify the version of Python when running the dev server, unit tests, or functional tests.
  For example there's no `tox -e tests`, it's always `tox -e py310-tests`
  (although `py310-tests` is the default envlist so just `tox` is equivalent to `tox -e py310-tests`).

  This is not necessary for things that only run in one version of Python:
  formatting, linting, and producing the coverage report are just
  `tox -e format,lint,coverage` (which will run them with the first version in the `.python_version` file).

* Both `make sure` and GitHub Actions use tox to run everything in parallel which is much faster.

  One nice thing about how tox does this is that by default
  (if you don't put `parallel_show_output = true` in your `tox.ini`)
  it only prints the output of any envs that failed, not the ones that succeeded.
  This makes the logs in your terminal or in GitHub Actions much shorter.

* I'm using [`pip-sync`](https://pip-tools.readthedocs.io/en/latest/#example-usage-for-pip-sync)
  to automatically update the virtualenvs whenever the requirements.txt files
  change.

  The trick here is to *not* put `-r requirements/foo.txt` lines in the `deps` section in `tox.ini`.
  Instead just put `pip-tools` in the `deps` and then put `pip-sync
  requirements/foo.txt` commands in the `commands_pre` section.
  So we're relieving tox of the duty of installing and updating our
  dependencies and calling `pip-sync` to do that for us instead:

  ```tox.ini
  deps = pip-tools
  commands_pre =
      lint:                     pip-sync --pip-args '--disable-pip-version-check' requirements/py310/lint.txt
      {format,checkformatting}: pip-sync --pip-args '--disable-pip-version-check' requirements/py310/format.txt
      coverage:                 pip-sync --pip-args '--disable-pip-version-check' requirements/py310/coverage.txt
      py310-dev:                pip-sync --pip-args '--disable-pip-version-check' requirements/py310/dev.txt
      ...
  ```

* Normally tox would install the package-under-test (the Python package at `src/python_multiversion_dependency_management_demo`)
  into the virtualenv but then the `pip-sync` commands that I'm running in
  `pre_commands` would uninstall it again!

  I've hacked around this by putting `skipsdist = true` in `tox.ini`.
  This tells tox not to build and install the package under test.
  I then add the environment variable `PYTHONPATH = src` so that
  the tests can `import python_multiversion_dependency_management_demo`.

  This is not ideal:
  you want tox to build the Python package and install it into the test venv
  and run the tests against the installed copy of the package, instead of
  against the copy in the `src` dir. This is part of the reason for the `src`
  dir layout, it protects against packaging issues (for example if you don't do
  this the tests could be passing but the code could be depending on a file
  that isn't actually making it into the built package, so the package would
  actually be broken).

  So it'd be good to find a better solution to this.

* Note that if I didn't have `skipsdist = true` (which implies `skip_install = true`)
  I would want to add `skip_install = true` to `tox.ini` for the `format`,
  `checkformatting` and `coverage` environments because these operations don't
  require the package to be installed:

  ```ini
  [testenv]
  skip_install =
      {format,checkformatting,coverage}: true
  ...
  ```

### GitHub Actions

[The GitHub Actions workflow](.github/workflows/test.yml) is pretty simple
(just 23 lines): it installs each of the versions of Python (using
the `setup-python` action), runs `pip install tox`, and then runs
a single tox command to run everything in parallel (formatting,
linting, unit tests for all Python versions, coverage, functests
for all Python versions).

The other way to do this would be to use multiple GitHub Actions jobs to run
things in parallel but that would likely be slower because each job boots its
own VM and it would compete for a scarce resource:
we're [limited to 60 concurrent jobs](https://docs.github.com/en/actions/learn-github-actions/usage-limits-billing-and-administration)
across our GitHub organization.

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

* The GitHub Actions workflow has to install each version of Python and also
  has to mention the version in its tox command

My totally untested idea for how to handle this is by templating all of these
files using [cookiecutter](https://github.com/cookiecutter/cookiecutter).
The single source of truth for the list of Python versions will be in the
cookiecutter template variables and templates will produce `.python_version`,
`Makefile`, `tox.ini`, and other files based on these variables.  Changing the
project's Python versions will involve changing the template variables in the
`cookiecutter.json` file and then re-running the cookiecutter.

My hope is that allowing ourselves to have repetitive, duplicative stuff in all
these files really frees you up: the various files can be much simpler, and
you're free from the difficult task of avoiding duplication or repetitiveness
across a variety of different file formats.

### Dependabot :(

If you're using `pip-compile` to generate different requirements files for
different versions of Python then you can't use Dependabot because it won't
know which version of Python to compile which requirements file with.
Dependabot will just compile all your requirements files with the first version
of Python from your `.python_version` file, which will break them.
There are lots of issues about this in Dependabot's GitHub issues, here's a couple:

https://github.com/dependabot/dependabot-core/issues/4216
https://github.com/dependabot/dependabot-core/issues/4607

That's already fatal but it gets worse.
Dependabot also doesn't understand compiling a requirements.txt file from input
dependencies in a `setup.cfg` file:
https://github.com/dependabot/dependabot-core/issues/1475

And worse:
pip-tools doesn't provide a solution for the problem of multiple versions of Python.
They just [document](https://pip-tools.readthedocs.io/en/latest/#cross-environment-usage-of-requirements-in-requirements-txt-and-pip-compile)
that pip-compile needs to be run with the right version of Python and leave it
up to you to figure that out:

> The dependencies of a package can change depending on the Python environment
> in which it is installed. Here, we define a Python environment as the
> combination of Operating System, Python version (3.7, 3.8, etc.), and Python
> implementation (CPython, PyPy, etc.). For an exact definition, refer to the
> possible combinations of PEP 508 environment markers.
>
> As the resulting requirements.txt can differ for each environment, users must
> execute pip-compile on each Python environment separately to generate a
> requirements.txt valid for each said environment...

This leaves the user to invent their own scheme for how they'll lay out their
requirements files (like the `requirements/pyXY/` subdirs in this repo) and how
they'll handle compiling them (our `make requirements` script).

Unfortunately once you've invented a custom scheme like this, Dependabot won't
understand it. In this repo I get this error from Dependabot:

> **Dependabot couldn't find a prod.txt**
>
> Dependabot couldn't find a prod.txt.
>
> Dependabot requires a prod.txt to evaluate your Python dependencies. It had
> expected to find one at the path: /requirements/prod.txt.
>
> If this isn't a Python project, you may wish to disable updates for it in the
> .github/dependabot.yml config file in this repo.

### Operating system-dependent requirements :(

[PEP 508 environment markers](https://peps.python.org/pep-0508/#environment-markers)
can vary a package's dependencies not only depending on the version of Python
but also depending on the operating system, operating system version, processor
architecture, or Python implementation. To fully support these you'd not only
need to compile a separate requirements file for each version of Python but for
each specific environment: each combination of OS, CPU architecture, Python
version, etc.

### Testing against multiple versions of a library :(

tox has a feature called [generate envlists](https://tox.wiki/en/latest/config.html#generating-environments-conditional-settings)
where it can run your tests against multiple different versions of a dependency
(or against combinations of different versions of multiple dependencies and of
Python itself). Here's an example from tox's docs:

```ini
[tox]
envlist = {py27,py36}-django{15,16}

[testenv]
deps =
    pytest
    django15: Django>=1.5,<1.6
    django16: Django>=1.6,<1.7
    py36: unittest2
commands = pytest
```

I can certainly imagine why you might want to test against multiple different
versions of a dependency but this seems incompatible with the idea of pinning
your dependencies. A pinned `requirements.txt` file lists exact versions of all
your dependencies (and their dependencies), whereas a generative envlist lists
multiple different versions of one or more dependencies.

So it seems that if you want to pin your dependencies you may need to give up
the ability to test against multiple versions of a dependency?
Or maybe there is some way to get `pip-sync` and tox to work together here?
But it certainly feels like going against the grain.

What about Pipenv and Poetry?
-----------------------------

I've heard enough reports about problems with Pipenv that I didn't seriously
consider it.

[Poetry](https://python-poetry.org/) looks really nice though and I think it
may make it possible to support multiple versions of Python while pinning your
dependencies and working with Dependabot.
Pinning dependencies across multiple versions of Python is just what Poetry does,
you don't need to invent a whole scheme of your own for compiling multiple
requirements files like you do with `pip-compile`.
You define the versions of Python that your project supports in the Poetry
settings in your `pyproject.toml` file and Poetry builds a single `poetry.lock`
file that can be used (with `poetry install`) to install your dependencies in
any of your supported versions of Python.
When there are differences between versions of Python (a dependency is only
needed in some versions of Python, or different versions of a dependency are
needed in different versions of Python) these conditionals are expressed in the
`poetry.lock` file.
Poetry can either export a `poetry.lock` file into a `requirements.txt` format
that you can install with `pip` (unlike `pip-compile` Poetry generates a single
`requirements.txt` file for all supported versions of Python: any necessary
conditionals are compiled into the file as PEP 508 environment markers).
And Dependabot has built-in support for Poetry. I haven't tried it but I'm guessing Dependabot
knows how to update a `poetry.lock` file covering mulitple versions of Python.
Unlike `pip-compile` Poetry makes this easy: all Dependabot has to do is run `poetry update`.

Poetry is beyond the scope of this investigation:
there'd be all sorts of decisions and consequences involved in moving our
projects from `pip-tools` to Poetry (whether Poetry on its own or Poetry in
combination with tox).

Perhaps another day
