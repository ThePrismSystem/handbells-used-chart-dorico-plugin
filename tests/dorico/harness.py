"""Helpers for in-Dorico suites that run several cases on one scratch copy and look at it through the Remote API."""
import json
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools" / "dorico"))
import dws  # noqa: E402
import run_lua  # noqa: E402
import snap  # noqa: E402

FIXTURE = ROOT / "fixtures" / "handbells-fixture.dorico"
SCRATCH = run_lua.RUN_DIR / "scratch.dorico"
CROP = ROOT / "tools" / "dorico" / "crop.ps1"


def check(test, result, name):
    test.assertIsNotNone(result, f"{name} wrote no result")
    failed = [c for c in result.get("checks", []) if not c["ok"]]
    test.assertTrue(result.get("ok"), json.dumps({"error": result.get("error"), "failed": failed,
                                                  "facts": result.get("facts")}, indent=1)[:5000])
    return result


@contextmanager
def scratch(test, case, open_file=FIXTURE, args=None, timeout=600):
    """Open a copy, run the first case on it, keep it open for more, and close it (unsaved) at the end."""
    client = dws.DoricoClient()
    client.connect()
    score_id = None
    result = None
    try:
        code, result, score_id = run_lua.run(HERE / case, open_file=open_file, keep_open=True, extra_args=args or {},
                                             timeout=timeout, client=client)
        facts = (result or {}).get("facts") or {}
        score_id = facts.get("scratchScoreID", score_id)
        yield client, check(test, result, case)
    finally:
        if result and ((result.get("facts") or {}).get("scratchVerified")):
            run_lua.close_scratch(client, score_id)
        client.close()


def run_more(test, client, case, args=None, timeout=600, expect_ok=True):
    """Run another case on the copy that is still open (the probe confirms it is the active project)."""
    extra = dict(args or {})
    extra["expectScratch"] = {"path": run_lua.fwd(SCRATCH)}
    code, result, _ = run_lua.run(HERE / case, on_active=True, extra_args=extra, timeout=timeout, client=client)
    if expect_ok:
        return check(test, result, case)
    return result


CLICK = ROOT / "tools" / "dorico" / "click.ps1"
CAPTURE = ROOT / "tools" / "dorico" / "capture.ps1"


def click(window, button):
    proc = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(CLICK),
                           "-Window", window, "-Button", button], capture_output=True, text=True)
    return proc.returncode == 0


def wait_for_window(timeout=90, title=None, besides=()):
    """The first window titled `title` (or, without one, any title not in `besides`) to appear, else None."""
    import time
    deadline = time.time() + timeout
    while time.time() < deadline:
        for t in run_lua.window_titles():
            if (title is not None and t == title) or (title is None and t not in besides and t):
                return t
        time.sleep(1)
    return None


def capture_window(title, out):
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(CAPTURE), "-Out", str(out),
                    "-TitleLike", title], capture_output=True, text=True)


class Background:
    """Runs a call on a thread (a case that waits on one of Dorico's dialogs) and hands back its result."""

    def __init__(self, fn):
        import threading
        self.result = None
        self.thread = threading.Thread(target=self._run, args=(fn,))
        self.thread.start()

    def _run(self, fn):
        self.result = fn()

    def join(self, timeout=None):
        self.thread.join(timeout)
        return self.result


def options(client, kind, key, ident):
    client.send({"message": "getoptions", "optionsType": kind, key: ident})
    while True:
        reply = client.recv()
        if reply.get("message") == "optionslist":
            return {o["path"]: o.get("currentValue") for o in reply["options"]}
        # a late kOK for an earlier command (one sent from a background run) is not this request's answer
        if reply.get("message") == "response" and reply.get("code") != "kOK":
            raise RuntimeError(f"getoptions {kind} {ident}: {reply}")


def capture(client, out, x=340, y=330, width=1150, height=900):
    """Page 1, cropped to the music area."""
    whole = run_lua.RUN_DIR / "capture-whole.png"
    snap.snap(whole, zoom="whole", client=client)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(CROP), "-In", str(whole),
                    "-Out", str(out), "-X", str(x), "-Y", str(y), "-Width", str(width), "-Height", str(height)],
                   check=True, capture_output=True)
