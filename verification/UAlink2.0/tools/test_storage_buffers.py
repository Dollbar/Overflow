"""Real JSON transform: macro loads must traverse buffers, aliases are insufficient.

Run: python3 -m unittest verification.tools.test_storage_buffers -v
Output: unittest results, including actual Yosys JSON import; failure is nonzero.
Next: mapped macro-port equivalence and full integrated timing matrix.
"""

from copy import deepcopy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

try:
    from scripts.buffer_storage import buffer_storage
except ImportError:
    buffer_storage = None


def fixture():
    """Small hand-wired SDP macro; test actual port connectivity, not tool mocks."""
    return {"modules": {"upli_receive_storage": {"ports": {"i_clk": {"direction": "input", "bits": [2]}},
            "netnames": {"payload": {"bits": [3]}}, "cells": {
                "memory": {"type": "KD28_SRAM_SDP_256X32", "connections": {
                    "WCLK": [2], "RCLK": [2], "WCS": [4], "RCS": [5],
                    "D": [3] + ["0"] * 31, "Q": list(range(20, 52)),
                    "WA": [6] + ["0"] * 7, "RA": [7] + ["0"] * 7, "WM": ["1"] * 4}},
                "observer": {"type": "BUFFD0BWP40P140", "connections": {"I": [3], "Z": [8]}}}}}}


def shared_read_reset_fixture(count=17):
    source = fixture()
    top = source["modules"].pop("upli_receive_storage")
    source["modules"]["upli_receive_channel"] = top
    top["ports"]["i_rstn"] = {"direction": "input", "bits": [80]}
    base = top["cells"].pop("memory")
    for index in range(count):
        cell = deepcopy(base)
        cell["connections"]["Q"] = list(range(200+32*index, 232+32*index))
        top["cells"][f"memory_{index}"] = cell
    top["cells"]["read_inverter"] = {"type": "INVD1BWP40P140",
        "port_directions": {"I": "input", "ZN": "output"}, "connections": {"I": [81], "ZN": [5]}}
    top["cells"]["read_qualifier"] = {"type": "ND3D2BWP40P140",
        "port_directions": {"A1": "input", "A2": "input", "A3": "input", "ZN": "output"},
        "connections": {"A1": [80], "A2": [82], "A3": [83], "ZN": [81]}}
    top["cells"]["reset_observer"] = {"type": "BUFFD0BWP40P140",
        "port_directions": {"I": "input", "Z": "output"}, "connections": {"I": [80], "Z": [84]}}
    return source


class StorageBufferTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(buffer_storage, "load-connected storage hold transform missing")

    def test_data_address_get_three_buffers_and_qualified_controls_get_one(self):
        source = fixture(); before = deepcopy(source)
        result = buffer_storage(source)
        module = result["modules"]["upli_receive_storage"]
        cells = module["cells"]; macro = cells["memory"]["connections"]
        self.assertEqual(source, before)
        self.assertEqual(len(cells), 13)
        for port, original in (("D", 3), ("WCS", 4), ("RCS", 5), ("WA", 6), ("RA", 7)):
            bit = macro[port][0]
            for _ in range(1 if port in ("WCS", "RCS") else 3):
                drivers = [v for k, v in cells.items() if k.startswith("storage_hold_") and v["connections"]["Z"] == [bit]]
                self.assertEqual(len(drivers), 1)
                self.assertEqual(drivers[0]["type"], "BUFFD0BWP40P140")
                bit = drivers[0]["connections"]["I"][0]
            self.assertEqual(bit, original)
        self.assertEqual(cells["observer"], before["modules"]["upli_receive_storage"]["cells"]["observer"])
        self.assertEqual(macro["WCLK"], [2]); self.assertEqual(macro["RCLK"], [2])
        self.assertEqual(macro["D"][1:], ["0"] * 31); self.assertEqual(macro["WM"], ["1"] * 4)
        self.assertEqual(macro["Q"], list(range(20, 52)))

    def test_explicit_channel_top_reconnects_loads_without_renaming_design(self):
        source = fixture()
        source["modules"]["upli_receive_channel"] = source["modules"].pop("upli_receive_storage")
        before = deepcopy(source)
        result = buffer_storage(source, top="upli_receive_channel")
        self.assertEqual(set(result["modules"]), {"upli_receive_channel"})
        self.assertEqual(source, before)
        self.assertNotEqual(result["modules"]["upli_receive_channel"]["cells"]["memory"]["connections"]["D"][0], 3)
        self.assertEqual(result["modules"]["upli_receive_channel"]["cells"]["memory"]["connections"]["WCLK"], [2])

    def test_explicit_top_cannot_silently_target_another_module(self):
        with self.assertRaises(ValueError):
            buffer_storage(fixture(), top="upli_receive_channel")
        with self.assertRaises(ValueError):
            buffer_storage(fixture(), top="anything")

    def test_uart_path_top_buffers_real_macro_loads_without_touching_other_sinks(self):
        source = fixture()
        source["modules"]["dl_uart_tx_path"] = source["modules"].pop("upli_receive_storage")
        before = deepcopy(source)
        result = buffer_storage(source, top="dl_uart_tx_path")
        self.assertEqual(source, before)
        self.assertEqual(set(result["modules"]), {"dl_uart_tx_path"})
        cells = result["modules"]["dl_uart_tx_path"]["cells"]
        macro = cells["memory"]["connections"]
        for port, original in (("D", 3), ("WA", 6), ("RA", 7), ("WCS", 4), ("RCS", 5)):
            bit = macro[port][0]
            for _ in range(1 if port in ("WCS", "RCS") else 3):
                drivers = [c for n,c in cells.items() if n.startswith("storage_hold_") and c["connections"]["Z"] == [bit]]
                self.assertEqual(len(drivers), 1)
                self.assertEqual(drivers[0]["type"], "BUFFD0BWP40P140")
                bit = drivers[0]["connections"]["I"][0]
            self.assertEqual(bit, original)
        for port in ("WCLK", "RCLK", "Q", "WM"):
            self.assertEqual(macro[port], before["modules"]["dl_uart_tx_path"]["cells"]["memory"]["connections"][port])
        self.assertEqual(cells["observer"], before["modules"]["dl_uart_tx_path"]["cells"]["observer"])
        with self.assertRaises(ValueError):
            buffer_storage(result, top="dl_uart_tx_path")

    def test_optional_read_control_bypass_preserves_write_and_data_hold_chains(self):
        source = fixture(); before = deepcopy(source)
        cells = buffer_storage(source, read_control_stages=0)["modules"]["upli_receive_storage"]["cells"]
        macro = cells["memory"]["connections"]
        self.assertEqual(macro["RCS"], [5])
        self.assertNotEqual(macro["WCS"], [4])
        self.assertNotEqual(macro["D"][0], 3)
        self.assertEqual(len(cells), 12)
        self.assertEqual(source, before)
        # A shared data/control source still needs the strongest load requirement.
        source["modules"]["upli_receive_storage"]["cells"]["memory"]["connections"]["RCS"] = [3]
        macro = buffer_storage(source, read_control_stages=0)["modules"]["upli_receive_storage"]["cells"]["memory"]["connections"]
        self.assertEqual(macro["RCS"], [macro["D"][0]])

    def test_read_control_policy_rejects_unsupported_values(self):
        for stages in (-1, 2, True, "0", None):
            with self.subTest(stages=stages), self.assertRaises(ValueError):
                buffer_storage(fixture(), read_control_stages=stages)

    def test_channel_banked_read_controls_retain_local_hold_buffers(self):
        source = fixture(); top = source["modules"].pop("upli_receive_storage")
        source["modules"]["upli_receive_channel"] = top
        base = deepcopy(top["cells"]["memory"])
        base["type"] = "KD28_SRAM_SDP_2048X256"
        base["connections"].update(D=[3]+["0"]*255, Q=list(range(100,356)), WA=[6]+["0"]*10,
                                    RA=[7]+["0"]*10, WM=["1"]*32)
        for bank in (0,1):
            cell = deepcopy(base); cell["connections"]["RCS"] = [20+bank]
            cell["connections"]["Q"] = list(range(100+bank*256,356+bank*256))
            top["cells"][f"account.gen_depth_bank[{bank}].u_sram"] = cell
        before = deepcopy(source)
        result = buffer_storage(source, top="upli_receive_channel", read_control_stages=0)
        cells = result["modules"]["upli_receive_channel"]["cells"]
        for bank in (0,1):
            bit = cells[f"account.gen_depth_bank[{bank}].u_sram"]["connections"]["RCS"][0]
            self.assertNotEqual(bit,20+bank)
            drivers = [c for n,c in cells.items() if n.startswith("storage_hold_") and c["connections"]["Z"] == [bit]]
            self.assertEqual(len(drivers),1)
            self.assertEqual(drivers[0]["connections"]["I"],[20+bank])
        self.assertEqual(cells["memory"]["connections"]["RCS"],[5])
        self.assertEqual(source,before)

    def test_single_bank_macro_does_not_trigger_banked_hold_policy(self):
        source = fixture(); top = source["modules"].pop("upli_receive_storage")
        source["modules"]["upli_receive_channel"] = top
        top["cells"]["account.gen_depth_bank[0].u_sram"] = top["cells"].pop("memory")
        result = buffer_storage(source, top="upli_receive_channel", read_control_stages=0)
        self.assertEqual(result["modules"]["upli_receive_channel"]["cells"]["account.gen_depth_bank[0].u_sram"]["connections"]["RCS"],[5])

    def test_shared_read_reset_gets_a_local_guard_without_delaying_other_inputs(self):
        source = shared_read_reset_fixture(); before = deepcopy(source)
        top = buffer_storage(source, top="upli_receive_channel", read_control_stages=0)["modules"]["upli_receive_channel"]
        cells = top["cells"]
        pin = cells["read_qualifier"]["connections"]["A1"][0]
        self.assertNotEqual(pin, 80)
        buffers = [v for k, v in cells.items() if k.startswith("storage_hold_") and v["connections"]["Z"] == [pin]]
        self.assertEqual(len(buffers), 1)
        self.assertEqual(buffers[0]["connections"]["I"], [80])
        self.assertEqual(buffers[0]["type"], "BUFFD0BWP40P140")
        for port, bits in (("A2", [82]), ("A3", [83]), ("ZN", [81])):
            self.assertEqual(cells["read_qualifier"]["connections"][port], bits)
        self.assertEqual(cells["reset_observer"], before["modules"]["upli_receive_channel"]["cells"]["reset_observer"])
        for index in range(17):
            self.assertEqual(cells[f"memory_{index}"]["connections"]["RCS"], [5])
            self.assertEqual(cells[f"memory_{index}"]["connections"]["RCLK"], [2])
        self.assertEqual(source, before)

    def test_non_shared_read_reset_is_not_buffered_by_channel_policy(self):
        source = shared_read_reset_fixture(1)
        cells = buffer_storage(source, top="upli_receive_channel", read_control_stages=0)["modules"]["upli_receive_channel"]["cells"]
        self.assertEqual(cells["read_qualifier"]["connections"]["A1"], [80])

    def test_shared_data_loads_share_chain_without_rewriting_other_sinks(self):
        source = fixture(); module = source["modules"]["upli_receive_storage"]
        module["cells"]["memory_b"] = deepcopy(module["cells"]["memory"])
        module["cells"]["memory_b"]["connections"]["Q"] = list(range(52, 84))
        result = buffer_storage(source)["modules"]["upli_receive_storage"]["cells"]
        self.assertEqual(result["memory"]["connections"]["D"], result["memory_b"]["connections"]["D"])
        self.assertEqual(len(result), 14)

    def test_yosys_imports_transformed_netlist_without_cell_wire_name_collisions(self):
        with tempfile.TemporaryDirectory(prefix="storage-buffer-test-") as directory:
            path = Path(directory) / "mapped.json"
            path.write_text(json.dumps(buffer_storage(fixture())))
            run = subprocess.run(["yosys", "-Q", "-T", "-p", f"read_json {path}"],
                                 capture_output=True, text=True, check=False)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_rejects_second_application_and_reserved_name_collisions(self):
        result = buffer_storage(fixture())
        with self.assertRaises(ValueError):
            buffer_storage(result)
        source = fixture(); source["modules"]["upli_receive_storage"]["netnames"]["storage_hold_stale"] = {"bits": [90]}
        with self.assertRaises(ValueError):
            buffer_storage(source)

    def test_rejects_missing_macros_bad_types_ports_widths_and_unknown_bits(self):
        cases = []
        a = fixture(); del a["modules"]["upli_receive_storage"]["cells"]["memory"]; cases.append(a)
        a = fixture(); a["modules"]["upli_receive_storage"]["cells"]["memory"]["type"] = "KD28_SRAM_SP_256X32"; cases.append(a)
        for port, bits in (("D", [3]), ("WA", ["x"] * 8), ("Q", [True] * 32), ("RCLK", [])):
            a = fixture(); a["modules"]["upli_receive_storage"]["cells"]["memory"]["connections"][port] = bits; cases.append(a)
        for source in cases:
            before = deepcopy(source)
            with self.subTest(source=source), self.assertRaises(ValueError):
                buffer_storage(source)
            self.assertEqual(source, before)


if __name__ == "__main__":
    unittest.main()
