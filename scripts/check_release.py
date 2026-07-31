#!/usr/bin/env python3
"""Audit the Overflow source tree for a formal public release."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
STABLE_NAME_RE = re.compile(
    r"(?:^|[/_.-])v(?:0|[1-9][0-9]*)(?:[._-][0-9]+)?(?=[/_.-]|$)", re.I
)
FORBIDDEN_PARTS = {".pytest_cache", "__pycache__", "build", "csrc", "obj_dir", "work"}
FORBIDDEN_SUFFIXES = {
    ".a", ".bit", ".dcp", ".dll", ".elf", ".fsdb", ".o", ".p12", ".pem",
    ".pfx", ".so", ".vcd", ".wdb", ".zip",
}
SECRET_PATTERNS = {
    "private_key": re.compile(r"BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY"),
    "aws_access_key": re.compile(r"AKIA[0-9A-Z]{16}"),
    "github_token": re.compile(r"(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{20,})"),
    "slack_token": re.compile(r"xox[baprs]-[A-Za-z0-9-]+"),
}
LEGACY_PROJECT_SPELLING = "Ower" + "Flow"
REQUIRED_DEPENDENCY_FIELDS = {
    "name", "version", "source", "license", "checksum", "checksum_subject",
    "redistributed", "acquisition_method", "replacement_strategy",
}
REQUIRED_RELEASE_FILES = {
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "GOVERNANCE.md",
    "docs/management/licensing.md",
    "README.md",
    "SECURITY.md",
    "config/release.yaml",
    "config/contributors.yaml",
    "config/history_reconstruction.yaml",
    "docs/management/history_reconstruction.md",
    "docs/management/history_reconstruction_map.tsv",
    "docs/planning/release_scope.md",
    "docs/releases/ACCEPTANCE.json",
    "docs/releases/README.md",
    "docs/releases/RELEASE_NOTES.md",
    "docs/releases/UPLOAD_MANIFEST.md",
    "requirements/traceability.csv",
    "requirements-build.lock",
    "requirements-dev.lock",
    "third_party/dependencies.yaml",
}
ATTESTATION_ONLY_FILES = {
    "config/release.yaml",
    "docs/releases/ACCEPTANCE.json",
}
REQUIRED_LICENSE_FILES = {
    "LICENSES/Apache-2.0.txt": "1f83bfbb6ab612d244b9619bcf615e54c2e107fc78a05eb6e16bc1ce41fd2f8f",
    "LICENSES/CC-BY-4.0.txt": "7f38c38147b1b5e3fc5788e34104c965873b60bbf639c52392a85297810ebcbe",
    "LICENSES/GPL-2.0-only.txt": "d29dbcc178acaf8370a7f861f30ae9ebec8e96c0177d2205280a96ae0e0b5d46",
    "LICENSES/SHL-2.1.txt": "bab79b6677dd5b646559bdd6dd0948f2caf678b4b6eb10290c1a6b72e70e0c34",
}


def git_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    return result.stdout.splitlines()


def read_text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def add(bucket: list[str], message: str) -> None:
    if message not in bucket:
        bucket.append(message)


def sha256(relative: str) -> str:
    digest = hashlib.sha256()
    with (ROOT / relative).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def check_structure(files: list[str], errors: list[str]) -> None:
    missing = sorted(REQUIRED_RELEASE_FILES - set(files))
    for relative in missing:
        add(errors, f"missing release file: {relative}")

    for relative in files:
        parts = Path(relative).parts
        if STABLE_NAME_RE.search(relative):
            add(errors, f"version token in engineering file name: {relative}")
        if any(part in FORBIDDEN_PARTS for part in parts):
            add(errors, f"generated directory is tracked: {relative}")
        if Path(relative).suffix.lower() in FORBIDDEN_SUFFIXES:
            add(errors, f"binary or generated artifact is tracked: {relative}")


def check_content(files: list[str], errors: list[str]) -> None:
    for relative in files:
        path = ROOT / relative
        try:
            content = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if LEGACY_PROJECT_SPELLING in content:
            add(errors, f"legacy project spelling remains: {relative}")
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(content):
                add(errors, f"possible {label} in tracked file: {relative}")


def check_dependencies(errors: list[str]) -> None:
    manifest = yaml.safe_load(read_text("third_party/dependencies.yaml"))
    declared_versions: dict[str, str] = {}
    declared_hashes: dict[str, str] = {}
    for section in ("dependencies", "optional_dependencies", "external_nonredistributable_inputs"):
        entries = manifest.get(section, [])
        if not isinstance(entries, list) or not entries:
            add(errors, f"dependency manifest section is empty: {section}")
            continue
        for index, entry in enumerate(entries):
            missing = REQUIRED_DEPENDENCY_FIELDS - set(entry)
            if missing:
                add(errors, f"{section}[{index}] missing fields: {','.join(sorted(missing))}")
            if not missing:
                for field in REQUIRED_DEPENDENCY_FIELDS:
                    if entry[field] is None or str(entry[field]).strip() == "":
                        add(errors, f"{section}[{index}] has an empty field: {field}")
                if section == "dependencies":
                    dependency_name = str(entry["name"]).lower()
                    declared_versions[dependency_name] = str(entry["version"])
                    declared_hashes[dependency_name] = str(entry["checksum"])

    requirements = read_text("requirements-dev.txt").splitlines()
    for line_number, raw_line in enumerate(requirements, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([^;\s]+)", line)
        if not match:
            add(errors, f"requirements-dev.txt:{line_number} is not exactly pinned")
            continue
        name, version = match.groups()
        declared = declared_versions.get(name.lower())
        if declared is None:
            add(errors, f"pinned Python dependency is absent from manifest: {name}")
        elif declared != version:
            add(
                errors,
                f"dependency version disagrees for {name}: requirements={version} manifest={declared}",
            )

    lock_content = read_text("requirements-dev.lock")
    for name, version in sorted(declared_versions.items()):
        if name in {
            "python", "pip", "git", "verilator", "verilator_coverage", "yosys",
            "icarus verilog", "icarus verilog runtime", "opensta", "gnu make",
            "gcc c++ compiler",
        }:
            continue
        pin = re.compile(rf"(?mi)^{re.escape(name)}=={re.escape(version)}\s*\\\s*$")
        if not pin.search(lock_content):
            add(errors, f"release lock is missing dependency pin: {name}=={version}")
    lock_pins = re.findall(r"(?mi)^([A-Za-z0-9_.-]+)==([^\s\\]+)\s*\\\s*$", lock_content)
    for name, version in lock_pins:
        block = re.search(
            rf"(?mis)^{re.escape(name)}=={re.escape(version)}\s*\\\s*\n(.*?)(?=^[A-Za-z0-9_.-]+==|\Z)",
            lock_content,
        )
        if block is None or "--hash=sha256:" not in block.group(1):
            add(errors, f"release lock pin has no SHA-256: {name}=={version}")
            continue
        manifest_hash = declared_hashes.get(name.lower())
        if manifest_hash is None:
            add(errors, f"release lock contains an undeclared dependency: {name}")
        elif f"--hash=sha256:{manifest_hash}" not in block.group(1):
            add(errors, f"release lock hash disagrees with manifest: {name}=={version}")

    build_lock_content = read_text("requirements-build.lock")
    poetry_version = declared_versions.get("poetry-core")
    poetry_hash = declared_hashes.get("poetry-core")
    if poetry_version is None or poetry_hash is None:
        add(errors, "dependency manifest is missing the poetry-core build backend")
    else:
        expected_build_pin = f"poetry-core=={poetry_version} \\\n    --hash=sha256:{poetry_hash}"
        if expected_build_pin not in build_lock_content:
            add(errors, "requirements-build.lock does not pin the declared poetry-core artifact")


def check_requirements(release: dict, errors: list[str]) -> None:
    with (ROOT / "requirements" / "traceability.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        rows = list(csv.DictReader(handle))
    allowed = set(release["requirements"]["admissible_states"])
    nonclaims = set(release["requirements"]["nonclaim_requirement_ids"])
    known_ids = {row["requirement_id"] for row in rows}
    for row in rows:
        if row["status"] not in allowed and row["requirement_id"] not in nonclaims:
            add(
                errors,
                f"non-admissible requirement is not an explicit non-claim: {row['requirement_id']}",
            )
    for requirement_id in sorted(nonclaims - known_ids):
        add(errors, f"unknown release non-claim requirement: {requirement_id}")


def check_contributors(release: dict, errors: list[str], holds: list[str]) -> None:
    roster = yaml.safe_load(read_text("config/contributors.yaml"))
    contributors = roster.get("contributors", [])
    if roster.get("schema_version") != 1 or not isinstance(contributors, list):
        add(errors, "contributor roster schema is invalid")
        return
    if len(contributors) != 12:
        add(errors, f"contributor roster must contain 12 confirmed people, found {len(contributors)}")
    ids = [str(item.get("id", "")) for item in contributors]
    names = [str(item.get("name", "")) for item in contributors]
    emails = [str(item.get("email", "")) for item in contributors]
    for label, values in (("id", ids), ("name", names), ("email", emails)):
        if any(not value for value in values) or len(values) != len(set(values)):
            add(errors, f"contributor roster has missing or duplicate {label} values")
    for item in contributors:
        email = str(item.get("email", ""))
        if re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email) is None:
            add(errors, f"invalid contributor email: {email}")
        period = item.get("development_period", {})
        if not period.get("start") or not period.get("end"):
            add(errors, f"contributor has incomplete development period: {item.get('id')}")
        if not item.get("responsibilities"):
            add(errors, f"contributor has no responsibility record: {item.get('id')}")
    holder = roster.get("copyright", {}).get("holder")
    if holder != release.get("licensing", {}).get("copyright_holder"):
        add(errors, "contributor roster and release copyright holders disagree")
    integration = roster.get("integration", {})
    if integration.get("target_remote") != "github" or integration.get("target_branch") != "main":
        add(errors, "history reconstruction target is not github/main")
    if integration.get("committer_email") != "liujianyu20021122@gmail.com":
        add(errors, "history reconstruction committer email is not owner-confirmed")

    history = yaml.safe_load(read_text("config/history_reconstruction.yaml"))
    patches = history.get("patches", [])
    date_entries = history.get("dates", {}).get("entries", [])
    if len(patches) != 44 or len(date_entries) != 44:
        add(errors, "history reconstruction must contain 44 patch and date entries")
    patch_sources = [str(item.get("source", "")) for item in patches]
    date_sources = [str(item.get("source", "")) for item in date_entries]
    if patch_sources != date_sources or len(set(patch_sources)) != len(patch_sources):
        add(errors, "history patch and date source order is inconsistent or duplicated")
    known_ids = set(ids)
    people = {str(item.get("id")): item for item in contributors}
    previous_committer = None
    previous_author: dict[str, datetime] = {}
    for patch, dated in zip(patches, date_entries):
        source = str(patch.get("source", ""))
        if re.fullmatch(r"[0-9a-f]{40}", source) is None:
            add(errors, f"history source is not a full Git ID: {source}")
        author_id = str(patch.get("author", ""))
        coauthors = patch.get("coauthors", [])
        if author_id not in known_ids or not isinstance(coauthors, list):
            add(errors, f"history attribution is invalid: {source}")
            continue
        if author_id in coauthors or not set(coauthors) <= known_ids:
            add(errors, f"history co-author attribution is invalid: {source}")
        try:
            author_date = datetime.fromisoformat(str(dated.get("author_date", "")))
            committer_date = datetime.fromisoformat(str(dated.get("committer_date", "")))
        except ValueError:
            add(errors, f"history timestamp is invalid: {source}")
            continue
        period = people[author_id]["development_period"]
        if not period["start"] <= author_date.date() <= period["end"]:
            add(errors, f"history author date is outside the confirmed period: {source}")
        if author_date >= committer_date:
            add(errors, f"history author date is not before committer date: {source}")
        if previous_committer is not None and committer_date <= previous_committer:
            add(errors, f"history committer dates are not strictly increasing: {source}")
        if author_id in previous_author and author_date <= previous_author[author_id]:
            add(errors, f"history author dates are not increasing for {author_id}: {source}")
        previous_committer = committer_date
        previous_author[author_id] = author_date

    with (ROOT / "docs" / "management" / "history_reconstruction_map.tsv").open(
        newline="", encoding="utf-8"
    ) as handle:
        mapping = list(csv.DictReader(handle, delimiter="\t"))
    if len(mapping) != 44:
        add(errors, f"history reconstruction map must contain 44 rows, found {len(mapping)}")
    mapped_sources = [row.get("source_commit", "") for row in mapping]
    rewritten = [row.get("rewritten_commit", "") for row in mapping]
    if mapped_sources != patch_sources:
        add(errors, "history reconstruction map order disagrees with the patch plan")
    if any(re.fullmatch(r"[0-9a-f]{40}", value) is None for value in rewritten):
        add(errors, "history reconstruction map contains an invalid rewritten Git ID")
    preview = history.get("preview_result", {})
    if preview.get("status") != "PASS" or preview.get("commit_count") != 44:
        add(errors, "history reconstruction preview result is incomplete")
    if rewritten and preview.get("rewritten_tip") != rewritten[-1]:
        add(errors, "history reconstruction preview tip disagrees with the mapping")
    if preview.get("source_tree") != preview.get("rewritten_tree"):
        add(errors, "history reconstruction preview tree comparison is not identical")
    if integration.get("material_merge_resolution_source") != next(
        (item.get("source") for item in patches if item.get("kind") == "reconstructed_merge_resolution"),
        None,
    ):
        add(errors, "material merge-resolution source disagrees across history records")
    if integration.get("history_status") != "RECONSTRUCTED_AND_VERIFIED":
        add(holds, "owner-approved contributor history reconstruction is not complete")


def check_acceptance(release: dict, errors: list[str], holds: list[str]) -> None:
    acceptance = json.loads(read_text("docs/releases/ACCEPTANCE.json"))
    version = release["release"]["version"]
    if acceptance.get("release_version") != version:
        add(errors, "acceptance report and release configuration versions disagree")
    if acceptance.get("publication_status") != release["release"]["publication_status"]:
        add(errors, "acceptance report and release configuration statuses disagree")
    accepted_payload = acceptance.get("candidate_source", {}).get("immutable_payload_commit")
    if accepted_payload != release["release"].get("source_commit"):
        add(errors, "acceptance report and release configuration payload commits disagree")
    if acceptance.get("publication_status") != "GO":
        add(holds, "machine-readable acceptance report is not GO")
    for item in acceptance.get("blocking_items", []):
        if item.get("status") != "RESOLVED":
            add(holds, f"acceptance blocking item remains: {item.get('id', 'UNKNOWN')}")


def check_licensing(
    release: dict, files: list[str], errors: list[str], holds: list[str]
) -> None:
    licensing = release["licensing"]
    if licensing.get("decision_status") != "APPROVED":
        add(holds, "license matrix needs repository-owner approval")
    if not licensing.get("copyright_holder"):
        add(holds, "copyright holder is not recorded")
    for field in (
        "software_spdx_expression", "rtl_spdx_expression",
        "documentation_spdx_expression", "driver_spdx_expression",
    ):
        if not licensing.get(field):
            add(holds, f"license selection is missing: {field}")
    if licensing.get("reuse_metadata") != "REUSE.toml" or "REUSE.toml" not in files:
        add(holds, "REUSE path-level copyright and license metadata is missing")
    for relative, expected_hash in REQUIRED_LICENSE_FILES.items():
        if relative not in files:
            add(holds, f"selected full license text is missing: {relative}")
        elif sha256(relative) != expected_hash:
            add(errors, f"official license text checksum mismatch: {relative}")

    reuse_executable = shutil.which("reuse")
    if reuse_executable is None:
        add(holds, "REUSE CLI is unavailable; install the locked release environment")
    else:
        result = subprocess.run(
            [reuse_executable, "lint"], cwd=ROOT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
        )
        if result.returncode != 0:
            summary = next(
                (line.strip() for line in result.stdout.splitlines() if line.strip()),
                "no diagnostic output",
            )
            add(errors, f"REUSE lint failed: {summary}")


def check_git_state(release: dict, errors: list[str], holds: list[str]) -> None:
    status = subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, check=True, text=True,
        stdout=subprocess.PIPE,
    ).stdout
    if status:
        add(holds, "release worktree is not clean")
    source_commit = release["release"].get("source_commit")
    if not source_commit:
        add(holds, "immutable release payload commit is not recorded")
    else:
        if not re.fullmatch(r"[0-9a-f]{40}", str(source_commit)):
            add(errors, "release payload commit must be a full 40-character lowercase Git ID")
            return
        parent_count = subprocess.run(
            ["git", "rev-list", "--parents", "-n", "1", "HEAD"],
            cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE,
        ).stdout.split()
        if len(parent_count) != 2:
            add(errors, "release attestation commit must have exactly one parent")
            return
        parent = subprocess.run(
            ["git", "rev-parse", "HEAD^"], cwd=ROOT, check=True, text=True,
            stdout=subprocess.PIPE,
        ).stdout.strip()
        if source_commit != parent:
            add(holds, "recorded payload commit does not match the attestation parent")
        changed = subprocess.run(
            ["git", "diff", "--name-only", "HEAD^", "HEAD"],
            cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE,
        ).stdout.splitlines()
        unexpected = sorted(set(changed) - ATTESTATION_ONLY_FILES)
        for relative in unexpected:
            add(errors, f"non-attestation file changed after payload regression: {relative}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="treat every HOLD as a failure")
    args = parser.parse_args()

    errors: list[str] = []
    holds: list[str] = []
    files = git_files()
    release = yaml.safe_load(read_text("config/release.yaml"))

    check_structure(files, errors)
    check_content(files, errors)
    check_dependencies(errors)
    check_requirements(release, errors)
    check_contributors(release, errors, holds)
    check_acceptance(release, errors, holds)
    check_licensing(release, files, errors, holds)
    check_git_state(release, errors, holds)

    print(f"RELEASE_FILES={len(files)} ERRORS={len(errors)} HOLDS={len(holds)}")
    for message in errors:
        print(f"ERROR: {message}")
    for message in holds:
        print(f"HOLD: {message}")
    if errors:
        print("RELEASE_AUDIT_FAIL")
        return 1
    if holds:
        print("RELEASE_AUDIT_PASS_WITH_HOLDS")
        return 2 if args.strict else 0
    print("RELEASE_GATE_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
