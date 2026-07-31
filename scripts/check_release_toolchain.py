#!/usr/bin/env python3
"""Fail fast when the portable 1.0 regression host is incomplete."""

from __future__ import annotations

import hashlib
import importlib.metadata
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
COMMANDS = (
    ("Git", ("git",), ("--version",)),
    ("GNU Make", ("make",), ("--version",)),
    ("GCC C++ compiler", ("g++",), ("--version",)),
    ("Verilator", ("verilator",), ("--version",)),
    ("verilator_coverage", ("verilator_coverage",), ("--version",)),
    ("Yosys", ("yosys",), ("-V",)),
    ("Icarus Verilog", ("iverilog",), ("-V",)),
    ("Icarus Verilog runtime", ("vvp",), ("-V",)),
    ("OpenSTA", ("sta", "opensta"), ("-version",)),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def command_output(executable: str, arguments: tuple[str, ...]) -> str:
    result = subprocess.run(
        [executable, *arguments],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"exit {result.returncode}: {result.stdout.strip()}")
    return result.stdout.strip()


def main() -> int:
    errors: list[str] = []
    system = platform.system()
    machine = platform.machine().lower()
    if system != "Linux" or machine not in {"x86_64", "amd64"}:
        errors.append(
            f"the hash-locked release environment is Linux x86-64, found {system} {machine}"
        )
    if sys.version_info[:2] != (3, 12):
        errors.append(
            f"requirements-dev.lock requires CPython 3.12, found {platform.python_version()}"
        )

    manifest = yaml.safe_load(
        (ROOT / "third_party" / "dependencies.yaml").read_text(encoding="utf-8")
    )
    dependencies = {
        str(item["name"]): item for item in manifest.get("dependencies", [])
    }
    python_entry = dependencies.get("Python")
    if python_entry is None or str(python_entry["version"]) != platform.python_version():
        errors.append("the running Python version disagrees with third_party/dependencies.yaml")
    else:
        print(f"TOOL Python version={platform.python_version()}")

    pip_entry = dependencies.get("pip")
    try:
        pip_version = importlib.metadata.version("pip")
    except importlib.metadata.PackageNotFoundError:
        errors.append("pip is unavailable; create the release environment with ensurepip")
    else:
        if pip_entry is None or str(pip_entry["version"]) != pip_version:
            errors.append("the installed pip version disagrees with third_party/dependencies.yaml")
        else:
            print(f"TOOL pip version={pip_version}")

    for name, candidates, arguments in COMMANDS:
        entry = dependencies.get(name)
        if entry is None:
            errors.append(f"dependency manifest is missing {name}")
            continue
        executable = next(
            (shutil.which(candidate) for candidate in candidates if shutil.which(candidate)),
            None,
        )
        if executable is None:
            errors.append(f"required command is unavailable: {' or '.join(candidates)}")
            continue
        try:
            output = command_output(executable, arguments)
        except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
            errors.append(f"cannot query {name}: {exc}")
            continue
        expected = str(entry["version"])
        if re.search(rf"(?<![0-9]){re.escape(expected)}(?![0-9])", output) is None:
            errors.append(
                f"{name} version does not contain declared {expected}: {output.splitlines()[0]}"
            )
            continue
        print(
            f"TOOL {name} version={expected} "
            f"executable_sha256={sha256(Path(executable).resolve())}"
        )

    requirement_lines = (ROOT / "requirements-dev.txt").read_text(
        encoding="utf-8"
    ).splitlines()
    for raw_line in requirement_lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        name, expected = line.split("==", 1)
        try:
            actual = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            errors.append(f"locked Python package is unavailable: {name}=={expected}")
            continue
        if actual != expected:
            errors.append(
                f"Python package mismatch: {name} expected={expected} actual={actual}"
            )
        else:
            print(f"PYTHON_PACKAGE {name}=={actual}")

    reuse_executable = shutil.which("reuse")
    if reuse_executable is None:
        errors.append("required command is unavailable: reuse")
    else:
        try:
            output = command_output(reuse_executable, ("--version",))
        except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
            errors.append(f"cannot query reuse: {exc}")
        else:
            expected = str(dependencies.get("reuse", {}).get("version", ""))
            if not expected or re.search(
                rf"(?<![0-9]){re.escape(expected)}(?![0-9])", output
            ) is None:
                errors.append(f"reuse version does not contain declared {expected}: {output}")
            else:
                print(
                    f"TOOL reuse version={expected} "
                    f"executable_sha256={sha256(Path(reuse_executable).resolve())}"
                )

    if errors:
        for message in errors:
            print(f"ERROR: {message}", file=sys.stderr)
        print(f"RELEASE_TOOLCHAIN_FAIL errors={len(errors)}", file=sys.stderr)
        return 1
    print("RELEASE_TOOLCHAIN_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
