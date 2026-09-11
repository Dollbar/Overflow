"""Insert actual load-connected hold buffers into a Yosys mapped storage JSON.

Run: python3 scripts/buffer_storage.py build/storage_synth_5_32/unbuffered.json
     build/storage_synth_5_32/buffered.json
Output: a fresh mapped-design JSON; input is untouched, second application rejected.
Next: emit/check the netlist with Yosys, prove macro-port equivalence, run all STA views.
Only selected dynamic SRAM inputs change; SRAM clocks, outputs, constants and all
other sinks retain their connectivity. This is mapping repair, not RTL delay logic.
Data/address nets use three cells; logic-qualified WCS uses one. RCS defaults to
one, with an explicit zero-stage option for setup-critical channel controls.
Multi-bank channel read selects retain one local hold cell after bank decoding.
Shared read-driver reset qualification gets a local hold guard before sizing;
other reset sinks and the setup-critical consumer inputs keep their connections.
Shared nets take the larger requirement. All timing views must verify each policy.
"""

import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import re
import sys


def buffer_storage(design, *, top="upli_receive_storage", read_control_stages=1):
    if type(read_control_stages) is not int or read_control_stages not in (0, 1):
        raise ValueError("read control stages must be zero or one")
    if top not in ("upli_receive_storage", "upli_receive_channel", "dl_uart_tx_path", "dl_uart_rx_path") or top not in design.get("modules", {}):
        raise ValueError("missing or unsupported explicit storage top")
    original = design["modules"][top]
    if original.get("attributes", {}).get("ualink_storage_hold"):
        raise ValueError("hold transform already applied")
    for collection in (original.get("cells", {}), original.get("netnames", {})):
        if any(name.startswith("storage_hold_") for name in collection):
            raise ValueError("reserved storage hold name collision")
    classes = {"KD28_SRAM_SDP_256X32": (32, 8), "KD28_SRAM_SDP_512X64": (64, 9),
               "KD28_SRAM_SDP_1024X128": (128, 10), "KD28_SRAM_SDP_2048X256": (256, 11)}
    macros = []
    all_bits = []
    for port in original.get("ports", {}).values():
        all_bits.extend(port["bits"])
    for net in original.get("netnames", {}).values():
        all_bits.extend(net["bits"])
    for name, cell in original.get("cells", {}).items():
        for bits in cell.get("connections", {}).values():
            all_bits.extend(bits)
        if not cell["type"].startswith("KD28_SRAM_"):
            continue
        if cell["type"] not in classes:
            raise ValueError("unexpected SRAM class")
        width, address = classes[cell["type"]]
        expected = dict(WCLK=1, RCLK=1, WCS=1, RCS=1, D=width, Q=width,
                        WA=address, RA=address, WM=width // 8)
        ports = cell["connections"]
        if set(ports) != set(expected) or any(len(ports[p]) != n for p, n in expected.items()):
            raise ValueError("incomplete or malformed macro ports")
        if any(type(bit) is not int and bit not in ("0", "1") for bits in ports.values() for bit in bits):
            raise ValueError("nonbinary macro connection")
        macros.append(name)
    if not macros:
        raise ValueError("no fixed SRAM macros")
    if any(type(bit) is bool or type(bit) is int and bit < 2 for bit in all_bits):
        raise ValueError("invalid Yosys bit identity")
    next_bit = max(bit for bit in all_bits if type(bit) is int) + 1
    result = deepcopy(design)
    module = result["modules"][top]
    bank_groups = {}
    bank_for_macro = {}
    if top == "upli_receive_channel" and not read_control_stages:
        for name in macros:
            match = re.match(r"^(.*)\.gen_depth_bank\[(\d+)\]\.", name)
            if match:
                group, bank = match.groups()
                bank_groups.setdefault(group, set()).add(int(bank))
                bank_for_macro[name] = group
    banked_macros = {name for name, group in bank_for_macro.items()
                     if len(bank_groups[group]) > 1}
    stages_by_bit = {}
    for name in macros:
        for port in ("D", "WA", "RA", "WCS", "RCS"):
            stages = read_control_stages if port == "RCS" else 1 if port == "WCS" else 3
            if port == "RCS" and name in banked_macros:
                stages = 1
            for bit in module["cells"][name]["connections"][port]:
                if type(bit) is int:
                    stages_by_bit[bit] = max(stages_by_bit.get(bit, 0), stages)
    buffered = {}
    for name in sorted(macros):
        ports = module["cells"][name]["connections"]
        for port in ("D", "WA", "RA", "WCS", "RCS"):
            for index, bit in enumerate(ports[port]):
                if type(bit) is not int:
                    continue
                if bit not in buffered:
                    previous = bit
                    for stage in range(stages_by_bit[bit]):
                        identifier = f"storage_hold_{bit}_{stage}"
                        module["cells"][identifier] = {
                            "hide_name": 0, "type": "BUFFD0BWP40P140", "parameters": {}, "attributes": {},
                            "port_directions": {"I": "input", "Z": "output"},
                            "connections": {"I": [previous], "Z": [next_bit]}}
                        module["netnames"][identifier + "_net"] = {"hide_name": 0, "bits": [next_bit], "attributes": {}}
                        previous = next_bit
                        next_bit += 1
                    buffered[bit] = previous
                ports[port][index] = buffered[bit]
    module.setdefault("attributes", {})["ualink_storage_hold"] = (
        "three_data_address_buffers_one_qualified_control_buffer" if read_control_stages else
        "three_data_address_buffers_one_write_and_banked_read_control_buffer" if banked_macros else
        "three_data_address_buffers_one_write_control_buffer_zero_read_control_buffers")
    # Strengthening a heavily loaded read inverter shortens the direct reset
    # path. Guard only the reset pin of its actual NAND predecessor, not every
    # RCS load or the consumer input cone that caused the setup failure.
    reset_port = original.get("ports", {}).get("i_rstn", {})
    reset_bits = reset_port.get("bits", [])
    if (top == "upli_receive_channel" and not read_control_stages
            and reset_port.get("direction") == "input" and len(reset_bits) == 1
            and type(reset_bits[0]) is int):
        read_loads = Counter(bit for name in macros
                             for bit in original["cells"][name]["connections"]["RCS"] if type(bit) is int)
        shared_inputs = {bit for cell in original["cells"].values()
                         if cell["type"] == "INVD1BWP40P140"
                         and cell.get("port_directions", {}).get("ZN") == "output"
                         and any(read_loads[b] >= 8 for b in cell["connections"].get("ZN", []))
                         for bit in cell["connections"].get("I", []) if type(bit) is int}
        reset_sinks = [(name, pin) for name, cell in original["cells"].items()
                       if cell["type"] == "ND3D2BWP40P140"
                       and shared_inputs.intersection(cell["connections"].get("ZN", []))
                       for pin in ("A1", "A2", "A3")
                       if cell.get("port_directions", {}).get(pin) == "input"
                       and cell["connections"].get(pin) == reset_bits]
        for index, (name, pin) in enumerate(reset_sinks):
            identifier = f"storage_hold_read_reset_{index}"
            module["cells"][identifier] = {
                "hide_name": 0, "type": "BUFFD0BWP40P140", "parameters": {}, "attributes": {},
                "port_directions": {"I": "input", "Z": "output"},
                "connections": {"I": list(reset_bits), "Z": [next_bit]}}
            module["netnames"][identifier + "_net"] = {"hide_name": 0, "bits": [next_bit], "attributes": {}}
            module["cells"][name]["connections"][pin] = [next_bit]
            next_bit += 1
        if reset_sinks:
            module["attributes"]["ualink_storage_hold"] += "_local_shared_read_reset_guard"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--top", choices=("upli_receive_storage", "upli_receive_channel", "dl_uart_tx_path", "dl_uart_rx_path"), default="upli_receive_storage")
    parser.add_argument("--read-control-stages", type=int, choices=(0, 1), default=1)
    args = parser.parse_args()
    try:
        if args.source.resolve() == args.destination.resolve():
            raise ValueError("source and destination must differ")
        result = buffer_storage(json.loads(args.source.read_text()), top=args.top,
                                read_control_stages=args.read_control_stages)
        args.destination.write_text(json.dumps(result, indent=2) + "\n")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL storage hold transform: {error}", file=sys.stderr)
        return 1
    print("PASS storage hold transform; equivalence and STA still required")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
