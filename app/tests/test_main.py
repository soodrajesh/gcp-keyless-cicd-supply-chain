import main


def test_reports_build_identity(monkeypatch):
    monkeypatch.setenv("GIT_SHA", "abc1234")
    monkeypatch.setenv("RUN_URL", "https://github.com/o/r/actions/runs/1")
    body = main.app.test_client().get("/").get_json()
    assert body == {
        "service": "keyless-demo",
        "version": "abc1234",
        "built_by": "https://github.com/o/r/actions/runs/1",
    }


def test_unknown_build_is_explicit_not_empty(monkeypatch):
    monkeypatch.delenv("GIT_SHA", raising=False)
    assert main.app.test_client().get("/").get_json()["version"] == "unknown"
