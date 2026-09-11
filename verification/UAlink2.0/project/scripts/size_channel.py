"""Size actual head and heavily loaded SRAM read-control drivers with fixed cell pairs.

Run: python3 scripts/size_channel.py build/channel/input.json build/channel/sized.json
Output: fresh Yosys JSON; source is unchanged and repeated repair is rejected.
Next: re-emit netlist, prove full macro-port equivalence, check all STA corners.
This is a measured load repair, not a substitute for timing or Boolean proof.
"""
import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import sys


def size_channel(design):
    modules = design.get("modules", {})
    if "upli_receive_channel" not in modules:
        raise ValueError("missing explicit receive channel top")
    original = modules["upli_receive_channel"]
    if "ualink_head_sized_count" in original.get("attributes", {}):
        raise ValueError("head sizing already applied")
    output_bits = {bit for name, port in original.get("ports", {}).items()
                   if name.startswith("o_head_") and port["direction"] == "output"
                   for bit in port["bits"] if type(bit) is int}
    targets = [name for name, cell in original.get("cells", {}).items()
               if cell["type"] == "ND4D1BWP40P140"
               and cell.get("port_directions", {}).get("ZN") == "output"
               and output_bits.intersection(cell.get("connections", {}).get("ZN", []))]
    read_loads = Counter(bit for cell in original.get("cells", {}).values()
                         if cell["type"].startswith("KD28_SRAM_SDP_")
                         for bit in cell.get("connections", {}).get("RCS", []) if type(bit) is int)
    read_targets = [name for name, cell in original.get("cells", {}).items()
                    if cell["type"] == "INVD1BWP40P140"
                    and cell.get("port_directions", {}).get("ZN") == "output"
                    and any(read_loads[bit] >= 8 for bit in cell.get("connections", {}).get("ZN", []))]
    # Measured two-load RCS paths are limited by the small NAND before the NOR,
    # not the final NOR. Enlarging the latter alone worsens its input loading.
    qualified_inputs = {bit for cell in original.get("cells", {}).values()
                        if cell["type"] == "NR3D1P5BWP40P140"
                        and cell.get("port_directions", {}).get("ZN") == "output"
                        and any(read_loads[b] >= 2 for b in cell.get("connections", {}).get("ZN", []))
                        for pin in ("A1", "A2", "A3")
                        for bit in cell.get("connections", {}).get(pin, []) if type(bit) is int}
    read_predecessors = [name for name, cell in original.get("cells", {}).items()
                         if cell["type"] == "ND2D0BWP40P140"
                         and cell.get("port_directions", {}).get("ZN") == "output"
                         and qualified_inputs.intersection(cell.get("connections", {}).get("ZN", []))]
    nd4_shape = {"A1": ("input", 1), "A2": ("input", 1), "A3": ("input", 1),
                 "A4": ("input", 1), "ZN": ("output", 1)}
    inverter_shape = {"I": ("input", 1), "ZN": ("output", 1)}
    nd2_shape = {"A1": ("input", 1), "A2": ("input", 1), "ZN": ("output", 1)}
    repairs = ((targets, "ND4D1BWP40P140", "ND4D2BWP40P140", nd4_shape),
               (read_targets, "INVD1BWP40P140", "INVD4BWP40P140", inverter_shape),
               (read_predecessors, "ND2D0BWP40P140", "ND2D2BWP40P140", nd2_shape))
    for names, source_type, target_type, expected in repairs:
        if not names:
            continue
        shapes = []
        for kind in (source_type, target_type):
            if kind not in modules:
                raise ValueError("missing actual sizing cell definition")
            shapes.append({name: (port["direction"], len(port["bits"]))
                           for name, port in modules[kind].get("ports", {}).items()})
        if shapes != [expected, expected]:
            raise ValueError("incompatible sizing cell ports")
    result = deepcopy(design)
    top = result["modules"]["upli_receive_channel"]
    for names, _, target_type, _ in repairs:
        for name in names:
            top["cells"][name]["type"] = target_type
    top.setdefault("attributes", {})["ualink_head_sized_count"] = str(len(targets))
    top["attributes"]["ualink_read_sized_count"] = str(len(read_targets))
    top["attributes"]["ualink_read_predecessor_sized_count"] = str(len(read_predecessors))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        if args.source.resolve() == args.destination.resolve():
            raise ValueError("source and destination must differ")
        result = size_channel(json.loads(args.source.read_text()))
        args.destination.write_text(json.dumps(result, indent=2) + "\n")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL channel sizing: {error}", file=sys.stderr)
        return 1
    count = result["modules"]["upli_receive_channel"]["attributes"]["ualink_head_sized_count"]
    read_count = result["modules"]["upli_receive_channel"]["attributes"]["ualink_read_sized_count"]
    predecessor_count = result["modules"]["upli_receive_channel"]["attributes"]["ualink_read_predecessor_sized_count"]
    print(f"PASS channel sizing head_cells={count} read_cells={read_count} "
          f"read_predecessors={predecessor_count}; equivalence and STA still required")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
