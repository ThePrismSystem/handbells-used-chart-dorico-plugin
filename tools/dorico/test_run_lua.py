import io
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import run_lua  # noqa: E402


@unittest.skipUnless(run_lua.find_luac(), "luac52 not installed")
class SyntaxCheckTests(unittest.TestCase):
    def write(self, text, folder=None):
        fd, path = tempfile.mkstemp(suffix=".lua", dir=folder)
        with os.fdopen(fd, "w") as f:
            f.write(text)
        self.addCleanup(os.remove, path)
        return Path(path)

    def test_valid_script_has_no_error(self):
        self.assertIsNone(run_lua.syntax_error(self.write('local x = "a/b"\nreturn x\n')))

    def test_lua_files_include_plugin(self):
        names = {Path(f).name for f in run_lua.lua_files_for(run_lua.REPO / "spike" / "00_smoke.lua")}
        for name in ("Handbells Used Chart.lua", "main.lua", "doc.lua", "cases.lua"):
            self.assertIn(name, names)

    def test_bad_escape_is_reported(self):
        err = run_lua.syntax_error(self.write('local x = "\\hbuc"\n'))
        self.assertIsNotNone(err)
        self.assertIn("invalid escape", err)

    def test_bad_library_beside_the_script_is_reported(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(lambda: os.rmdir(folder))
        script = self.write("return 1\n", folder)
        lib_dir = Path(folder) / "lib"
        lib_dir.mkdir()
        self.addCleanup(lambda: os.rmdir(lib_dir))
        bad = lib_dir / "broken.lua"
        bad.write_text("local = 1\n")
        self.addCleanup(bad.unlink)
        err = run_lua.syntax_error(script)
        self.assertIsNotNone(err)
        self.assertIn("broken.lua", err)


class ScriptHeaderTests(unittest.TestCase):
    def test_scripts_add_to_package_path_only_once(self):
        # Dorico keeps one Lua state for every script run, so a bare prepend grows package.path on each run
        bare = []
        for folder in ("spike", "tests/dorico", "fixtures"):
            for path in sorted((run_lua.REPO / folder).rglob("*.lua")):
                for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                    if line.startswith("package.path = "):
                        bare.append(f"{path.relative_to(run_lua.REPO)}:{n}")
        self.assertEqual(bare, [])


class FakeClient:
    """Stands in for DoricoClient: records commands, simulates an open and a script run."""

    def __init__(self, run_dir, result_for=None, opened_id=7):
        self.run_dir = Path(run_dir)
        self.commands = []
        self.result_for = result_for  # callable(args) -> result dict, or None for "never finishes"
        self.opened_id = opened_id
        self.active = 0

    def status(self):
        return {"hasScore": True, "activeOpenScoreID": self.active}

    def settle(self):
        self.commands.append("<settled>")
        return True

    def command(self, cmd):
        self.commands.append(cmd)
        if cmd.startswith("File.Open"):
            self.active = self.opened_id
        if cmd.startswith("Script.RunScript") and self.result_for:
            (self.run_dir / "result.json").write_text(json.dumps(self.result_for(self.args(cmd))), encoding="utf-8")
        return {"message": "response", "code": "kOK"}

    def launcher(self, cmd):
        return Path(re.search(r"ScriptPath=(.*?)&", cmd).group(1))

    def args(self, cmd):
        args_path = re.search(r"args = \[==\[(.*?)\]==\]", self.launcher(cmd).read_text(encoding="utf-8")).group(1)
        return json.loads(Path(args_path).read_text(encoding="utf-8"))

    def closes(self):
        return [c for c in self.commands if c.startswith("File.CloseProject")]


class RunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.run_dir = Path(self.tmp.name) / "hbuc-run"
        patcher = mock.patch.object(run_lua, "RUN_DIR", self.run_dir)
        patcher.start()
        self.addCleanup(patcher.stop)
        mock.patch.object(run_lua, "syntax_error", return_value=None).start()
        mock.patch.object(run_lua, "answer_known_prompts", return_value=None).start()
        mock.patch.object(run_lua, "window_titles", return_value=[]).start()
        self.addCleanup(mock.patch.stopall)
        self.script = Path(self.tmp.name) / "probe.lua"
        self.script.write_text("return 1\n")
        self.source = Path(self.tmp.name) / "fixture.dorico"
        self.source.write_bytes(b"PK")

    def ok_result(self, verified):
        return lambda args: {"runId": args["runId"], "ok": True, "checks": [], "facts": {"scratchVerified": verified}}

    def test_verified_scratch_is_closed_without_saving(self):
        client = FakeClient(self.run_dir, self.ok_result(True))
        code, result, sid = run_lua.run(self.script, open_file=self.source, client=client)
        self.assertEqual(code, 0)
        self.assertEqual(client.closes(), ["File.CloseProject?OpenScoreID=7&Save=false"])

    def test_closes_the_id_the_probe_confirmed(self):
        # The id seen while opening is only a guess; the probe reads the verified copy's own openScoreID.
        def confirmed(args):
            return {"runId": args["runId"], "ok": True, "checks": [], "facts": {"scratchVerified": True, "scratchScoreID": 9}}

        client = FakeClient(self.run_dir, confirmed)
        run_lua.run(self.script, open_file=self.source, client=client)
        self.assertEqual(client.closes(), ["File.CloseProject?OpenScoreID=9&Save=false"])

    def test_close_is_retried_until_the_copy_is_gone(self):
        # Dorico can ignore a close sent while it is still finishing the script run.
        titles = iter([[], ["Song in scratch*"], []])
        with mock.patch.object(run_lua, "window_titles", side_effect=lambda: next(titles)), \
                mock.patch.object(run_lua.time, "sleep", return_value=None):
            client = FakeClient(self.run_dir, self.ok_result(True))
            run_lua.run(self.script, open_file=self.source, client=client)
        self.assertEqual(len(client.closes()), 2)

    def test_refuses_while_a_scratch_copy_is_still_open(self):
        # Copying over scratch.dorico under an open copy makes Dorico ask about a file modified on disk.
        with mock.patch.object(run_lua, "window_titles", return_value=["Song in scratch*", "Fugue in Bach"]):
            client = FakeClient(self.run_dir, self.ok_result(True))
            code, result, sid = run_lua.run(self.script, open_file=self.source, client=client)
        self.assertEqual(code, 2)
        self.assertEqual(client.closes(), [])
        self.assertFalse(any("File.Open" in c for c in client.commands))

    def test_unverified_project_is_never_closed(self):
        client = FakeClient(self.run_dir, self.ok_result(False))
        code, result, sid = run_lua.run(self.script, open_file=self.source, client=client)
        self.assertEqual(client.closes(), [])
        self.assertEqual(code, 2)

    def test_expected_scratch_is_passed_to_the_probe(self):
        seen = {}

        def capture(args):
            seen.update(args)
            return {"runId": args["runId"], "ok": True, "checks": [], "facts": {"scratchVerified": True}}

        run_lua.run(self.script, open_file=self.source, client=FakeClient(self.run_dir, capture))
        self.assertTrue(seen["expectScratch"]["path"].endswith("/scratch.dorico"))

    def test_timeout_returns_2_and_does_not_close(self):
        client = FakeClient(self.run_dir, result_for=None)
        code, result, sid = run_lua.run(self.script, open_file=self.source, client=client, timeout=1)
        self.assertEqual(code, 2)
        self.assertIsNone(result)
        self.assertEqual(client.closes(), [])

    def test_keep_open_skips_close(self):
        client = FakeClient(self.run_dir, self.ok_result(True))
        run_lua.run(self.script, open_file=self.source, keep_open=True, client=client)
        self.assertEqual(client.closes(), [])

    def test_stale_result_with_another_run_id_is_ignored(self):
        self.run_dir.mkdir(parents=True)
        client = FakeClient(self.run_dir, result_for=lambda args: {"runId": "old", "ok": True, "facts": {}})
        code, result, sid = run_lua.run(self.script, client=client, on_active=True, timeout=1)
        self.assertEqual(code, 2)
        self.assertIsNone(result)

    def test_a_new_copy_settles_before_the_script_runs(self):
        # Dorico goes on laying out a large project after its id appears; a script sent at once found the text
        # export writing nothing.
        client = FakeClient(self.run_dir, self.ok_result(True))
        run_lua.run(self.script, open_file=self.source, client=client)
        run_at = next(i for i, c in enumerate(client.commands) if c.startswith("Script.RunScript"))
        self.assertIn("<settled>", client.commands[:run_at])

    def test_each_run_launches_its_own_args(self):
        # A script Dorico runs late, after the runner gave up on it, must not take a later run's args and runId.
        client = FakeClient(self.run_dir, self.ok_result(True))
        run_lua.run(self.script, open_file=self.source, client=client)
        first = [c for c in client.commands if c.startswith("Script.RunScript")][0]
        launcher = client.launcher(first)
        self.assertEqual(launcher.parent, self.run_dir)
        text = launcher.read_text(encoding="utf-8")
        self.assertIn(run_lua.fwd(self.script), text, "the launcher runs the script")
        self.assertIn("HBUC_RUN = nil", text, "and forgets the run afterwards, in Dorico's one Lua state")
        first_id = client.args(first)["runId"]
        later = FakeClient(self.run_dir, self.ok_result(True))
        run_lua.run(self.script, open_file=self.source, client=later)
        second = [c for c in later.commands if c.startswith("Script.RunScript")][0]
        self.assertNotEqual(first_id, later.args(second)["runId"])
        self.assertFalse(launcher.exists(), "an earlier run's launcher is cleared away")

    def test_timeout_names_the_open_windows_and_a_bad_result(self):
        class Broken(FakeClient):
            def command(self, cmd):
                reply = super().command(cmd)
                if cmd.startswith("Script.RunScript"):
                    (self.run_dir / "result.json").write_text("{broken", encoding="utf-8")
                return reply

        err = io.StringIO()
        with mock.patch.object(run_lua, "open_windows", return_value=["Delete Flow"]), \
                mock.patch.object(sys, "stderr", err):
            code, result, sid = run_lua.run(self.script, client=Broken(self.run_dir, None), on_active=True, timeout=1)
        self.assertEqual(code, 2)
        self.assertIn("Delete Flow", err.getvalue())
        self.assertIn("result.json could not be read", err.getvalue())

    def test_bad_args_and_runner_errors_exit_3(self):
        with mock.patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(run_lua.main([str(self.script), "--args", "{not json"]), 3)
            with mock.patch.object(run_lua, "run", side_effect=KeyError("x")):
                self.assertEqual(run_lua.main([str(self.script), "--on-active"]), 3)

    def test_run_folder_follows_the_lua_side(self):
        # spike/lib/rundir.lua's order: TEMP, TMP, TMPDIR, then /tmp
        self.assertEqual(run_lua.run_dir_for({"TEMP": "C:/T", "TMP": "C:/U"}), Path("C:/T") / "hbuc-run")
        self.assertEqual(run_lua.run_dir_for({"TMP": "C:/U"}), Path("C:/U") / "hbuc-run")
        self.assertEqual(run_lua.run_dir_for({"TMPDIR": "/var/T"}), Path("/var/T") / "hbuc-run")
        self.assertEqual(run_lua.run_dir_for({}), Path("/tmp") / "hbuc-run")  # noqa: S108  # the fallback under test

    def test_active_project_needs_explicit_opt_in(self):
        client = FakeClient(self.run_dir, self.ok_result(False))
        code, result, sid = run_lua.run(self.script, client=client)
        self.assertEqual(code, 2)
        self.assertFalse(any(c.startswith("Script.RunScript") for c in client.commands))


if __name__ == "__main__":
    unittest.main()
