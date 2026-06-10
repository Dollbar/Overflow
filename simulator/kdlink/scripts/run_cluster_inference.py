#!/usr/bin/env python3
"""Run compressed KDLink cluster-inference traffic simulation."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODEL_ROOT = ROOT / "simulator" / "kdlink" / "model"
sys.path.insert(0, str(MODEL_ROOT))

from kdlink_model.cluster_simulator import evaluate_serving, simulate_inference  # noqa: E402
from kdlink_model.inference_workload import InferenceWorkload  # noqa: E402
from kdlink_model.network_resources import NetworkSimulationPolicy  # noqa: E402
from kdlink_model.simulation_metrics import (  # noqa: E402
    render_simulation_summary,
    render_serving_summary,
    serving_result_dict,
    simulation_result_dict,
)


def _integer_vector(value: str, length: int) -> tuple[int, ...]:
    try:
        parsed = tuple(int(item) for item in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("vector values must be integers") from error
    if len(parsed) != length:
        raise argparse.ArgumentTypeError(f"vector must contain {length} values")
    return parsed


def _float_vector(value: str, length: int) -> tuple[float, ...]:
    try:
        parsed = tuple(float(item) for item in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("vector values must be numeric") from error
    if len(parsed) != length:
        raise argparse.ArgumentTypeError(f"vector must contain {length} values")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="repository inference simulation JSON")
    parser.add_argument("--profile", choices=("nonblocking", "balanced"))
    parser.add_argument("--active-planes", type=int)
    parser.add_argument("--active-slices", type=int)
    parser.add_argument(
        "--planes-by-tier",
        type=lambda value: _integer_vector(value, 6),
        help="leaf,T1,T2,T3,T4,T5 active plane counts",
    )
    parser.add_argument(
        "--slices-by-tier",
        type=lambda value: _integer_vector(value, 6),
        help="leaf,T1,T2,T3,T4,T5 active slice counts",
    )
    parser.add_argument(
        "--oversubscription-by-tier",
        type=lambda value: _float_vector(value, 5),
        help="T1,T2,T3,T4,T5 oversubscription ratios",
    )
    parser.add_argument("--requests", type=int, help="run FCFS serving evaluation")
    parser.add_argument("--arrival-interval-us", type=float)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--output", type=Path, help="also write the selected report format")
    return parser.parse_args()


def load_config(
    path: Path,
) -> tuple[InferenceWorkload, NetworkSimulationPolicy, dict]:
    resolved = path if path.is_absolute() else ROOT / path
    values = json.loads(resolved.read_text(encoding="utf-8"))
    if values.get("schema_version") != 1:
        raise SystemExit("inference simulation config must use schema version one")
    if not values.get("planning_example_only", False):
        raise SystemExit("inference config must explicitly declare planning_example_only")
    return (
        InferenceWorkload.from_dict(values["workload"]),
        NetworkSimulationPolicy.from_dict(values["network"]),
        dict(values.get("serving", {})),
    )


def main() -> None:
    args = parse_args()
    workload, policy, serving = load_config(args.config)
    replacements = {}
    if args.profile is not None:
        replacements["profile"] = args.profile
    if args.active_planes is not None:
        replacements["active_planes"] = args.active_planes
        replacements["active_planes_by_tier"] = None
    if args.active_slices is not None:
        replacements["active_slices_per_port"] = args.active_slices
        replacements["active_slices_by_tier"] = None
    if args.planes_by_tier is not None:
        replacements["active_planes_by_tier"] = args.planes_by_tier
    if args.slices_by_tier is not None:
        replacements["active_slices_by_tier"] = args.slices_by_tier
    if args.oversubscription_by_tier is not None:
        replacements["oversubscription_by_tier"] = args.oversubscription_by_tier
    if replacements:
        policy = replace(policy, **replacements)
    request_count = args.requests if args.requests is not None else serving.get("request_count", 1)
    arrival_interval = (
        args.arrival_interval_us
        if args.arrival_interval_us is not None
        else serving.get("arrival_interval_microseconds", 0.0)
    )
    serving_mode = args.requests is not None or request_count > 1
    if serving_mode:
        result = evaluate_serving(
            workload,
            policy,
            request_count=request_count,
            arrival_interval_microseconds=arrival_interval,
        )
        selected_dict = serving_result_dict
        selected_renderer = render_serving_summary
    else:
        result = simulate_inference(workload, policy)
        selected_dict = simulation_result_dict
        selected_renderer = render_simulation_summary
    if args.json:
        report = json.dumps(selected_dict(result), indent=2, sort_keys=True)
    else:
        report = selected_renderer(result)
    print(report)
    if args.output is not None:
        output = args.output if args.output.is_absolute() else ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(report + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
