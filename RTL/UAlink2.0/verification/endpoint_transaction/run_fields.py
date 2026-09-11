#!/usr/bin/env python3
"""Check actual field RTL against fixed words and independently placed walking bits.

Run: python3 verification/endpoint_transaction/run_fields.py --label fields_first --faults
Outputs: build/verification/endpoint_transaction/LABEL/{result.json,vectors.json,*/...}
Next: integrate typed fields with transaction ownership and actual Data, then TL admission.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RTL = ["rtl/endpoint/endpoint_read_encode.v", "rtl/endpoint/endpoint_response_encode.v",
       "rtl/tl/tl_control_decode.v", "rtl/tl/tl_control_tenure.v"]
READ = dict(valid=1, tag=0, src=0, dst=0, address=0, length=15, attr=255,
            vc=0, pool=0, asi=0, metadata=0)
RESPONSE = dict(valid=1, tag=0, src=0, dst=0, status=0, num_beats=0,
                offset=0, last=1, vc=0, pool=0)
# Literal fixtures are independent of both the production RTL and semantic model.
RBASE = 0x10c0003fcf0000000000000000000000
SBASE = 0x2000003000000000


def vectors():
    cases = []

    def add(kind, name, values, word, valid=1, error=0):
        inputs = dict(READ if kind == "read" else RESPONSE)
        inputs.update(values)
        cases.append(dict(kind=kind, name=name, inputs=inputs,
                          word=f"{word:064x}", valid=valid, error=error))

    add("read", "fixed_zero", {}, RBASE)
    add("read", "fixed_max", dict(tag=2047, address=(1 << 57)-64, src=1023, dst=1022),
        0x10c3ffbfcf00ffffffffffffe1ffffc0)
    add("read", "fixed_mixed", dict(tag=1023, address=0x12340, src=1, dst=1023),
        0x10c1ffbfcf00000000000091a000ffe0)
    add("response", "fixed_zero", {}, SBASE)
    add("response", "fixed_max_error", dict(tag=2047, src=1023, dst=1022, status=3),
        0x23ff80fffffe0000)
    add("response", "fixed_mixed", dict(tag=1023, src=1, dst=1023), 0x21ff803007ff0000)
    # Common Tables 5-29/30: independent single-bit injection locations, no encoder call.
    for kind, base, mapping in [("read", RBASE, [("tag", 11, 103), ("src", 10, 15), ("dst", 10, 5)]),
                               ("response", SBASE, [("tag", 11, 47), ("src", 10, 26), ("dst", 10, 16)])]:
        for field, width, lsb in mapping:
            for bit in range(width):
                add(kind, f"{field}_bit_{bit}", {field: 1 << bit}, base | (1 << (lsb+bit)))
    for bit in range(6, 57):
        add("read", f"address_bit_{bit}", dict(address=1 << bit), RBASE | (1 << (bit+23)))
    # Exhaust each finite profile selector; address alignment tests each forbidden low bit.
    invalid = [("read", "address", [1 << bit for bit in range(6)]),
               ("read", "length", [v for v in range(64) if v != 15]),
               ("read", "attr", range(255)), ("read", "vc", range(1, 4)),
               ("read", "pool", [1]), ("read", "asi", range(1, 4)),
               ("read", "metadata", range(1, 256)),
               ("response", "status", [v for v in range(16) if v not in (0, 3)]),
               ("response", "num_beats", range(1, 4)), ("response", "offset", range(1, 4)),
               ("response", "last", [0]), ("response", "vc", range(1, 4)),
               ("response", "pool", [1])]
    for kind, field, values in invalid:
        for value in values:
            add(kind, f"reject_{field}_{value}", {field: value}, 0, 0, 1)
            add(kind, f"idle_{field}_{value}", {field: value, "valid": 0}, 0, 0, 0)
    for kind in ("read", "response"):
        add(kind, "idle_legal", dict(valid=0), 0, 0, 0)
    # Revisit accepted words after invalid/idle cycles to expose stale/latching outputs.
    add("read", "recover", dict(address=1 << 56), RBASE | (1 << 79))
    add("response", "recover_error", dict(status=3), SBASE | (3 << 38))
    return cases


def testbench(cases, shell):
    widths = dict(valid=1, tag=11, src=10, dst=10, address=57, length=6, attr=8,
                  vc=2, pool=1, asi=2, metadata=8, status=4, num_beats=2, offset=2, last=1)
    lines = ["`timescale 1ns/1ps", "module tb;"]
    for prefix, defaults, module in [("r", READ, "endpoint_read_encode"),
                                     ("s", RESPONSE, "endpoint_response_encode")]:
        for key in defaults:
            lines.append(f"reg [{widths[key]-1}:0] {prefix}_{key};")
        lines += [f"wire {prefix}_valid_out, {prefix}_error;", f"wire [255:0] {prefix}_control;"]
        if shell:
            lines += [f"wire [511:0] {prefix}_shell_data;",
                      f"assign {prefix}_control={prefix}_shell_data[255:0];",
                      f"{module} {prefix}_dut(.i_clk(1'b0),.i_rstn(1'b1),.i_enable(1'b1),"
                      f".i_valid({prefix}_valid),.i_data(512'd0),.i_meta(128'd0),"
                      f".o_valid({prefix}_valid_out),.o_error({prefix}_error),.o_data({prefix}_shell_data));"]
        else:
            ports = [f".i_{key}({prefix}_{key})" for key in defaults]
            ports += [f".o_valid({prefix}_valid_out)", f".o_error({prefix}_error)", f".o_control({prefix}_control)"]
            lines.append(f"{module} {prefix}_dut({','.join(ports)});")
        lines += [f"wire {prefix}_decoded; wire [2:0] {prefix}_requests; wire [3:0] {prefix}_responses;",
                  f"wire [7:0] {prefix}_starts,{prefix}_reqstarts,{prefix}_rspstarts;",
                  f"wire [1:0] {prefix}_tenure_status; wire [3:0] {prefix}_fields;",
                  f"wire [31:0] {prefix}_data_counts; wire [7:0] {prefix}_byte_enable;",
                  f"tl_control_decode {prefix}_decode(.i_half({prefix}_control),.o_valid({prefix}_decoded),"
                  f".o_requests({prefix}_requests),.o_responses({prefix}_responses),.o_field_starts({prefix}_starts),"
                  f".o_request_starts({prefix}_reqstarts),.o_response_starts({prefix}_rspstarts));",
                  f"tl_control_tenure {prefix}_tenure(.i_half({prefix}_control),.o_status({prefix}_tenure_status),"
                  f".o_fields({prefix}_fields),.o_data_counts({prefix}_data_counts),.o_byte_enable({prefix}_byte_enable));"]
    lines.append("initial begin")
    for prefix, defaults in [("r", READ), ("s", RESPONSE)]:
        lines += [f"{prefix}_{key}={widths[key]}'d{value};" for key, value in defaults.items()]
    for index, case in enumerate(cases):
        p = "r" if case["kind"] == "read" else "s"
        lines += [f"{p}_{key}={widths[key]}'d{value};" for key, value in case["inputs"].items()]
        lines.append("#1;")
        lines.append(f"if ({{{p}_valid_out,{p}_error,{p}_control}} !== "
                     f"{{1'b{case['valid']},1'b{case['error']},256'h{case['word']}}}) "
                     f'$fatal(1,"FIELD_SCOREBOARD case={index} {case["kind"]}/{case["name"]} valid=%b error=%b control=%h",'
                     f"{p}_valid_out,{p}_error,{p}_control);")
        req = int(p == "r") * case["valid"]
        rsp = int(p == "s") * case["valid"]
        starts = (0xf1 if p == "r" else 0xfd) if case["valid"] else 0xff
        lines.append(f"if ({{{p}_decoded,{p}_requests,{p}_responses,{p}_starts,{p}_reqstarts,{p}_rspstarts,"
                     f"{p}_tenure_status,{p}_fields,{p}_data_counts,{p}_byte_enable}} !== "
                     f"{{1'b1,3'd{req},4'd{rsp},8'd{starts},8'd{req},8'd{rsp},2'd0,"
                     f"4'd{case['valid']},32'd{2*rsp},8'd0}}) "
                     f'$fatal(1,"TL_CONSUMER case={index} {case["kind"]}/{case["name"]}");')
    lines += [f'$display("PASS vectors={len(cases)}");', "$finish;", "end", "endmodule"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--shell-baseline", action="store_true", help="Capture assertion failure of original generic shells before implementation")
    parser.add_argument("--faults", action="store_true", help="Run five actual RTL mutations; each must fail its scoreboard")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.label):
        parser.error("label must be a simple fresh directory name")
    if args.shell_baseline and args.faults:
        parser.error("shell baseline and implemented RTL mutations are separate stages")
    out = ROOT / "build/verification/endpoint_transaction" / args.label
    out.mkdir(parents=True, exist_ok=False)
    tools = {name: shutil.which(getattr(args, name)) for name in ("iverilog", "vvp")}
    if not all(tools.values()):
        raise SystemExit("Icarus tools missing; pass --iverilog and --vvp explicitly")
    cases = vectors()
    (out / "vectors.json").write_text(json.dumps(cases, indent=2) + "\n")
    tb = testbench(cases, args.shell_baseline)
    sources = {path: (ROOT / path).read_text() for path in RTL}
    mutations = [("read_shell", None), ("response_shell", None)] if args.shell_baseline else [("positive", None)]
    if args.faults:
        mutations += [
            ("read_address_truncate", (RTL[0], "i_address[56:2]", "{45'd0,i_address[11:2]}")),
            ("read_tag_high_drop", (RTL[0], "i_asi, i_tag, i_pool", "i_asi, {1'b0,i_tag[9:0]}, i_pool")),
            ("read_profile_bypass", (RTL[0], "i_valid && profile_legal", "i_valid")),
            ("response_data_tenure", (RTL[1], "i_status, 1'b1, i_last", "i_status, 1'b0, i_last")),
            ("consumer_response_count", (RTL[3], "if(i_half[37]) d1[0 +: 4]", "if(1'b0) d1[0 +: 4]")),
        ]
    result = dict(scope="single64B Read/Response field RTL and actual TL structural/tenure consumers",
                  shell_baseline=args.shell_baseline, vectors=len(cases), tools=tools, cases=[],
                  tool_versions={name: subprocess.run([path, "-V"], text=True, capture_output=True, timeout=10).stdout.splitlines()[:2] for name, path in tools.items()},
                  source_sha256={p: hashlib.sha256(s.encode()).hexdigest() for p, s in sources.items()})
    for path in ["config/endpoint_transaction_contract.json", "verification/endpoint_transaction/run_fields.py"]:
        result["source_sha256"][path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
    for name, mutation in mutations:
        folder = out / name
        folder.mkdir()
        snapshot = dict(sources)
        if mutation:
            path, before, after = mutation
            if snapshot[path].count(before) != 1:
                raise RuntimeError(f"mutation no longer uniquely applicable: {name}")
            snapshot[path] = snapshot[path].replace(before, after)
        for path, content in snapshot.items():
            (folder / Path(path).name).write_text(content)
        (folder / "tb.sv").write_text(testbench(sorted(cases, key=lambda c: c["kind"] != "response"), True) if name == "response_shell" else tb)
        commands = [[tools["iverilog"], "-g2012", "-Wall", "-s", "tb", "-o", "sim.vvp", "tb.sv"] +
                    [Path(path).name for path in RTL], [tools["vvp"], "sim.vvp"]]
        compile_run = subprocess.run(commands[0], cwd=folder, text=True, capture_output=True, timeout=60)
        (folder / "compile.log").write_text(compile_run.stdout + compile_run.stderr)
        if compile_run.returncode:
            raise RuntimeError(f"compile failed, not a functional test result: {folder}")
        simulation = subprocess.run(commands[1], cwd=folder, text=True, capture_output=True, timeout=60)
        log = simulation.stdout + simulation.stderr
        (folder / "run.log").write_text(log)
        expected_fail = bool(mutation) or args.shell_baseline
        detected = simulation.returncode != 0 and ("FIELD_SCOREBOARD" in log or "TL_CONSUMER" in log)
        passed = detected if expected_fail else simulation.returncode == 0 and f"PASS vectors={len(cases)}" in log
        result["cases"].append(dict(name=name, commands=commands, returncode=simulation.returncode,
                                    expected_failure=expected_fail, passed=passed, output=log.strip()))
    result["passed"] = all(case["passed"] for case in result["cases"])
    result["artifact_sha256"] = {str(p.relative_to(out)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in sorted(out.rglob("*")) if p.is_file()}
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(dict(directory=str(out), passed=result["passed"], vectors=len(cases), cases=result["cases"]), indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
