"""Tooling tests: preserve logic/fanout while buffering only the direct guard D."""

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

try:
    from scripts.buffer_reset_guard import buffer_reset_guard
except ModuleNotFoundError as exc:
    if exc.name != "scripts.buffer_reset_guard":
        raise
    buffer_reset_guard = None


def fixture():
    return {"creator": "test fixture", "modules": {
        "upli_connection_side": {
            "attributes": {},
            "ports": {"i_clk": {"direction": "input", "bits": [2]},
                      "i_rstn": {"direction": "input", "bits": [3]}},
            "netnames": {"i_rstn": {"hide_name": 0, "bits": [3], "attributes": {}},
                         "other": {"hide_name": 1, "bits": [20], "attributes": {}}},
            "cells": {
                "guard": {"type": "DFQD2BWP40P140", "attributes": {"mark": "retain"},
                          "parameters": {}, "hide_name": 0,
                          "port_directions": {"D": "input", "CP": "input", "Q": "output"},
                          "connections": {"D": [3], "CP": [2], "Q": [7]}},
                "other_ff": {"type": "DFQD2BWP40P140", "attributes": {}, "parameters": {},
                             "port_directions": {"D": "input", "CP": "input", "Q": "output"},
                             "connections": {"D": [4], "CP": [2], "Q": [9]}},
                "reset_logic": {"type": "AND", "attributes": {}, "parameters": {},
                                "port_directions": {"A": "input", "B": "input", "Y": "output"},
                                "connections": {"A": [3], "B": [9], "Y": [20]}}
            }
        },
        "BUFFD0BWP40P140": {"ports": {"I": {"direction": "input", "bits": [2]},
                                         "Z": {"direction": "output", "bits": [3]}},
                               "attributes": {"blackbox": "1"}, "cells": {}, "netnames": {}}
    }}


class ResetGuardBufferTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(buffer_reset_guard, "bounded reset-buffer transformation not implemented")

    def test_only_direct_guard_data_is_buffered_and_source_is_unchanged(self):
        original = fixture()
        saved = copy.deepcopy(original)
        result = buffer_reset_guard(original)
        top = result["modules"]["upli_connection_side"]
        self.assertEqual(top["cells"]["guard"]["connections"], {"D": [21], "CP": [2], "Q": [7]})
        self.assertEqual(top["cells"]["ualink_reset_hold_buffer"]["connections"], {"I": [3], "Z": [21]})
        self.assertEqual(top["cells"]["ualink_reset_hold_buffer"]["type"], "BUFFD0BWP40P140")
        for name in ("other_ff", "reset_logic"):
            self.assertEqual(top["cells"][name], original["modules"]["upli_connection_side"]["cells"][name])
        self.assertEqual(top["ports"], original["modules"]["upli_connection_side"]["ports"])
        self.assertEqual(top["cells"]["guard"]["attributes"], {"mark": "retain"})
        self.assertEqual(original, saved)

    def test_bit_allocator_accounts_for_cell_only_and_port_only_bits(self):
        for location in ("cell", "port"):
            with self.subTest(location=location):
                design = fixture()
                top = design["modules"]["upli_connection_side"]
                if location == "cell":
                    top["cells"]["other_ff"]["connections"]["Q"] = [97]
                else:
                    top["ports"]["spare"] = {"direction": "output", "bits": [97]}
                self.assertEqual(buffer_reset_guard(design)["modules"]["upli_connection_side"]["cells"]["guard"]["connections"]["D"], [98])

    def test_missing_or_multiple_direct_guard_sinks_are_rejected(self):
        for count in (0, 2):
            with self.subTest(count=count):
                design = fixture()
                cells = design["modules"]["upli_connection_side"]["cells"]
                if count == 0:
                    cells["guard"]["connections"]["D"] = [4]
                else:
                    cells["other_ff"]["connections"]["D"] = [3]
                saved = copy.deepcopy(design)
                with self.assertRaises(ValueError):
                    buffer_reset_guard(design)
                self.assertEqual(design, saved)

    def test_preexisting_repair_cell_or_net_is_not_overwritten(self):
        for collection, name in (("cells", "ualink_reset_hold_buffer"), ("netnames", "ualink_reset_held")):
            design = fixture()
            design["modules"]["upli_connection_side"][collection][name] = {"existing": True}
            with self.assertRaises(ValueError):
                buffer_reset_guard(design)

    def test_source_must_be_a_scalar_input_net(self):
        for port in ({"direction": "output", "bits": [3]}, {"direction": "input", "bits": [3, 4]},
                     {"direction": "input", "bits": ["0"]}, {"direction": "input", "bits": [True]}):
            design = fixture()
            design["modules"]["upli_connection_side"]["ports"]["i_rstn"] = port
            with self.assertRaises(ValueError):
                buffer_reset_guard(design)

    def test_incompatible_buffer_pin_declaration_is_rejected(self):
        for ports in ({}, {"I": {"direction": "input", "bits": [2, 3]}, "Z": {"direction": "output", "bits": [4]}},
                      {"I": {"direction": "output", "bits": [2]}, "Z": {"direction": "input", "bits": [3]}}):
            design = fixture()
            design["modules"]["BUFFD0BWP40P140"]["ports"] = ports
            with self.assertRaises(ValueError):
                buffer_reset_guard(design)

    def test_sink_data_must_be_declared_input(self):
        design = fixture()
        design["modules"]["upli_connection_side"]["cells"]["guard"]["port_directions"]["D"] = "output"
        with self.assertRaises(ValueError):
            buffer_reset_guard(design)

    def test_unlowered_top_state_and_missing_design_parts_are_rejected(self):
        for key in ("processes", "memories"):
            design = fixture()
            design["modules"]["upli_connection_side"][key] = {"state": {}}
            with self.assertRaises(ValueError):
                buffer_reset_guard(design)
        for module in ("upli_connection_side", "BUFFD0BWP40P140"):
            design = fixture()
            del design["modules"][module]
            with self.assertRaises(ValueError):
                buffer_reset_guard(design)

    def test_second_application_cannot_silently_add_more_delay(self):
        repaired = buffer_reset_guard(fixture())
        with self.assertRaises(ValueError):
            buffer_reset_guard(repaired)

    def test_cli_emits_repaired_json_without_rewriting_input(self):
        script = Path(__file__).resolve().parents[2] / "scripts/buffer_reset_guard.py"
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input with spaces.json"
            source.write_text(json.dumps(fixture()), encoding="utf-8")
            before = source.read_bytes()
            result = subprocess.run([sys.executable, str(script), "--input", str(source)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            output = json.loads(result.stdout)
            self.assertEqual(output["modules"]["upli_connection_side"]["cells"]["guard"]["connections"]["D"], [21])
            self.assertEqual(source.read_bytes(), before)

    def test_cli_rejects_bad_json_or_missing_file_with_no_success_output(self):
        script = Path(__file__).resolve().parents[2] / "scripts/buffer_reset_guard.py"
        with tempfile.TemporaryDirectory() as directory:
            bad_json = Path(directory) / "invalid.json"
            bad_json.write_text("{broken", encoding="utf-8")
            for source in (bad_json, Path(directory) / "missing.json"):
                result = subprocess.run([sys.executable, str(script), "--input", str(source)],
                                        capture_output=True, text=True, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertTrue(result.stderr)
