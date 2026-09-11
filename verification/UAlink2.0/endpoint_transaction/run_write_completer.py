#!/usr/bin/env python3
"""Run assembled Write execution against independent byte memory and response fields.

Run: python3 verification/endpoint_transaction/run_write_completer.py --label NEW
Outputs: reports/endpoint_transaction/write_completer_NEW/{summary.json,*,snapshots}.
Next: connect the real receiver and shared ordered Read/Write backend dispatch.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import time

ROOT = (lambda _ualink_file: next(((_ualink_dir / (_ualink_dir / '.ualink-root').read_text(encoding='utf-8').strip()).resolve() for _ualink_dir in _ualink_file.parents if (_ualink_dir / '.ualink-root').is_file()), Path(__file__).resolve().parents[2]))(__import__('pathlib').Path(__file__).resolve())
RTL = ROOT / "rtl/endpoint/endpoint_write_completer.v"
TB = Path(__file__).with_name("write_completer_tb.sv")


def vectors(folder: Path) -> dict:
    rows = []
    memory = bytearray((i * 13 + (i >> 3) * 7 + 19) & 255 for i in range(8192))
    (folder / "initial.hex").write_text("".join(f"{x:02x}\n" for x in memory))
    rng = random.Random(190719)
    cases = [(False, offset * 4, length, 0, None) for offset in range(64) for length in range(64)]
    cases += [(True, offset * 64, length, 0, None) for offset in range(4) for length in (15, 31, 47, 63)]
    cases += [(False, 60, 1, status, None) for status in (0, 2, 3, 6, 8)]
    cases += [(False, 128, 15, 0, "outside_be"), (False, 3, 0, 0, None), (True, 4, 15, 0, None)]
    cases += [(False, 0, 63, 0, bad) for bad in ("dst", "vc", "pool")]
    stats = dict(vectors=len(cases), accepted=0, ordinary=0, full=0, rejected=0, zero_be=0, high_address=0)
    for index, (full, offset, length, status, bad) in enumerate(cases):
        size = 4 * (length + 1)
        address = (index % 16) * 256 + offset + ((1 << 56) if index % 2 else 0)
        tag = (index * 509 + 1024) & 2047
        src = (index * 97 + 512) & 1023
        attr, asi, metadata = (index * 19) & 255, index % 4, (index * 53) & 255
        data = rng.getrandbits(2048)
        span = ((1 << size) - 1) << offset
        mode = index % 5
        be = 0 if mode == 0 else span if mode == 1 else span & int("aa" * 32, 16) if mode == 2 else 1 << offset if mode == 3 else 1 << (offset + size - 1)
        be &= (1 << 256) - 1
        if bad == "outside_be": be |= 1
        if full: be = rng.getrandbits(256)  # Ignored by WriteFull, deliberately not the expected mask.
        legal = (offset % 4 == 0 and offset + size <= 256 and (not full or (offset % 64 == 0 and size % 64 == 0)) and bad not in ("outside_be", "dst", "vc", "pool"))
        expected_be = (span if full else be) & ((1 << 256) - 1)
        control = (2 << 60) | (tag << 47) | (status << 38) | (0x3A5 << 26) | (src << 16)
        if legal:
            stats["accepted"] += 1
            stats["full" if full else "ordinary"] += 1
            stats["zero_be"] += expected_be == 0
            stats["high_address"] += bool(address >> 56)
            if status == 0:
                # Region-based oracle, independent of the backend's relative-beat loops.
                region = (address & 4095) & ~255
                first_beat = (offset // 64) * 64
                for byte in range(256):
                    if expected_be >> byte & 1:
                        memory[(4096 if address >> 56 else 0) + region + byte] = data >> (8 * (byte - first_beat)) & 255
        else: stats["rejected"] += 1
        dst = 0x3A4 if bad == "dst" else 0x3A5
        fields = [int(legal), int(full), address, length, attr, asi, metadata, tag, src, dst, int(bad == "vc"), int(bad == "pool"), data, be, expected_be, status, control]
        rows.append(" ".join(f"{x:x}" for x in fields) + "\n")
    (folder / "vectors.txt").write_text("".join(rows))
    (folder / "final.hex").write_text("".join(f"{x:02x}\n" for x in memory))
    return stats


def execute(command: list[str], folder: Path, name: str) -> dict:
    start = time.monotonic()
    with (folder / (name + ".log")).open("w") as output:
        try:
            result = subprocess.run(command, cwd=folder, stdout=output, stderr=subprocess.STDOUT, timeout=120)
            code = result.returncode
        except subprocess.TimeoutExpired: code = 124
    row = dict(command=command, returncode=code, seconds=round(time.monotonic() - start, 3))
    (folder / (name + ".json")).write_text(json.dumps(row, indent=2) + "\n")
    return row


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--label", required=True)
    p.add_argument("--capacity", type=int, choices=(1, 2, 3, 4), default=4)
    p.add_argument("--slot-width", type=int, choices=(1, 2))
    p.add_argument("--shell-baseline", action="store_true")
    p.add_argument("--faults", action="store_true")
    p.add_argument("--synth", action="store_true")
    a = p.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", a.label): p.error("safe fresh label required")
    sw = a.slot_width or max(1, (a.capacity - 1).bit_length())
    if (1 << sw) < a.capacity: p.error("slot width cannot represent capacity")
    output = ROOT / "reports/endpoint_transaction" / ("write_completer_" + a.label)
    output.mkdir(parents=True, exist_ok=False)
    original = RTL.read_text()
    (output / "source.v").write_text(original)
    shutil.copyfile(__file__, output / "run_write_completer.py")
    parameter = f"#(.CAPACITY({a.capacity})" + (f",.SLOT_WIDTH({sw})" if a.slot_width else "") + ")"
    if a.shell_baseline:
        tb = "module tb;wire ready,implemented;endpoint_write_completer dut(.i_clk(1'b0),.i_rstn(1'b1),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'd0),.i_meta(128'd0),.o_ready(ready),.o_implemented(implemented));initial begin #1;if(!ready||!implemented)$fatal(1,\"WRITE_COMPLETER_UNIMPLEMENTED\");$finish;end endmodule\n"
    else:
        tb = TB.read_text().replace("@@CAPACITY@@", str(a.capacity)).replace("@@SLOT_WIDTH@@", str(sw)).replace("@@PARAMETERS@@", parameter)
    (output / "tb.sv").write_text(tb)
    mutations = {
        "address_high": ("assign o_mem_address=issue_address;", "assign o_mem_address={1'b0,issue_address[55:0]};"),
        "early_response": ("assign o_source_valid=active&&head_busy&&head_complete;", "assign o_source_valid=active&&head_busy;"),
        "region_be": ("assign o_mem_be=issue_be;", "assign o_mem_be={issue_be[127:0],issue_be[255:128]};"),
        "upper_beat": ("assign o_mem_data=issue_data;", "assign o_mem_data={issue_data[1535:0],issue_data[2047:1536]};"),
    }
    summary = dict(capacity=a.capacity, slot_width=sw, width_mode="explicit" if a.slot_width else "automatic", source_sha256=hashlib.sha256(RTL.read_bytes()).hexdigest(), cases=[])
    for mutation in [None] + (list(mutations) if a.faults and not a.shell_baseline else []):
        folder = output / (mutation or "normal"); folder.mkdir()
        text = original
        if mutation:
            before, after = mutations[mutation]
            if text.count(before) != 1: raise ValueError("ambiguous mutation anchor " + mutation)
            text = text.replace(before, after)
        (folder / "dut.v").write_text(text)
        row = dict(mutation=mutation)
        if not a.shell_baseline: row["vectors"] = vectors(folder)
        row["compile"] = execute(["iverilog", "-g2012", "-s", "tb", "-o", "sim.vvp", "dut.v", str(output / "tb.sv")], folder, "compile")
        row["passed"] = False
        if row["compile"]["returncode"] == 0:
            row["run"] = execute(["vvp", "sim.vvp"], folder, "run")
            log = (folder / "run.log").read_text()
            row["passed"] = row["run"]["returncode"] == 0 and "WRITE_COMPLETER_PASS" in log
            if mutation: row["passed"] = row["run"]["returncode"] == 1 and any(s in log for s in ("WRITE_MEMORY_FIELDS", "WRITE_MEMORY_BE", "WRITE_MEMORY_DATA", "WRITE_EARLY_RESPONSE"))
            row["coverage"] = {k:int(v) for k,v in re.findall(r"(\w+)=(\d+)", log)}
        summary["cases"].append(row)
        print(mutation or "normal", row["passed"], flush=True)
    if a.synth and not a.shell_baseline:
        folder=output/"synthesis";folder.mkdir()
        (folder/"wrapper.v").write_text("module check;endpoint_write_completer " + parameter + " dut();endmodule\n")
        summary["g2001"]=execute(["iverilog","-g2001","-s","check","-o","syntax.vvp","wrapper.v","../source.v"],folder,"g2001")
        (folder/"run.ys").write_text("read_verilog ../source.v\nchparam -set CAPACITY " + str(a.capacity) + (" -set SLOT_WIDTH " + str(sw) if a.slot_width else "") + " endpoint_write_completer\nhierarchy -check -top endpoint_write_completer\nproc\nopt\nmemory\nopt\ncheck -assert\nstat\nwrite_json netlist.json\n")
        summary["synthesis"]=execute(["yosys","-Q","-T","-s","run.ys"],folder,"synthesis")
    summary["passed"] = all(x["passed"] for x in summary["cases"]) and all(summary[k]["returncode"]==0 for k in ("g2001","synthesis") if k in summary)
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(output / "summary.json")
    return 0 if summary["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
