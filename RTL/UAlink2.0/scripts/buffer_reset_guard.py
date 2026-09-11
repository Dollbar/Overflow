"""Insert one technology hold buffer on the connection reset-release guard D.

This is a bounded post-map transformation, not an RTL delay or generic hold
optimizer. Cell timing/function must be checked with the authorized Liberty.
CLI: python3 scripts/buffer_reset_guard.py --input mapped.json > hold_mapped.json
Next: emit/check the netlist, prove equivalence, and run all declared STA corners.
"""

import argparse
import copy
import json
import sys

TOP = "upli_connection_side"
BUFFER = "BUFFD0BWP40P140"
BUFFER_NAME = "ualink_reset_hold_buffer"
BUFFER_NET = "ualink_reset_held"


def buffer_reset_guard(design):
    """Return a fresh netlist; reject structural drift rather than guessing sinks."""
    try:
        top = design["modules"][TOP]
        buffer_ports = design["modules"][BUFFER]["ports"]
        reset = top["ports"]["i_rstn"]
        cells = top["cells"]
        netnames = top["netnames"]
    except (KeyError, TypeError) as exc:
        raise ValueError("required mapped top, reset or buffer declaration is missing") from exc
    if top.get("processes") or top.get("memories"):
        raise ValueError("only the lowered, memory-free connection top is supported")
    if BUFFER_NAME in cells or BUFFER_NET in netnames:
        raise ValueError("repair object already exists; do not overwrite or stack buffers")
    if (reset.get("direction") != "input" or len(reset.get("bits", [])) != 1
            or type(reset["bits"][0]) is not int or reset["bits"][0] < 2):
        raise ValueError("i_rstn must be a scalar input net, not a constant")
    if set(buffer_ports) != {"I", "Z"}:
        raise ValueError("buffer must expose exactly scalar I and Z pins")
    for name, direction in (("I", "input"), ("Z", "output")):
        port = buffer_ports[name]
        if port.get("direction") != direction or len(port.get("bits", [])) != 1:
            raise ValueError("buffer declaration has an incompatible pin direction or width")
    source_bit = reset["bits"][0]
    sinks = [name for name, cell in cells.items()
             if cell.get("type") == "DFQD2BWP40P140"
             and cell.get("connections", {}).get("D") == [source_bit]]
    if len(sinks) != 1:
        raise ValueError("expected exactly one direct reset-to-guard D connection")
    sink = sinks[0]
    if cells[sink].get("port_directions", {}).get("D") != "input":
        raise ValueError("selected guard D is not an input")

    # Allocate in this module's bit namespace, including non-public/aliased nets.
    bit_vectors = [port["bits"] for port in top["ports"].values()]
    bit_vectors += [net["bits"] for net in netnames.values()]
    bit_vectors += [bits for cell in cells.values() for bits in cell["connections"].values()]
    new_bit = 1 + max(bit for bits in bit_vectors for bit in bits if type(bit) is int)
    repaired = copy.deepcopy(design)
    changed = repaired["modules"][TOP]
    changed["cells"][sink]["connections"]["D"] = [new_bit]
    changed["netnames"][BUFFER_NET] = {"hide_name": 0, "bits": [new_bit], "attributes": {}}
    changed["cells"][BUFFER_NAME] = {
        "hide_name": 0, "type": BUFFER, "parameters": {},
        "attributes": {"keep": "1", "ualink_purpose": "reset_guard_hold_repair"},
        "port_directions": {"I": "input", "Z": "output"},
        "connections": {"I": [source_bit], "Z": [new_bit]}
    }
    return repaired


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="original Yosys JSON, never overwritten")
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as stream:
            repaired = buffer_reset_guard(json.load(stream))
        json.dump(repaired, sys.stdout, indent=2)
        print()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL reset guard repair: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
