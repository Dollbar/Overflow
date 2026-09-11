"""Exercise burst build freshness, failed attempts and real consumer suppression."""

from dataclasses import replace
import fcntl
from pathlib import Path
import sys
import tempfile
import unittest

try:
    from scripts.burst_build_identity import BurstContext, SOURCES, run_stage
except ImportError:
    BurstContext = run_stage = None
    SOURCES = ()


class BurstIdentityTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(run_stage, "burst consumers lack a build identity guard")
        self.temp = tempfile.TemporaryDirectory(prefix="ualink-burst-identity-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        for name in SOURCES:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture input " + name)
        self.lib = Path(self.temp.name) / "mapping.lib"
        self.lib.write_text("authorized fixture library")
        self.analysis = Path(self.temp.name) / "analysis.lib"
        self.analysis.write_text("analysis fixture")
        self.run = self.root / "build" / "burst"
        self.context = BurstContext(self.root, self.run, self.lib,
                                    {"ports": "2", "credit_width": "4", "mapping_corner": "ssg0p81vm40c"},
                                    Path(sys.executable), self.analysis)
        self.marker = self.root / "consumer_ran"
        self.consume = [sys.executable, "-c", f"from pathlib import Path;Path({str(self.marker)!r}).write_text('ran')"]
        self.produce = [sys.executable, "-c", "from pathlib import Path;"
                        + f"p=Path({str(self.run)!r});"
                        + "[(p/n).write_text('fresh '+n) for n in ('mapped.v','mapped.json','area.json')]"]

    def test_missing_identity_stops_consumer_even_with_netlist(self):
        self.run.mkdir(parents=True)
        (self.run / "mapped.v").write_text("unbound")
        with self.assertRaises(ValueError):
            run_stage("sta", self.context, self.consume)
        self.assertFalse(self.marker.exists())

    def test_fresh_build_allows_consumer_and_archives_previous_attempt(self):
        self.assertEqual(run_stage("synth", self.context, self.produce), 0)
        self.assertEqual(run_stage("equiv", self.context, self.consume), 0)
        self.assertTrue(self.marker.exists())
        self.assertEqual(run_stage("synth", self.context, self.produce), 0)
        archives = list((self.run / "previous_build").glob("*/mapped.v"))
        self.assertEqual(len(archives), 1)
        self.assertEqual(archives[0].read_text(), "fresh mapped.v")

    def test_source_library_parameter_and_output_drift_stop_consumer(self):
        for change in ("source", "library", "parameters", "output"):
            with self.subTest(change=change):
                run_stage("synth", self.context, self.produce)
                context = self.context
                if change == "source":
                    (self.root / SOURCES[0]).write_text("changed RTL")
                elif change == "library":
                    self.lib.write_text("changed mapping library")
                elif change == "parameters":
                    context = replace(context, parameters=dict(context.parameters, ports="4"))
                else:
                    (self.run / "mapped.v").write_text("changed netlist")
                with self.assertRaises(ValueError):
                    run_stage("sta", context, self.consume)
                self.assertFalse(self.marker.exists())

    def test_failed_rebuild_cannot_leave_old_ready_artifacts(self):
        run_stage("synth", self.context, self.produce)
        self.assertEqual(run_stage("synth", self.context, [sys.executable, "-c", "raise SystemExit(7)"]), 7)
        with self.assertRaises(ValueError):
            run_stage("sta", self.context, self.consume)
        self.assertFalse(self.marker.exists())

    def test_zero_exit_without_all_outputs_is_not_a_successful_build(self):
        with self.assertRaises(ValueError):
            run_stage("synth", self.context, [sys.executable, "-c", "pass"])
        with self.assertRaises(ValueError):
            run_stage("equiv", self.context, self.consume)
        self.assertFalse(self.marker.exists())

    def test_input_or_analysis_library_change_during_tool_execution_is_rejected(self):
        run_stage("synth", self.context, self.produce)
        for path in (self.root / SOURCES[0], self.analysis):
            command = [sys.executable, "-c", f"from pathlib import Path;Path({str(path)!r}).write_text('drifted')"]
            with self.assertRaises(ValueError):
                run_stage("sta", self.context, command)
            run_stage("synth", self.context, self.produce)

    def test_concurrent_stage_cannot_enter_existing_locked_build(self):
        run_stage("synth", self.context, self.produce)
        with (self.run / "build_identity.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(ValueError):
                run_stage("sta", self.context, self.consume)
        self.assertFalse(self.marker.exists())

    def test_broad_or_escaping_build_path_is_rejected(self):
        for run in (self.root, self.root / "build", Path(self.temp.name) / "outside"):
            with self.assertRaises(ValueError):
                run_stage("synth", replace(self.context, run_dir=run), self.produce)

    def test_sizing_tool_and_script_drift_require_new_synthesis(self):
        self.assertIn("sizing_tool", BurstContext.__dataclass_fields__, "STA sizing is not bound to synthesis identity")
        tool = self.root / "fixture_sta"
        tool.write_text("synthetic tool identity")
        context = replace(self.context, sizing_tool=tool)
        script = self.root / "scripts" / "size_burst_control.tcl"
        for changed in (tool, script):
            run_stage("synth", context, self.produce)
            changed.write_text("changed sizing input")
            with self.assertRaises(ValueError):
                run_stage("equiv", context, self.consume)
            self.assertFalse(self.marker.exists())

    def test_dangling_output_symlink_cannot_be_used_by_synthesis(self):
        self.run.mkdir(parents=True)
        outside = Path(self.temp.name) / "outside_netlist"
        (self.run / "mapped.v").symlink_to(outside)
        with self.assertRaises(ValueError):
            run_stage("synth", self.context, self.produce)
        self.assertFalse(outside.exists())


if __name__ == "__main__":
    unittest.main()
