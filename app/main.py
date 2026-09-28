"""A deliberately tiny service. Its only job is to say which build it is, so the pipeline's
smoke test can prove the deployed revision is the one that was just built and signed."""

from __future__ import annotations

import os

from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(
        service="keyless-demo",
        version=os.environ.get("GIT_SHA", "unknown"),
        built_by=os.environ.get("RUN_URL", "unknown"),
    )
