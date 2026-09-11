#!/usr/bin/env python3
"""Check real switch_route_lookup with an independent Python route registry.

Run: python3 verification/ip_tops/run_route_lookup.py --label route_lookup
Output: reports/ip_tops/route_lookup_<label>/summary.json and retained case logs,
stimuli, compiled simulation, source and harness snapshots. Next: update the
inventory/scaffold binding and run the existing integrated Switch regression.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "rtl/switch/switch_route_lookup.v"

SHELL_TB = r'''`timescale 1ns/1ps // 使用确定的独立壳能力红测时间单位。
module lookup_shell_tb; // 检查现有壳确实没有实现服务。
wire implemented, ready; // 观察壳声明的能力和接收行为。
switch_route_lookup dut(.i_clk(1'b0),.i_rstn(1'b1),.i_enable(1'b1),.i_valid(1'b1),.i_data(512'd0),.i_meta(128'd0),.o_ready(ready),.o_implemented(implemented)); // 仅通过既有壳端口发出真实请求。
initial begin // 不以新接口不匹配的编译错误代替行为红测。
 #1; // 等待既有壳组合输出稳定。
 if(implemented!==1'b1) $fatal(1,"FAIL unimplemented_route_lookup implemented=%b ready=%b",implemented,ready); // 尚未实现的实际壳必须产生运行失败。
 $display("PASS implemented service"); $finish; // 只有真实服务声明才通过本能力契约。
end // 结束壳能力红测。
endmodule // 结束lookup_shell_tb。
'''

TB = r'''`timescale 1ns/1ps // 定义独立组合查表测试时间单位。
module route_lookup_tb; // 逐条对比外部独立逻辑目标参考。
parameter PORTS=4; // 从编译命令指定实际端口规模。
reg [PORTS-1:0] valid=0, enabled=0; // 驱动逐源有效和逐目的使能。
reg [PORTS*10-1:0] dst=0, ids=0; // 驱动完整10位目标与表项。
wire [PORTS*PORTS-1:0] match_bits; // 观察全部source-major onehot行。
wire [PORTS-1:0] errors; // 观察逐源有效请求的拒绝状态。
reg [PORTS*PORTS-1:0] expected_match; // 从独立Python字典参考读取完整预期矩阵。
reg [PORTS-1:0] expected_errors; // 从独立参考读取有效门控错误预期。
integer fd, fields, checks=0; // 维护真实刺激解析和比较计数。
switch_route_lookup #(.PORTS(PORTS)) dut(.i_valid(valid),.i_dst(dst),.i_route_ids(ids),.i_port_enable(enabled),.o_match(match_bits),.o_error(errors)); // 只实例化实际lookup，不编译顶层聚合。
initial begin // 顺序运行有限且可重放的刺激文件。
 fd=$fopen("vectors.txt","r"); // 按独立运行目录解析刺激路径。
 if(!fd) $fatal(1,"FAIL missing_vectors"); // 缺失输入必须失败。
 fields=$fscanf(fd,"%h %h %h %h %h %h\n",valid,dst,ids,enabled,expected_match,expected_errors); // 读取完整一条组合输入及独立预期。
 while(fields==6) begin // 对全部有效记录比较整张路由矩阵。
  #1; // 等待组合查找稳定而不提供时钟或复位。
  if(match_bits!==expected_match || errors!==expected_errors) $fatal(1,"FAIL lookup case=%0d valid=%h dst=%h ids=%h enabled=%h match=%h expected=%h error=%h expected_error=%h",checks,valid,dst,ids,enabled,match_bits,expected_match,errors,expected_errors); // 任意源/目标位和错误位不符均实际失败。
  checks=checks+1; // 累计真实比较记录。
  fields=$fscanf(fd,"%h %h %h %h %h %h\n",valid,dst,ids,enabled,expected_match,expected_errors); // 推进下一组合输入。
 end // 结束全部查表刺激。
 if(fields!=-1 || checks==0) $fatal(1,"FAIL malformed_or_empty_vectors"); // 防止空跑或截断输入误报通过。
 $display("PASS ports=%0d checks=%0d",PORTS,checks); $fclose(fd); $finish; // 输出真实检查总数。
end // 结束完整组合查表验证。
endmodule // 结束route_lookup_tb。
'''


def pack(values: list[int], width: int) -> int:
    return sum(value << (index * width) for index, value in enumerate(values))


def stimuli(path: Path, ports: int) -> dict:
    """Use a dictionary of ID -> enabled physical destinations, not RTL logic."""
    phases: dict[str, int] = {}
    count = 0
    rng = random.Random(29173 + ports)
    seen_ids: set[int] = set()
    seen_dst: set[int] = set()
    source_target_pairs: set[tuple[int, int]] = set()
    full = (1 << ports) - 1
    with path.open("w") as stream:
        def emit(ids: list[int], dst: list[int], enable: int, valid: int) -> None:
            nonlocal count
            registry: dict[int, list[int]] = defaultdict(list)
            for target, route_id in enumerate(ids):
                seen_ids.add(route_id)
                if enable & (1 << target):
                    registry[route_id].append(target)
            match, error = 0, 0
            for source, route_id in enumerate(dst):
                seen_dst.add(route_id)
                choices = registry.get(route_id, [])
                if len(choices) == 1:
                    target = choices[0]
                    match |= 1 << (source * ports + target)
                    source_target_pairs.add((source, target))
                elif valid & (1 << source):
                    error |= 1 << source
            stream.write(f"{valid:x} {pack(dst,10):x} {pack(ids,10):x} {enable:x} {match:x} {error:x}\n")
            count += 1

        boundary = [0, 1, 511, 512, 1023][:ports]
        start = count
        for base in range(1024):
            ids = [(base + target * 257) % 1024 for target in range(ports)]
            emit(ids, [ids[(source + base) % ports] for source in range(ports)], full, full)
        phases["all_1024_route_ids_and_source_target_pairs"] = count - start
        start = count
        for requested in range(1024):
            emit(boundary, [(requested + source) % 1024 for source in range(ports)], full, full)
        phases["all_1024_requested_ids_against_boundary_table"] = count - start
        start = count
        for enables in range(1 << ports):
            for valid in range(1 << ports):
                emit(boundary, list(boundary), enables, valid)
        phases["all_enable_valid_masks_self_route"] = count - start
        start = count
        for first in range(ports):
            for second in range(first + 1, ports):
                for duplicate_id in (0, 1, 511, 512, 1023):
                    ids = [(10 + index) for index in range(ports)]
                    ids[first] = duplicate_id
                    ids[second] = duplicate_id
                    for enables in (full, full ^ (1 << first), full ^ (1 << second),
                                    full ^ (1 << first) ^ (1 << second)):
                        for valid in (0, full):
                            emit(ids, [duplicate_id] * ports, enables, valid)
        phases["duplicate_pairs_with_each_enabled_combination"] = count - start
        start = count
        for _ in range(128):
            emit([rng.randrange(1024) for _ in range(ports)],
                 [rng.randrange(1024) for _ in range(ports)], rng.randrange(full + 1), rng.randrange(full + 1))
        phases["random_tables_requests_and_masks"] = count - start
    assert len(seen_ids) == 1024 and len(seen_dst) == 1024
    assert len(source_target_pairs) == ports * ports
    return {"checks": count, "phases": phases, "table_id_values": len(seen_ids),
            "requested_id_values": len(seen_dst), "source_target_pairs": len(source_target_pairs),
            "seed": 29173 + ports, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def execute(command: list[str], directory: Path, stem: str) -> dict:
    start = time.monotonic()
    with (directory / f"{stem}.log").open("w") as log:
        try:
            outcome = subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT,
                                     timeout=120, check=False)
            result = {"command": command, "returncode": outcome.returncode, "timeout": False}
        except subprocess.TimeoutExpired:
            result = {"command": command, "returncode": None, "timeout": True}
    result["seconds"] = round(time.monotonic() - start, 3)
    (directory / f"{stem}.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--label", required=True)
    parser.add_argument("--mode", choices=("functional", "shell"), default="functional")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.label):
        parser.error("choose a safe new evidence label")
    compiler, runtime = shutil.which("iverilog"), shutil.which("vvp")
    if not compiler or not runtime:
        parser.error("iverilog and vvp are required")
    directory = ROOT / "reports/ip_tops" / f"route_lookup_{args.label}"
    if directory.exists():
        parser.error(f"existing evidence is retained; choose a new label: {directory}")
    directory.mkdir(parents=True)
    original = SOURCE.read_text()
    (directory / "source.v").write_text(original)
    (directory / "testbench.sv").write_text(SHELL_TB if args.mode == "shell" else TB)
    shutil.copyfile(__file__, directory / "run_route_lookup.py")
    execute([compiler, "-V"], directory, "iverilog_version")
    summary = {"mode": args.mode, "scope": "unique enabled 10-bit internal destination lookup",
               "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "cases": []}
    configurations = [(1, None)] if args.mode == "shell" else [(p, None) for p in (1, 2, 3, 4, 5)] + [(5, "ignore_id_msb"), (3, "accept_duplicate")]
    mutations = {
        "ignore_id_msb": ("i_route_ids[target*10 +: 10] == i_dst[source*10 +: 10]",
                          "i_route_ids[target*10 +: 9] == i_dst[source*10 +: 9]"),
        "accept_duplicate": ("((candidate_matches & (candidate_matches - 1'b1)) == {PORTS{1'b0}})", "1'b1"),
    }
    for ports, mutation in configurations:
        case_dir = directory / (f"ports{ports}" + (f"_{mutation}" if mutation else ""))
        case_dir.mkdir()
        text = original
        record = {"ports": ports, "mutation": mutation}
        if mutation:
            before, after = mutations[mutation]
            if text.count(before) != 1:
                parser.error(f"mutation anchor changed: {mutation}")
            text = text.replace(before, after)
            record["mutation_change"] = {"before": before, "after": after}
        (case_dir / "dut.v").write_text(text)
        top = "lookup_shell_tb" if args.mode == "shell" else "route_lookup_tb"
        if args.mode != "shell":
            record["stimuli"] = stimuli(case_dir / "vectors.txt", ports)
        command = [compiler, "-g2012", "-Wall", "-s", top]
        if args.mode != "shell":
            command += [f"-Proute_lookup_tb.PORTS={ports}"]
        command += ["-o", "simulation.vvp", str(directory / "testbench.sv"), "dut.v"]
        record["compile"] = execute(command, case_dir, "compile")
        record["status"] = "compile_failed"
        if record["compile"]["returncode"] == 0:
            record["simulation"] = execute([runtime, "simulation.vvp"], case_dir, "simulation")
            log = (case_dir / "simulation.log").read_text()
            code = record["simulation"]["returncode"]
            if mutation:
                record["status"] = "detected" if code is not None and code > 0 and "FAIL lookup case=" in log and "PASS" not in log else "mutation_missed"
            else:
                record["status"] = "pass" if code == 0 and "PASS" in log and "FAIL" not in log else "failed"
                if args.mode != "shell" and record["status"] == "pass":
                    observed = re.search(r"PASS ports=(\d+) checks=(\d+)", log)
                    if not observed or int(observed[1]) != ports or int(observed[2]) != record["stimuli"]["checks"]:
                        record["status"] = "coverage_mismatch"
        (case_dir / "result.json").write_text(json.dumps(record, indent=2) + "\n")
        summary["cases"].append(record)
        print(f"{record['status']}: ports={ports} mutation={mutation}", flush=True)
    summary["status"] = "pass" if all(c["status"] in ("pass", "detected") for c in summary["cases"]) else "fail"
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{summary['status']}: {directory / 'summary.json'}")
    return 0 if summary["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
