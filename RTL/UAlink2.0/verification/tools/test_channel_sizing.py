"""Load-connected head/read driver repairs must preserve all actual transactions."""
from copy import deepcopy
import unittest

try:
    from scripts.size_channel import size_channel
except ImportError:
    size_channel = None


def fixture():
    ports = {name: {"direction": "output" if name == "ZN" else "input", "bits": [i+2]}
             for i, name in enumerate(("A1", "A2", "A3", "A4", "ZN"))}
    cell = {"type": "ND4D1BWP40P140", "parameters": {}, "attributes": {},
            "port_directions": {p: v["direction"] for p, v in ports.items()},
            "connections": {p: v["bits"] for p, v in ports.items()}}
    unrelated = deepcopy(cell); unrelated["connections"]["ZN"] = [90]
    return {"modules": {"upli_receive_channel": {"ports": {"o_head_payload": {"direction": "output", "bits": [6]}},
                        "cells": {"head": cell, "unrelated": unrelated}},
                        "ND4D1BWP40P140": {"ports": ports}, "ND4D2BWP40P140": {"ports": deepcopy(ports)}}}


def read_load_fixture(count=17):
    source = fixture()
    pins = {"I": {"direction": "input", "bits": [2]}, "ZN": {"direction": "output", "bits": [3]}}
    for kind in ("INVD1BWP40P140", "INVD4BWP40P140"):
        source["modules"][kind] = {"ports": deepcopy(pins)}
    cells = source["modules"]["upli_receive_channel"]["cells"]
    cells["read_driver"] = {"type": "INVD1BWP40P140", "connections": {"I": [100], "ZN": [101]},
                            "port_directions": {"I": "input", "ZN": "output"}}
    # Complete 256x32 macro connections: only the seventeen RCS loads share the target net.
    for index in range(count):
        cells[f"memory_{index}"] = {"type": "KD28_SRAM_SDP_256X32", "connections": {
            "WCLK": [2], "RCLK": [2], "WCS": [102], "RCS": [101], "D": ["0"]*32,
            "Q": list(range(200+32*index,232+32*index)), "WA": ["0"]*8, "RA": ["0"]*8, "WM": ["1"]*4}}
    return source


def qualified_read_fixture():
    source = read_load_fixture(2)
    pins = {"A1": {"direction": "input", "bits": [2]}, "A2": {"direction": "input", "bits": [3]},
            "ZN": {"direction": "output", "bits": [4]}}
    for kind in ("ND2D0BWP40P140", "ND2D2BWP40P140"):
        source["modules"][kind] = {"ports": deepcopy(pins)}
    cells = source["modules"]["upli_receive_channel"]["cells"]
    cells["read_driver"] = {"type": "NR3D1P5BWP40P140",
                            "connections": {"A1": [100], "A2": [104], "A3": [105], "ZN": [101]},
                            "port_directions": {"A1": "input", "A2": "input", "A3": "input", "ZN": "output"}}
    cells["read_predecessor"] = {"type": "ND2D0BWP40P140",
                                 "connections": {"A1": [106], "A2": [107], "ZN": [100]},
                                 "port_directions": {"A1": "input", "A2": "input", "ZN": "output"}}
    cells["unrelated_nand"] = deepcopy(cells["read_predecessor"])
    cells["unrelated_nand"]["connections"]["ZN"] = [108]
    return source


class ChannelSizingTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(size_channel, "channel output driver transform missing")

    def test_only_actual_head_driver_changes_type_without_connectivity_changes(self):
        source = fixture(); before = deepcopy(source); result = size_channel(source)
        cells = result["modules"]["upli_receive_channel"]["cells"]
        self.assertEqual(source, before)
        self.assertEqual(cells["head"]["type"], "ND4D2BWP40P140")
        self.assertEqual(cells["head"]["connections"], source["modules"]["upli_receive_channel"]["cells"]["head"]["connections"])
        self.assertEqual(cells["unrelated"], source["modules"]["upli_receive_channel"]["cells"]["unrelated"])

    def test_no_target_gate_is_a_recorded_noop(self):
        source = fixture(); source["modules"]["upli_receive_channel"]["ports"]["o_head_payload"]["bits"] = ["0"]
        result = size_channel(source)
        self.assertEqual(result["modules"]["upli_receive_channel"]["cells"], source["modules"]["upli_receive_channel"]["cells"])
        self.assertEqual(result["modules"]["upli_receive_channel"]["attributes"]["ualink_head_sized_count"], "0")

    def test_missing_or_pin_incompatible_library_definition_is_rejected(self):
        a = fixture(); del a["modules"]["ND4D2BWP40P140"]
        b = fixture(); del b["modules"]["ND4D2BWP40P140"]["ports"]["A4"]
        for source in (a,b):
            with self.assertRaises(ValueError): size_channel(source)

    def test_missing_top_and_second_application_are_rejected(self):
        with self.assertRaises(ValueError): size_channel({"modules": {}})
        with self.assertRaises(ValueError): size_channel(size_channel(fixture()))

    def test_shared_read_driver_is_strengthened_without_changing_macro_transactions(self):
        source = read_load_fixture(); before = deepcopy(source)
        result = size_channel(source)["modules"]["upli_receive_channel"]
        self.assertEqual(result["cells"]["read_driver"]["type"], "INVD4BWP40P140")
        self.assertEqual(result["cells"]["read_driver"]["connections"], {"I": [100], "ZN": [101]})
        for index in range(17):
            self.assertEqual(result["cells"][f"memory_{index}"], source["modules"]["upli_receive_channel"]["cells"][f"memory_{index}"])
        self.assertEqual(source, before)

    def test_low_load_control_is_not_indiscriminately_strengthened(self):
        source = read_load_fixture(1)
        result = size_channel(source)["modules"]["upli_receive_channel"]
        self.assertEqual(result["cells"]["read_driver"], source["modules"]["upli_receive_channel"]["cells"]["read_driver"])

    def test_read_driver_repair_requires_matching_actual_cell_definition(self):
        source = read_load_fixture(); del source["modules"]["INVD4BWP40P140"]
        with self.assertRaises(ValueError): size_channel(source)

    def test_qualified_read_predecessor_is_strengthened_without_changing_read_gate(self):
        source = qualified_read_fixture(); before = deepcopy(source)
        cells = size_channel(source)["modules"]["upli_receive_channel"]["cells"]
        self.assertEqual(cells["read_predecessor"]["type"], "ND2D2BWP40P140")
        self.assertEqual(cells["read_predecessor"]["connections"],
                         before["modules"]["upli_receive_channel"]["cells"]["read_predecessor"]["connections"])
        for name in ("read_driver", "unrelated_nand", "memory_0", "memory_1"):
            self.assertEqual(cells[name], before["modules"]["upli_receive_channel"]["cells"][name])
        self.assertEqual(source, before)

    def test_qualified_read_repair_requires_actual_nand_definition(self):
        source = qualified_read_fixture(); del source["modules"]["ND2D2BWP40P140"]
        with self.assertRaises(ValueError): size_channel(source)

    def test_non_shared_read_control_does_not_trigger_predecessor_sizing(self):
        source = qualified_read_fixture()
        source["modules"]["upli_receive_channel"]["cells"]["memory_1"]["connections"]["RCS"] = [108]
        result = size_channel(source)["modules"]["upli_receive_channel"]["cells"]
        self.assertEqual(result["read_predecessor"], source["modules"]["upli_receive_channel"]["cells"]["read_predecessor"])
