#!/usr/bin/env python3
"""Audit KDLink release paths, repository dependencies, and open tool availability."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = ROOT / "config" / "kdlink_toolchain.json"
MANIFEST = ROOT / "simulator" / "kdlink" / "manifest.json"
HOST_PATH_PATTERN = re.compile(r"(?:/" + r"home/|/" + r"Users/|[A-Za-z]:\\\\)")
VERSIONED_ENGINEERING_NAME = re.compile(r"(?:^|[_-])v\d+(?:[._-]|$)", re.IGNORECASE)
PORTABLE_SUFFIXES = {".json", ".py", ".sh", ".tcl", ".yaml", ".yml", ".ys"}
ENGINEERING_ROOTS = (
    ROOT / "rtl" / "kdlink",
    ROOT / "simulator" / "kdlink",
    ROOT / "verification" / "kdlink",
)


def version_tuple(text: str) -> tuple[int, ...]:
    match = re.search(r"\d+(?:\.\d+)+|\d+", text)
    return tuple(int(part) for part in match.group(0).split(".")) if match else ()


def version_at_least(actual: str, minimum: str) -> bool:
    actual_parts = version_tuple(actual)
    minimum_parts = version_tuple(minimum)
    width = max(len(actual_parts), len(minimum_parts))
    return actual_parts + (0,) * (width - len(actual_parts)) >= minimum_parts + (0,) * (width - len(minimum_parts))


def command_version(executable: str) -> str:
    result = subprocess.run(
        [executable, "--version"],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    return result.stdout.splitlines()[0].strip() if result.stdout else ""


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_tools(config: dict[str, object], require_sta: bool, errors: list[str]) -> None:
    groups = [config["portable_release_tools"]]
    if require_sta:
        groups.append(config["optional_sta_tools"])
    for group in groups:
        for tool in group:
            name = str(tool["name"])
            minimum = str(tool.get("minimum_version", ""))
            if "python_module" in tool:
                module = str(tool["python_module"])
                try:
                    distribution = importlib.metadata.distribution(module)
                    actual = distribution.version
                except importlib.metadata.PackageNotFoundError:
                    errors.append(f"missing Python module: {module}")
                    continue
                executable = f"{Path(sys.executable).name} -m {module}"
                record = next((item for item in distribution.files or [] if str(item).endswith(".dist-info/RECORD")), None)
                checksum = file_sha256(Path(distribution.locate_file(record))) if record is not None else "unavailable"
            elif name == "Python":
                executable = sys.executable
                actual = ".".join(str(part) for part in sys.version_info[:3])
                checksum = file_sha256(Path(executable).resolve())
            else:
                executable = next(
                    (path for candidate in tool["executables"] if (path := shutil.which(str(candidate)))),
                    "",
                )
                if not executable:
                    errors.append(f"missing executable for {name}: {', '.join(tool['executables'])}")
                    continue
                actual = command_version(executable)
                checksum = file_sha256(Path(executable).resolve())
            if minimum and not version_at_least(actual, minimum):
                errors.append(f"{name} version is below {minimum}: {actual}")
            print(f"[KDLINK TOOL] {name}: {actual} sha256={checksum} ({executable})")


def check_tool_provenance(config: dict[str, object], errors: list[str]) -> None:
    required = {"validated_version", "validated_sha256", "source", "license", "acquisition_method"}
    for group_name in ("portable_release_tools", "optional_sta_tools"):
        for tool in config[group_name]:
            missing = sorted(required - set(tool))
            if missing:
                errors.append(f"tool provenance is incomplete for {tool.get('name', 'unknown')}: {', '.join(missing)}")
            checksum = str(tool.get("validated_sha256", ""))
            if not re.fullmatch(r"[0-9a-f]{64}", checksum):
                errors.append(f"invalid validated SHA-256 for {tool.get('name', 'unknown')}")


def safe_repository_path(raw: str, errors: list[str], owner: str) -> Path | None:
    path = Path(raw)
    if path.is_absolute() or ".." in path.parts:
        errors.append(f"unsafe repository path in {owner}: {raw}")
        return None
    resolved = (ROOT / path).resolve()
    if ROOT not in (resolved, *resolved.parents):
        errors.append(f"repository path escapes root in {owner}: {raw}")
        return None
    if not resolved.exists():
        errors.append(f"missing repository dependency in {owner}: {raw}")
    return resolved


def check_manifest(errors: list[str]) -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("tests"), dict):
        errors.append("invalid KDLink simulation manifest schema")
        return
    for test_name, test in data["tests"].items():
        for raw in [*test.get("rtl", []), test.get("testbench", "")]:
            safe_repository_path(str(raw), errors, f"manifest test {test_name}")
    print(f"[KDLINK PATH] manifest tests: {len(data['tests'])}")


def check_repository_dependencies(config: dict[str, object], errors: list[str]) -> None:
    dependencies = config["repository_dependencies"]
    safe_repository_path(str(dependencies["serdes_model_root"]), errors, "toolchain manifest")
    safe_repository_path(str(dependencies["interface_liberty_root"]), errors, "toolchain manifest")
    for raw in dependencies["interface_liberty_files"]:
        safe_repository_path(str(raw), errors, "toolchain manifest")


def portable_files() -> list[Path]:
    files = [ROOT / "Makefile", ROOT / "config" / "kdlink_toolchain.json", ROOT / "scripts" / "check_kdlink_release.py"]
    for directory in ENGINEERING_ROOTS:
        for path in directory.rglob("*"):
            if not path.is_file() or "work" in path.parts or "__pycache__" in path.parts:
                continue
            if path.name == "Makefile" or path.suffix.lower() in PORTABLE_SUFFIXES:
                files.append(path)
    return sorted(set(files))


def check_host_paths(errors: list[str]) -> None:
    for path in portable_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        if HOST_PATH_PATTERN.search(text):
            errors.append(f"host-specific absolute path found: {path.relative_to(ROOT)}")


def check_engineering_names(errors: list[str]) -> None:
    for directory in ENGINEERING_ROOTS:
        for path in directory.rglob("*"):
            if not path.is_file() or "work" in path.parts or "__pycache__" in path.parts:
                continue
            if VERSIONED_ENGINEERING_NAME.search(path.name):
                errors.append(f"versioned engineering filename found: {path.relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-only", action="store_true", help="skip executable and version checks")
    parser.add_argument("--require-sta", action="store_true", help="also require the optional OpenSTA executable")
    args = parser.parse_args()
    config = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))
    errors: list[str] = []
    check_manifest(errors)
    check_repository_dependencies(config, errors)
    check_tool_provenance(config, errors)
    check_host_paths(errors)
    check_engineering_names(errors)
    if not args.repository_only:
        check_tools(config, args.require_sta, errors)
    if errors:
        for error in errors:
            print(f"[KDLINK RELEASE ERROR] {error}")
        return 1
    print("KDLINK_RELEASE_PREFLIGHT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
