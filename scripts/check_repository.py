#!/usr/bin/env python3
"""Check consistency and scope of the Overflow model-to-RTL repository."""

from __future__ import annotations

import csv
import re
import subprocess
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
ALLOWED_HAN_NAMES = {
    "刘键宇",
    "李贇潇",
    "高恩",
    "王伟林",
    "刘浩楠",
    "刘京顺",
    "秦一",
    "付国恒",
    "伍富",
    "陈宏伟",
    "李代庆",
    "苏蒙",
}
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
TEXT_SUFFIXES = {"", ".csv", ".md", ".py", ".tcl", ".txt", ".xdc", ".yaml", ".yml"}
HOST_BINDING_SUFFIXES = {
    ".bash",
    ".json",
    ".md",
    ".mk",
    ".py",
    ".sdc",
    ".sh",
    ".tcl",
    ".xdc",
    ".yaml",
    ".yml",
}
GENERATED_DIRECTORY_NAMES = {
    ".pytest_cache",
    "__pycache__",
    "build",
    "csrc",
    "dist",
    "obj_dir",
    "simv",
    "work",
}
ABSOLUTE_HOST_PATH_RE = re.compile(
    r"/(?:home|Users|opt|usr/local|mnt|workspace|data|tools|eda|proj|scratch)/"
)
WINDOWS_HOST_PATH_RE = re.compile(r"[A-Za-z]:[\\/](?:Users|tools|eda|workspace)[\\/]", re.I)
LOCAL_ENV_EXECUTABLE_RE = re.compile(r"(?:^|[\s=])\.venv/(?:bin|Scripts)/")
PLACEHOLDER_HOST_PATH_RE = re.compile(r"/absolute/" r"path(?:/|\b)", re.I)
FIXED_HOST_ENDPOINT_RE = re.compile(
    r"\b(?:local" r"host|127\.0\.0\.1|0\.0\.0\.0)\b|"
    r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])",
    re.I,
)
REQUIRED_TRACE_COLUMNS = {
    "requirement_id",
    "domain",
    "requirement",
    "owner_path",
    "verification_method",
    "evidence_level",
    "status",
}
REQUIRED_TOP_LEVEL_READMES = {
    "Library",
    "ci",
    "compiler",
    "config",
    "deployment",
    "docs",
    "drivers",
    "firmware",
    "isa",
    "models",
    "requirements",
    "rtl",
    "runtime",
    "scripts",
    "simulator",
    "specs",
    "third_party",
    "technology",
    "verification",
}
LICENSE_ONLY_DIRECTORIES = {"LICENSES"}
ALLOWED_TOP_LEVEL_DIRECTORIES = REQUIRED_TOP_LEVEL_READMES | LICENSE_ONLY_DIRECTORIES | {".git", ".github"}
ALLOWED_EVIDENCE_LEVELS = {
    "ANALYTICAL",
    "FUNCTIONAL_SIM",
    "RTL_SIM",
    "FORMAL",
    "GENERIC_SYNTH",
}


def project_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode == 0:
        return sorted(
            ROOT / relative
            for relative in result.stdout.split("\0")
            if relative and (ROOT / relative).is_file()
        )
    return sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file()
        and ".git" not in path.parts
        and not any(part in GENERATED_DIRECTORY_NAMES for part in path.relative_to(ROOT).parts)
    )


def check_repository_scope(errors: list[str]) -> None:
    for path in ROOT.iterdir():
        if path.is_dir() and path.name not in ALLOWED_TOP_LEVEL_DIRECTORIES:
            errors.append(f"Top-level directory is outside the repository boundary: {path.name}")


def check_english_text(errors: list[str]) -> None:
    for path in project_files():
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {
            ".editorconfig",
            ".gitattributes",
            ".gitignore",
            "Makefile",
        }:
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        content_without_names = content
        for allowed_name in ALLOWED_HAN_NAMES:
            content_without_names = content_without_names.replace(allowed_name, "")
        if HAN_RE.search(content_without_names):
            errors.append(f"Non-English Han text found: {path.relative_to(ROOT)}")


def check_host_bindings(errors: list[str]) -> int:
    checked = 0
    for path in project_files():
        relative = path.relative_to(ROOT)
        if any(part in GENERATED_DIRECTORY_NAMES for part in relative.parts):
            continue
        if path.name != "Makefile" and path.suffix.lower() not in HOST_BINDING_SUFFIXES:
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        checked += 1
        for line_number, line in enumerate(content.splitlines(), start=1):
            if (
                ABSOLUTE_HOST_PATH_RE.search(line)
                or WINDOWS_HOST_PATH_RE.search(line)
                or LOCAL_ENV_EXECUTABLE_RE.search(line)
                or PLACEHOLDER_HOST_PATH_RE.search(line)
            ):
                errors.append(
                    f"Host-bound absolute path: {relative}:{line_number}"
                )
            if FIXED_HOST_ENDPOINT_RE.search(line):
                errors.append(
                    f"Fixed host endpoint: {relative}:{line_number}"
                )
    return checked


def check_readmes(errors: list[str]) -> tuple[int, int]:
    markdown_files = [path for path in project_files() if path.suffix.lower() == ".md"]
    readmes = [path for path in markdown_files if path.name == "README.md"]

    for directory in sorted(REQUIRED_TOP_LEVEL_READMES):
        if not (ROOT / directory / "README.md").is_file():
            errors.append(f"First-level directory has no README.md: {directory}")

    for path in markdown_files:
        content = path.read_text(encoding="utf-8")
        for raw_target in MARKDOWN_LINK_RE.findall(content):
            if raw_target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = raw_target.split("#", 1)[0]
            if target and not (path.parent / target).resolve().exists():
                errors.append(f"Broken relative link: {path.relative_to(ROOT)} -> {raw_target}")

    return len(readmes), len(markdown_files)


def check_traceability(errors: list[str]) -> int:
    trace_path = ROOT / "requirements" / "traceability.csv"
    with trace_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    if set(reader.fieldnames or []) != REQUIRED_TRACE_COLUMNS:
        errors.append("Requirement traceability columns do not match the schema")

    requirement_ids = [row["requirement_id"] for row in rows]
    if len(requirement_ids) != len(set(requirement_ids)):
        errors.append("Requirement traceability contains duplicate IDs")

    for row in rows:
        if row["evidence_level"] not in ALLOWED_EVIDENCE_LEVELS:
            errors.append(
                f"Requirement {row['requirement_id']} uses an unsupported evidence level: "
                f"{row['evidence_level']}"
            )
        for owner in row["owner_path"].split(";"):
            if owner and not (ROOT / owner).exists():
                errors.append(f"Requirement {row['requirement_id']} has an unknown owner: {owner}")

    return len(rows)


def check_baseline(errors: list[str]) -> None:
    baseline_path = ROOT / "config" / "system_baseline.yaml"
    baseline = yaml.safe_load(baseline_path.read_text(encoding="utf-8"))

    boundary = baseline["repository_boundary"]
    if boundary["lower_boundary"] != "synthesizable_rtl":
        errors.append("The repository lower boundary must remain synthesizable_rtl")
    if boundary["external_environment"] != "behavioral_models":
        errors.append("External environments must remain behavioral_models")

    system = baseline["system"]
    expected_capacity = (
        system["logical_npu_count"] * system["logical_hbm_gbyte_per_npu"]
    )
    if expected_capacity != system["aggregate_logical_hbm_gbyte"]:
        errors.append("Logical HBM aggregate capacity is inconsistent in system_baseline.yaml")

    kdlink = baseline["kdlink"]
    expected_injection = (
        kdlink["analytical_payload_gbyte_per_second_per_port"]
        * kdlink["target_ports_per_npu"]
    )
    if expected_injection != kdlink["analytical_tx_payload_gbyte_per_second_per_npu"]:
        errors.append("KDLink analytical TX injection is inconsistent in system_baseline.yaml")
    if expected_injection != kdlink["analytical_rx_payload_gbyte_per_second_per_npu"]:
        errors.append("KDLink analytical RX injection is inconsistent in system_baseline.yaml")

    configured_evidence = set(baseline["evidence_policy"]["allowed_levels"])
    if configured_evidence != ALLOWED_EVIDENCE_LEVELS:
        errors.append("Configured evidence levels do not match the repository policy")


def check_npu_proposal(errors: list[str]) -> None:
    proposal_path = ROOT / "config" / "npu_arch_proposed.yaml"
    proposal = yaml.safe_load(proposal_path.read_text(encoding="utf-8"))
    organization = proposal["organization"]
    sram = proposal["sram"]
    hbm = proposal["hbm"]
    dma = proposal["dma"]

    pods = organization["pods_per_npu"]
    if pods != organization["pod_rows"] * organization["pod_columns"]:
        errors.append("NPU pod geometry is inconsistent in npu_arch_proposed.yaml")
    if organization["tensor_tiles_per_npu"] != pods * organization["tensor_tiles_per_pod"]:
        errors.append("NPU tensor-tile count is inconsistent in npu_arch_proposed.yaml")
    if organization["hbm_partitions_per_npu"] != pods or dma["engines_per_npu"] != pods:
        errors.append("NPU pod, HBM partition, and DMA engine counts must match")

    aggregate_gbyte_per_second = (
        organization["hbm_partitions_per_npu"]
        * hbm["target_payload_gbyte_per_second_per_partition"]
    )
    if aggregate_gbyte_per_second != hbm["target_aggregate_tbyte_per_second"] * 1000:
        errors.append("NPU aggregate HBM bandwidth is inconsistent in npu_arch_proposed.yaml")

    expected_dma_geometry = {
        "logical_channels_per_engine": 16,
        "active_descriptors_per_engine": 64,
        "data_beat_bytes": 128,
        "outstanding_data_beats_per_engine": 4096,
        "maximum_descriptor_bytes": 16777216,
        "qos_classes": 4,
    }
    for field, expected in expected_dma_geometry.items():
        if dma[field] != expected:
            errors.append(f"NPU DMA v0.1 geometry mismatch for {field}: expected {expected}")

    expected_sram_geometry = {
        "pod_shared_mib": 16,
        "pod_shared_bank_count": 8,
        "pod_shared_bank_width_bits": 1024,
        "pod_shared_physical_macro_count": 256,
    }
    for field, expected in expected_sram_geometry.items():
        if sram[field] != expected:
            errors.append(f"NPU Pod SRAM v0.1 geometry mismatch for {field}: expected {expected}")
    if sram["pod_shared_geometry_contract"] != "specs/interfaces/npu_pod_shared_sram.md":
        errors.append("NPU Pod SRAM geometry contract path is inconsistent")


def main() -> int:
    errors: list[str] = []
    check_repository_scope(errors)
    check_english_text(errors)
    host_binding_count = check_host_bindings(errors)
    readme_count, markdown_count = check_readmes(errors)
    requirement_count = check_traceability(errors)
    check_baseline(errors)
    check_npu_proposal(errors)

    print(
        f"READMES={readme_count} MARKDOWN={markdown_count} HOST_FILES={host_binding_count} "
        f"REQUIREMENTS={requirement_count}"
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1

    print("REPOSITORY_GATE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
