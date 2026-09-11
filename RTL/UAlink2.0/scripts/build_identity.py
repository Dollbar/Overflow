"""Bind channel EDA consumers to the actual inputs and mapped artifacts.

Run through scripts/channel.mk; or provide its UALINK_* environment and run
python3 scripts/build_identity.py synth|equiv|sta -- <tool> <arguments>.
Output: build_identity.json and ordinary tool output; failures return nonzero.
Next: inspect actual equivalence/STA results. Freshness is not a correctness proof.
Paths are explicit or project-relative. Previous mapped outputs are moved to a
recoverable previous_build/ attempt before rebuilding; external inputs are read-only.
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
    "rtl/upli/upli_receive_fifo.v", "rtl/upli/upli_receive_storage.v",
    "rtl/upli/upli_credit_initializer.v", "rtl/upli/upli_credit_return_queue.v",
    "rtl/upli/upli_receive_channel.v", "scripts/channel.mk",
    "scripts/channel_config.tcl", "scripts/synth_channel.tcl",
    "scripts/equiv_channel.tcl", "scripts/sta_channel.tcl",
    "scripts/check_channel_report.py", "scripts/credit_abc.constr",
    "scripts/buffer_storage.py", "scripts/size_channel.py", "scripts/build_identity.py",
)
DEPENDENCIES = (
    "Library/models/kd28/fifo/rtl/kd28_fifo_sdp_storage_map.v",
    "Library/models/kd28/sram/rtl/kd28_sram_blackboxes.v",
)
OUTPUTS = ("mapped.v", "mapped.json", "area.json")


@dataclass(frozen=True)
class BuildContext:
    root: Path
    run_dir: Path
    kd_root: Path
    mapping_library: Path
    parameters: dict
    mapping_tool: Path
    analysis_libraries: tuple = ()


def _digest(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"missing or empty identity input: {path}")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _inputs(context):
    return {
        "sources": {name: _digest(context.root / name) for name in SOURCES},
        "dependencies": {name: _digest(context.kd_root / name) for name in DEPENDENCIES},
        "mapping_library_sha256": _digest(context.mapping_library),
        "mapping_tool_sha256": _digest(context.mapping_tool),
        "parameters": dict(context.parameters),
    }


def _outputs(context):
    return {name: _digest(context.run_dir / name) for name in OUTPUTS}


def _write(path, record):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix="identity-", delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(record, stream, indent=2)
        stream.write("\n")
    temporary.replace(path)


def _verify(record, inputs, outputs):
    if record.get("schema_version") != 1 or record.get("status") != "ready":
        raise ValueError("build identity is not ready; run synth-channel first")
    if record.get("inputs") != inputs or record.get("artifacts") != outputs:
        raise ValueError("stale source, parameters, dependency or mapped artifact; rebuild required")


def run_stage(stage, context, command):
    if stage not in ("synth", "equiv", "sta") or not command:
        raise ValueError("explicit stage and tool command required")
    build_root = (context.root / "build").resolve()
    run = context.run_dir.resolve()
    if run == build_root or not run.is_relative_to(build_root):
        raise ValueError("identity build directory must be a child of the project build directory")
    run.mkdir(parents=True, exist_ok=True)
    manifest = run / "build_identity.json"
    lock_path = run / "build_identity.lock"
    if lock_path.is_symlink() or manifest.is_symlink():
        raise ValueError("identity control files cannot be symlinks")
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("another EDA stage is using this build directory") from error
        inputs = _inputs(context)
        analysis = [_digest(path) for path in context.analysis_libraries]
        if stage == "synth":
            existing = [run / name for name in (*OUTPUTS, "build_identity.json") if (run / name).exists()]
            if any(path.is_symlink() or not path.is_file() for path in existing):
                raise ValueError("mapped outputs must be regular files")
            if existing:
                archive_root = run / "previous_build"
                if archive_root.is_symlink():
                    raise ValueError("previous build archive cannot be a symlink")
                archive_root.mkdir(exist_ok=True)
                archive = Path(tempfile.mkdtemp(prefix="attempt-", dir=archive_root))
                for path in existing:
                    path.rename(archive / path.name)
                print(f"Saved previous mapped outputs in {archive}", flush=True)
            record = {"schema_version": 1, "status": "building", "inputs": inputs}
            _write(manifest, record)
        else:
            if not manifest.is_file():
                raise ValueError("missing build identity; existing netlist alone is insufficient")
            record = json.loads(manifest.read_text())
            _verify(record, inputs, _outputs(context))
        result = subprocess.run(command, check=False).returncode
        if result:
            if stage == "synth":
                record["status"] = "failed"
                _write(manifest, record)
            return result
        if _inputs(context) != inputs or [_digest(path) for path in context.analysis_libraries] != analysis:
            raise ValueError("EDA inputs changed during execution; result cannot be accepted")
        outputs = _outputs(context)
        if stage == "synth":
            record.update(status="ready", artifacts=outputs)
            _write(manifest, record)
        else:
            _verify(record, inputs, outputs)
        print(f"PASS channel build identity stage={stage}; correctness uses the separate EDA result", flush=True)
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("synth", "equiv", "sta"))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        required = ("UALINK_BUILD_DIR", "UALINK_KD28_ROOT", "UALINK_MAPPING_LIBERTY", "UALINK_YOSYS",
                    "UALINK_PORTS", "UALINK_WIDTH", "UALINK_CREDIT_WIDTH", "UALINK_CAP_HEX",
                    "UALINK_RETURN_DEPTH", "UALINK_READ_CONTROL_BUFFERS", "UALINK_HOLD", "UALINK_MAPPING_CORNER")
        if any(not os.environ.get(name) for name in required):
            raise ValueError("missing explicit UALINK build identity environment")
        tool = shutil.which(os.environ["UALINK_YOSYS"])
        if not tool:
            raise ValueError("mapping executable not found")
        parameters = {name.removeprefix("UALINK_").lower(): os.environ[name] for name in required[4:]}
        analysis = tuple(Path(os.environ[name]) for name in ("UALINK_LIBERTY", "UALINK_MACRO_LIBERTY")
                         if os.environ.get(name))
        context = BuildContext(Path(__file__).resolve().parents[1], Path(os.environ["UALINK_BUILD_DIR"]),
                               Path(os.environ["UALINK_KD28_ROOT"]), Path(os.environ["UALINK_MAPPING_LIBERTY"]),
                               parameters, Path(tool), analysis)
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        return run_stage(args.stage, context, command)
    except (OSError, ValueError, TypeError) as error:
        print(f"FAIL channel build identity: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
