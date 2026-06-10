import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).parents[4]
SCRIPT = ROOT / "simulator" / "kdlink" / "scripts" / "run_cluster_inference.py"
CONFIG = ROOT / "simulator" / "kdlink" / "config" / "inference_serving.json"


def test_serving_cli_emits_machine_readable_tail_metrics() -> None:
    completed = subprocess.run(
        [sys.executable, str(SCRIPT), str(CONFIG), "--json"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    values = json.loads(completed.stdout)
    assert values["scheduling_model"] == "FCFS_CLUSTER_BATCH"
    assert values["request_count"] == 16
    assert values["latency_p99_microseconds"] >= values["latency_p50_microseconds"]
    assert values["cluster_generated_tokens_per_second"] > 0.0


def test_cli_per_tier_slice_override_changes_only_leaf_resource() -> None:
    completed = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            str(CONFIG),
            "--requests",
            "1",
            "--slices-by-tier",
            "2,1,1,1,1,1",
            "--json",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    values = json.loads(completed.stdout)
    assert values["tier_metrics"][0]["active_slices_per_port"] == 2
    assert all(
        tier["active_slices_per_port"] == 1
        for tier in values["tier_metrics"][1:]
    )
