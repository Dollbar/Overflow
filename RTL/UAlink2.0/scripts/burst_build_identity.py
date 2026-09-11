"""Run through scripts/burst.mk: bind burst EDA to current inputs and outputs.

Output: build_identity.json and ordinary tool logs; failures return nonzero.
Next: inspect actual equivalence/STA. Freshness is not a correctness proof.
Old mapped attempts are retained under previous_build, external libraries read-only.
"""

import argparse
from dataclasses import dataclass
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


SOURCES = (
    "rtl/upli/upli_burst_control.v", "config/upli_burst_control_contract.json",
    "scripts/burst.mk", "scripts/synth_burst_control.tcl",
    "scripts/equiv_burst_control.tcl", "scripts/sta_burst_control.tcl",
    "scripts/burst_abc.constr", "scripts/check_sta_report.py",
    "scripts/burst_build_identity.py", "scripts/size_burst_control.tcl",
    "scripts/apply_burst_sizing.tcl",
)
OUTPUTS = ("mapped.v", "mapped.json", "area.json")


@dataclass(frozen=True)
class BurstContext:
    root: Path
    run_dir: Path
    mapping_library: Path
    parameters: dict
    mapping_tool: Path
    analysis_library: Path | None = None
    abc_tool: Path | None = None
    sizing_tool: Path | None = None


def digest(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"missing or empty identity input: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inputs(context):
    return {"sources": {name: digest(context.root / name) for name in SOURCES},
            "mapping_library": digest(context.mapping_library),
            "mapping_tool": digest(context.mapping_tool),
            "abc_tool": digest(context.abc_tool) if context.abc_tool else None,
            "sizing_tool": digest(context.sizing_tool) if context.sizing_tool else None,
            "parameters": dict(context.parameters)}


def outputs(run):
    return {name: digest(run / name) for name in OUTPUTS}


def write_record(path, record):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix="identity-", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(record, stream, indent=2)
        stream.write("\n")
    temporary.replace(path)


def verify(record, expected_inputs, actual_outputs):
    if record.get("profile") != "burst_control" or record.get("schema_version") != 1 or record.get("status") != "ready":
        raise ValueError("burst build identity is not ready; fresh synthesis required")
    if record.get("inputs") != expected_inputs or record.get("artifacts") != actual_outputs:
        raise ValueError("stale burst source, parameters, tool, library or mapped output")


def run_stage(stage, context, command):
    if stage not in ("synth", "equiv", "sta") or not command:
        raise ValueError("explicit supported stage and command required")
    build = (context.root / "build").resolve()
    run = context.run_dir.resolve()
    if run == build or not run.is_relative_to(build):
        raise ValueError("burst build must be a child of the project build directory")
    run.mkdir(parents=True, exist_ok=True)
    manifest = run / "build_identity.json"
    lock_path = run / "build_identity.lock"
    if manifest.is_symlink() or lock_path.is_symlink():
        raise ValueError("identity files cannot be symlinks")
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("another EDA stage owns this burst build") from error
        before = inputs(context)
        analysis_before = digest(context.analysis_library) if context.analysis_library else None
        if stage == "synth":
            existing = [run / name for name in (*OUTPUTS, "build_identity.json")
                        if (run / name).exists() or (run / name).is_symlink()]
            if any(p.is_symlink() or not p.is_file() for p in existing):
                raise ValueError("mapped outputs must be regular files")
            if existing:
                archives = run / "previous_build"
                if archives.is_symlink():
                    raise ValueError("archive directory cannot be a symlink")
                archives.mkdir(exist_ok=True)
                archive = Path(tempfile.mkdtemp(prefix="attempt-", dir=archives))
                for path in existing:
                    path.rename(archive / path.name)
            record = {"schema_version": 1, "profile": "burst_control", "status": "building", "inputs": before}
            write_record(manifest, record)
        else:
            if not manifest.is_file():
                raise ValueError("missing burst build identity")
            record = json.loads(manifest.read_text())
            verify(record, before, outputs(run))
        status = subprocess.run(command, check=False).returncode
        if status:
            if stage == "synth":
                record["status"] = "failed"
                write_record(manifest, record)
            return status
        analysis_after = digest(context.analysis_library) if context.analysis_library else None
        if inputs(context) != before or analysis_before != analysis_after:
            raise ValueError("burst EDA input changed during execution")
        actual_outputs = outputs(run)
        if stage == "synth":
            record.update(status="ready", artifacts=actual_outputs)
            write_record(manifest, record)
        else:
            verify(record, before, actual_outputs)
        print(f"PASS burst build identity stage={stage}; EDA correctness is checked separately", flush=True)
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("synth", "equiv", "sta"))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        required = ("UALINK_BUILD_DIR", "UALINK_MAPPING_LIBERTY", "UALINK_YOSYS", "UALINK_ABC", "UALINK_STA",
                    "UALINK_PORTS", "UALINK_CREDIT_WIDTH", "UALINK_MAPPING_CORNER")
        if any(not os.environ.get(key) for key in required):
            raise ValueError("missing explicit burst identity environment")
        yosys = shutil.which(os.environ["UALINK_YOSYS"])
        abc = shutil.which(os.environ["UALINK_ABC"])
        sta = shutil.which(os.environ["UALINK_STA"])
        if not yosys or not abc or not sta:
            raise ValueError("actual Yosys/ABC/OpenSTA executable not found")
        parameters = {key.removeprefix("UALINK_").lower(): os.environ[key] for key in required[5:]}
        analysis = Path(os.environ["UALINK_LIBERTY"]) if os.environ.get("UALINK_LIBERTY") else None
        context = BurstContext(Path(__file__).resolve().parents[1], Path(os.environ["UALINK_BUILD_DIR"]),
                               Path(os.environ["UALINK_MAPPING_LIBERTY"]), parameters, Path(yosys), analysis, Path(abc), Path(sta))
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        return run_stage(args.stage, context, command)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"FAIL burst build identity: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
