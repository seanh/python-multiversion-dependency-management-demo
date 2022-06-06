import sys

from flask import Flask

app = Flask(__name__)


@app.route("/")
def hello_world():
    if sys.version.startswith("3.9"):
        return "<p>Hello, Python 3.9!</p>"

    if sys.version.startswith("3.8"):
        return "<p>Hello, Python 3.8!</p>"

    return "<p>Hello, Python!</p>"
