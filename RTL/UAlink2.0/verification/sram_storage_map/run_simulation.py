#!/usr/bin/env python3
"""Run actual KD28 storage mapper/macros against an independent logical memory.

Example (repository root):
  python3 verification/sram_storage_map/run_simulation.py \
    --kd28-root /authorized/KD28/project --label storage_mapping
Outputs: reports/sram_storage_map/simulation_<label>/summary.json and per-case
stimuli, compilation/runtime logs and binaries. Next: inspect every case and
mutation verdict; keep macro STA and full Endpoint/Switch closure separate.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import time


REPO = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WIDTHS = (8, 32, 40, 256, 512, 600)
DEPTHS = (1, 2, 3, 5, 255, 256, 257, 511, 512, 513, 1024, 1025, 2048, 2049, 4097, 65535)
SOURCES = (
    "Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v",
    "Library/models/kd28/sram/rtl/kd28_sram_cells.v",
    "Library/models/kd28/sram/rtl/kd28_sram_sdp_model.v",
    "Library/models/kd28/sram/rtl/kd28_sram_sp_model.v",
    "Library/models/kd28/sram/rtl/kd28_sram_tdp_model.v",
)
MUTATIONS = {
    "data_lane": (
        "write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH]",
        "(write_data_padded[lane_index*MACRO_WIDTH +: MACRO_WIDTH] ^ {{(MACRO_WIDTH-1){1'b0}}, 1'b1})",
        4,
    ),
    "read_bank_bypass": (
        "bank_read_data[(read_bank_q*PHYSICAL_WIDTH) +: DATA_WIDTH]",
        "bank_read_data[(read_bank_select*PHYSICAL_WIDTH) +: DATA_WIDTH]",
        1,
    ),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def run(command: list[str], cwd: Path, stem: str, timeout: float) -> dict:
    """Retain actual tool exit status; timeout never counts as mutant detection."""
    start = time.monotonic()
    result = {"command": command, "cwd": str(cwd), "timeout": False}
    with (cwd / f"{stem}.log").open("w") as log:
        try:
            completed = subprocess.run(command, cwd=cwd, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=timeout, check=False)
            result["returncode"] = completed.returncode
        except subprocess.TimeoutExpired:
            result.update(returncode=None, timeout=True)
    result["seconds"] = round(time.monotonic() - start, 3)
    write_json(cwd / f"{stem}.json", result)
    return result


def vectors(path: Path, width: int, depth: int, seed: int, random_steps: int) -> dict:
    """Generate stimuli only: expected data is produced by the flat-memory TB.

    No row/lane/bank decoder participates in the reference. Literal address
    landmarks exercise every macro-depth transition and 2048-word bank boundary.
    """
    rng = random.Random(seed)
    mask = (1 << width) - 1
    count = 0
    phases: dict[str, int] = {}
    with path.open("w") as stream:
        def emit(mode: int, we: int, wa: int, re_: int, ra: int, data: int = 0) -> None:
            nonlocal count
            stream.write(f"{mode} {we} {wa} {re_} {ra} {data & mask:x}\n")
            count += 1

        # Whole-address fill/readback detects missing decode bits, row aliases,
        # and incorrect bank enables with independently random full-word data.
        for address in range(depth):
            emit(1, 1, address, 0, 0, rng.getrandbits(width))
        emit(2, 0, 0, 1, 0)  # Establish a known registered bank.
        emit(2, 0, 0, 0, depth - 1)  # Switch bank/address during an explicitly disabled read.
        for address in reversed(range(depth)):
            emit(2, 0, 0, 1, address)
        phases["all_address_fill_readback"] = count

        start = count
        for address in sorted({0, depth - 1}):
            for data in (0, mask):
                emit(1, 1, address, 0, address, data)
                emit(2, 0, address, 1, address)
            for bit in range(width):
                for data in (1 << bit, mask ^ (1 << bit)):
                    emit(1, 1, address, 0, address, data)
                    emit(2, 0, address, 1, address)
        phases["walking_one_zero_all_bits_first_last"] = count - start

        start = count
        landmarks = {0, depth - 1}
        for point in (1, 2, 3, 4, 255, 256, 257, 511, 512, 513, 1023, 1024, 1025):
            if point < depth:
                landmarks.add(point)
        for boundary in range(2048, depth, 2048):
            landmarks.update((boundary - 1, boundary))
            if boundary + 1 < depth:
                landmarks.add(boundary + 1)
        for address in sorted(landmarks):
            opposite = depth - 1 if address == 0 else 0
            emit(1, 1, address, 0, opposite, rng.getrandbits(width))
            emit(2, 0, opposite, 1, address)
            # Vary read-bank address with read enable low, both without an edge
            # and on a read edge, while the last registered result must hold.
            emit(0, 1, address, 0, opposite, rng.getrandbits(width))
            emit(2, 0, address, 0, opposite)
            emit(3, 0, address, 0, opposite, rng.getrandbits(width))
            emit(2, 0, opposite, 1, address)  # Disabled write left memory intact.
            emit(3, 1, address, 1, address, rng.getrandbits(width))
            emit(2, 0, opposite, 1, address)  # Read updated data after old-data collision.
            emit(1, 1, address, 1, opposite, rng.getrandbits(width))
            emit(2, 0, address, 1, address)  # No read edge during preceding write.
        phases["boundaries_enables_hold_and_collisions"] = count - start

        start = count
        for _ in range(random_steps):
            mode, we, re_ = rng.randrange(4), rng.randrange(2), rng.randrange(2)
            wa, ra = rng.randrange(depth), rng.randrange(depth)
            if rng.randrange(4) == 0:
                ra = wa
            emit(mode, we, wa, re_, ra, rng.getrandbits(width))
        # A final full sweep checks all writes, including writes with no nearby
        # random read; random enable failures cannot escape as unread state.
        for address in range(depth):
            emit(2, 0, 0, 1, address)
        phases["random_and_final_all_address_readback"] = count - start
    return {"vectors": count, "phases": phases, "landmarks": sorted(landmarks),
            "random_steps": random_steps, "seed": seed, "sha256": digest(path)}


def case(output: Path, sources: list[Path], tb: Path, width: int, depth: int,
         mutation: str | None, args: argparse.Namespace) -> dict:
    name = f"w{width}_d{depth}" + (f"_{mutation}" if mutation else "")
    directory = output / name
    directory.mkdir(mode=0o700)
    result = {"name": name, "width": width, "depth": depth,
              "logical_depth": depth, "mapped_depth": max(2, depth),
              "address_width": depth.bit_length(),
              "mutation": mutation, "status": "not_run"}
    try:
        case_sources = list(sources)
        if mutation:
            original = sources[0].read_text()
            before, after, expected_count = MUTATIONS[mutation]
            actual_count = original.count(before)
            if actual_count != expected_count:
                raise ValueError(f"mutation source anchor changed: expected {expected_count}, got {actual_count}")
            mutated = directory / "mutated_storage_map.v"
            mutated.write_text(original.replace(before, after))
            mutated.chmod(0o600)
            case_sources[0] = mutated
            result["mutation_record"] = {"before": before, "after": after,
                                          "replacements": actual_count, "sha256": digest(mutated)}
        result["stimulus"] = vectors(directory / "vectors.txt", width, depth,
                                     args.seed ^ (width << 16) ^ depth, args.random_steps)
        compile_command = [args.iverilog, "-g2012", "-Wall", "-s", "simulation_tb",
                           f"-Psimulation_tb.WIDTH={width}", f"-Psimulation_tb.DEPTH={depth}",
                           f"-Psimulation_tb.MAPPED_DEPTH={max(2, depth)}",
                           f"-Psimulation_tb.ADDR_WIDTH={depth.bit_length()}",
                           "-o", "simulation.vvp", str(tb), *map(str, case_sources)]
        result["compile"] = run(compile_command, directory, "compile", args.timeout)
        if result["compile"]["returncode"] != 0:
            result["status"] = "compile_failed"
        else:
            result["simulation"] = run([args.vvp, "simulation.vvp", "+vectors=vectors.txt"],
                                       directory, "simulation", args.timeout)
            log = (directory / "simulation.log").read_text()
            code = result["simulation"]["returncode"]
            pass_lines = re.findall(r"^PASS (.+)$", log, re.MULTILINE)
            if mutation:
                # An actual comparison failure, never malformed input, compile
                # failure, coverage-only failure, timeout or an injected marker.
                caught = code is not None and code > 0 and bool(re.search(
                    r"FAIL (data|preedge_hold|padding) cycle=", log)) and not pass_lines
                result["status"] = "detected" if caught else "mutation_not_detected"
            else:
                result["status"] = "pass" if code == 0 and len(pass_lines) == 1 and "FAIL" not in log else "failed"
                if pass_lines:
                    result["coverage"] = {key: int(value) for key, value in
                                          re.findall(r"(\w+)=(\d+)", pass_lines[0])}
                    for field in ("logical_depth", "mapped_depth", "address_width"):
                        if result["coverage"].get(field) != result[field]:
                            result["status"] = "parameter_mismatch"
    except Exception as error:
        result.update(status="error", error=f"{type(error).__name__}: {error}")
    write_json(directory / "result.json", result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--kd28-root", type=Path, required=True, help="Explicit authorized external project root")
    parser.add_argument("--label", required=True, help="New evidence label; existing labels are refused")
    parser.add_argument("--widths", type=int, nargs="+", default=list(WIDTHS))
    parser.add_argument("--depths", type=int, nargs="+", default=list(DEPTHS))
    parser.add_argument("--seed", type=int, default=73129)
    parser.add_argument("--random-steps", type=int, default=512)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--mode", choices=("all", "positive", "mutations"), default="all")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.label):
        parser.error("label must contain only letters, digits, underscore, dot and dash")
    if any(w <= 0 or w % 8 for w in args.widths) or any(d < 1 or d > 65535 for d in args.depths):
        parser.error("widths must be positive multiples of 8; depths must be in 1..65535")
    if args.jobs < 1 or args.random_steps < 1 or args.timeout <= 0:
        parser.error("jobs, random-steps and timeout must be positive")
    args.widths = list(dict.fromkeys(args.widths))
    args.depths = list(dict.fromkeys(args.depths))
    root = args.kd28_root.expanduser().resolve()
    external = [root / relative for relative in SOURCES]
    if missing := [str(path) for path in external if not path.is_file()]:
        parser.error(f"missing authorized dependency: {missing}")
    for tool in ("iverilog", "vvp"):
        resolved = shutil.which(getattr(args, tool))
        if not resolved:
            parser.error(f"missing tool: {getattr(args, tool)}")
        setattr(args, tool, resolved)
    output = REPO / "reports" / "sram_storage_map" / f"simulation_{args.label}"
    if output.exists():
        parser.error(f"evidence already exists; choose a new --label: {output}")
    output.mkdir(parents=True, mode=0o700)
    source_dir = output / "private_sources"
    source_dir.mkdir(mode=0o700)
    # Archive authorized source snapshots under a private directory. Never modify
    # the external dependency, and never stage these restricted artifacts.
    manifest = []
    sources = []
    for path, relative in zip(external, SOURCES):
        target = source_dir / path.name
        shutil.copyfile(path, target)
        target.chmod(0o600)
        sources.append(target)
        manifest.append({"relative_path": relative, "sha256": digest(target), "source": str(path)})
    tb = output / "simulation_tb.sv"
    shutil.copyfile(HERE / "simulation_tb.sv", tb)
    shutil.copyfile(Path(__file__), output / "run_simulation.py")
    summary = {"scope": "KD28 logical storage mapping digital simulation; no macro STA or full IP claim",
               "label": args.label, "kd28_root": str(root), "sources": manifest,
               "parameter_profile": "production_count_address_width_and_minimum_two_mapped_words",
               "tb_sha256": digest(tb), "runner_sha256": digest(Path(__file__)),
               "widths": args.widths, "depths": args.depths, "seed": args.seed,
               "random_steps": args.random_steps, "cases": [], "status": "running"}
    for tool in ("iverilog", "vvp"):
        run([getattr(args, tool), "-V"], output, f"tool_{tool}", 30)
    write_json(output / "summary.json", summary)
    configurations = []
    if args.mode in ("all", "mutations"):
        configurations.extend(((40, 5, "data_lane"), (40, 2049, "read_bank_bypass")))
    if args.mode in ("all", "positive"):
        configurations.extend((w, d, None) for w in args.widths for d in args.depths)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as executor:
        pending = [executor.submit(case, output, sources, tb, w, d, mutation, args)
                   for w, d, mutation in configurations]
        for future in concurrent.futures.as_completed(pending):
            result = future.result()
            summary["cases"].append(result)
            write_json(output / "summary.json", summary)
            print(f"{result['status']:22} {result['name']}", flush=True)
    summary["cases"].sort(key=lambda item: item["name"])
    summary["positive_passed"] = sum(c["status"] == "pass" for c in summary["cases"])
    summary["mutations_detected"] = sum(c["status"] == "detected" for c in summary["cases"])
    summary["positive_planned"] = sum(m is None for _, _, m in configurations)
    summary["mutations_planned"] = sum(m is not None for _, _, m in configurations)
    summary["external_sources_unchanged"] = all(digest(path) == record["sha256"]
                                                 for path, record in zip(external, manifest))
    passed = all(c["status"] in ("pass", "detected") for c in summary["cases"])
    summary["status"] = "pass" if passed and summary["external_sources_unchanged"] else "fail"
    write_json(output / "summary.json", summary)
    print(f"{summary['status']}: {summary['positive_passed']}/{summary['positive_planned']} positive, "
          f"{summary['mutations_detected']}/{summary['mutations_planned']} mutations; {output / 'summary.json'}")
    return 0 if summary["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
