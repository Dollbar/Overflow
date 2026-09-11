"""Fail-closed build provenance with real temporary files and child processes.

Run: python3 -m unittest verification.tools.test_build_identity -v
Output: unittest results and temporary fixtures, removed by TemporaryDirectory.
Next: exercise real Yosys/OpenSTA targets and their rejection paths.
"""

from dataclasses import replace
import fcntl
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

try:
    from scripts.build_identity import BuildContext, run_stage
except ImportError:
    BuildContext = run_stage = None


class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(run_stage, "source-to-artifact identity gate missing")
        self.temporary = tempfile.TemporaryDirectory(prefix="ualink-identity-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "project"
        for directory in ("scripts", "rtl/upli"):
            shutil.copytree(Path(__file__).resolve().parents[2] / directory, self.root / directory)
        self.run = self.root / "build/mapped"
        self.run.mkdir(parents=True)
        self.kd = self.base / "external"
        for name in ("Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v",
                     "Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v"):
            path = self.kd / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("test fixture dependency\n")
        self.lib = self.base / "mapping.lib"
        self.lib.write_text("test fixture mapping library\n")
        self.context = BuildContext(self.root, self.run, self.kd, self.lib,
                                    {"ports": "1", "width": "32"}, Path(sys.executable))
        self.producer = [sys.executable, "-c",
                         "from pathlib import Path; import sys; p=Path(sys.argv[1]); "
                         "[(p/n).write_text('mapped output '+n) for n in ('mapped.v','mapped.json','area.json')]",
                         str(self.run)]
        self.marker = self.run / "consumer_ran"
        self.consumer = [sys.executable, "-c", "from pathlib import Path; import sys; Path(sys.argv[1]).touch()", str(self.marker)]

    def build(self):
        self.assertEqual(run_stage("synth", self.context, self.producer), 0)

    def test_fresh_build_can_be_consumed_and_records_actual_artifacts(self):
        self.build()
        self.assertEqual(run_stage("equiv", self.context, self.consumer), 0)
        self.assertTrue(self.marker.exists())
        record = json.loads((self.run / "build_identity.json").read_text())
        self.assertEqual(record["status"], "ready")
        self.assertEqual(set(record["artifacts"]), {"mapped.v", "mapped.json", "area.json"})

    def test_missing_manifest_refuses_existing_old_netlist_before_child_runs(self):
        (self.run / "mapped.v").write_text("old netlist")
        with self.assertRaises(ValueError):
            run_stage("sta", self.context, self.consumer)
        self.assertFalse(self.marker.exists())

    def test_modified_rtl_mapping_script_or_gate_rejects_old_build(self):
        for name in ("rtl/upli/upli_receive_fifo.v", "rtl/upli/upli_receive_channel.v",
                     "scripts/buffer_storage.py", "scripts/size_channel.py", "scripts/sta_channel.tcl"):
            with self.subTest(name=name):
                self.build()
                path = self.root / name
                path.write_text(path.read_text() + "\n// changed fixture\n")
                with self.assertRaises(ValueError):
                    run_stage("equiv", self.context, self.consumer)
                self.assertFalse(self.marker.exists())

    def test_parameter_dependency_library_or_tool_drift_rejects_old_build(self):
        self.build()
        with self.assertRaises(ValueError):
            run_stage("sta", replace(self.context, parameters={"ports": "2", "width": "32"}), self.consumer)
        for path in (self.lib, self.kd / "Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v"):
            self.build()
            path.write_text(path.read_text() + "changed\n")
            with self.assertRaises(ValueError):
                run_stage("sta", self.context, self.consumer)
        self.build()
        other_tool = self.base / "different_tool"
        other_tool.write_text("different binary identity")
        with self.assertRaises(ValueError):
            run_stage("sta", replace(self.context, mapping_tool=other_tool), self.consumer)
        self.assertFalse(self.marker.exists())

    def test_modified_or_missing_actual_output_rejects_old_build(self):
        for name in ("mapped.v", "mapped.json", "area.json"):
            self.build()
            (self.run / name).write_text("tampered output")
            with self.assertRaises(ValueError):
                run_stage("equiv", self.context, self.consumer)
        self.build()
        (self.run / "mapped.v").unlink()
        with self.assertRaises(ValueError):
            run_stage("equiv", self.context, self.consumer)
        self.assertFalse(self.marker.exists())

    def test_failed_rebuild_invalidates_the_previous_success(self):
        self.build()
        self.assertEqual(run_stage("synth", self.context, [sys.executable, "-c", "raise SystemExit(7)"]), 7)
        with self.assertRaises(ValueError):
            run_stage("sta", self.context, self.consumer)
        self.assertFalse(self.marker.exists())

    def test_source_change_during_synthesis_cannot_publish_ready_identity(self):
        changed = self.root / "rtl/upli/upli_receive_channel.v"
        command = [sys.executable, "-c", "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('changed during build')", str(changed)]
        self.build()
        with self.assertRaises(ValueError):
            run_stage("synth", self.context, command)
        with self.assertRaises(ValueError):
            run_stage("equiv", self.context, self.consumer)
        self.assertFalse(self.marker.exists())

    def test_consumer_modifying_netlist_cannot_report_success(self):
        self.build()
        command = [sys.executable, "-c", "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('changed during check')", str(self.run / "mapped.v")]
        with self.assertRaises(ValueError):
            run_stage("equiv", self.context, command)

    def test_content_identical_relocation_is_allowed(self):
        self.build()
        moved = self.base / "relocated"
        shutil.copytree(self.root, moved)
        relocated = replace(self.context, root=moved, run_dir=moved / "build/mapped")
        self.assertEqual(run_stage("equiv", relocated, self.consumer), 0)

    def test_failed_validation_does_not_claim_success_or_corrupt_build_identity(self):
        self.build()
        before = (self.run / "build_identity.json").read_bytes()
        self.assertEqual(run_stage("equiv", self.context, [sys.executable, "-c", "raise SystemExit(9)"]), 9)
        self.assertEqual((self.run / "build_identity.json").read_bytes(), before)

    def test_successful_child_without_new_outputs_cannot_relabel_old_netlist(self):
        self.build()
        with self.assertRaises(ValueError):
            run_stage("synth", self.context, [sys.executable, "-c", "pass"])
        self.assertFalse((self.run / "mapped.v").exists())
        saved = list((self.run / "previous_build").glob("*/mapped.v"))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_text(), "mapped output mapped.v")

    def test_concurrent_consumer_or_rebuild_is_rejected_before_child_runs(self):
        self.build()
        with (self.run / "build_identity.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(ValueError):
                run_stage("equiv", self.context, self.consumer)
        self.assertFalse(self.marker.exists())

    def test_invalid_build_directory_cannot_move_source_files(self):
        with self.assertRaises(ValueError):
            run_stage("synth", replace(self.context, run_dir=self.root), self.producer)
        self.assertFalse((self.root / "build_identity.json").exists())

    def test_make_equivalence_refuses_unidentified_netlist_before_running_tool(self):
        library_root = self.base / "libraries"
        library_root.mkdir()
        (library_root / "tcbn28hpcplusbwp40p140ssg0p81vm40c.lib").write_text("test library\n")
        target = self.root / "build/channel_synth_legacy"
        target.mkdir()
        (target / "mapped.v").write_text("old netlist\n")
        probe = self.base / "probe_yosys"
        probe.write_text("#!/usr/bin/env python3\nfrom pathlib import Path\nPath(" + repr(str(self.marker)) + ").touch()\n")
        probe.chmod(0o700)
        result = subprocess.run(["make", "-f", str(self.root / "scripts/channel.mk"), "equiv-channel",
                                 "TAG=legacy", f"KD28_ROOT={self.kd}", f"LIB_ROOT={library_root}", f"YOSYS={probe}"],
                                cwd=self.base, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, "old Makefile invoked the tool with an unidentified netlist")
        self.assertFalse(self.marker.exists(), result.stdout + result.stderr)
        self.assertTrue((self.root / "reports/channel_equiv_legacy.log").is_file(),
                        "standalone consumer must create its report directory before the identity check")


if __name__ == "__main__":
    unittest.main()
