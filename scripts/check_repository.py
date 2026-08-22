#!/usr/bin/env python3
"""Check consistency and scope of the OwerFlow model-to-RTL repository."""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
TEXT_SUFFIXES = {"", ".csv", ".md", ".py", ".tcl", ".txt", ".xdc", ".yaml", ".yml"}
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
    "LICENSES",
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
ALLOWED_TOP_LEVEL_DIRECTORIES = REQUIRED_TOP_LEVEL_READMES | {".git", ".github"}
ALLOWED_EVIDENCE_LEVELS = {
    "ANALYTICAL",
    "FUNCTIONAL_SIM",
    "RTL_SIM",
    "FORMAL",
    "GENERIC_SYNTH",
}


def project_files() -> list[Path]:
    return [path for path in ROOT.rglob("*") if path.is_file() and ".git" not in path.parts]


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
        if HAN_RE.search(content):
            errors.append(f"Non-English Han text found: {path.relative_to(ROOT)}")


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


def main() -> int:
    errors: list[str] = []
    check_repository_scope(errors)
    check_english_text(errors)
    readme_count, markdown_count = check_readmes(errors)
    requirement_count = check_traceability(errors)
    check_baseline(errors)

    print(
        f"READMES={readme_count} MARKDOWN={markdown_count} "
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
