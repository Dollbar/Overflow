#!/usr/bin/env python3
"""Report the analytical KDLink hierarchy bandwidth contract for one deployment."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODEL_ROOT = ROOT / "simulator" / "kdlink" / "model"
sys.path.insert(0, str(MODEL_ROOT))

from kdlink_model.bandwidth import (  # noqa: E402
    BALANCED_OVERSUBSCRIPTION,
    NONBLOCKING_OVERSUBSCRIPTION,
    REFERENCE_RTT_CYCLES,
    BandwidthTrafficDemand,
    plan_hierarchical_bandwidth,
    reference_tier_policies,
)


def comma_separated_integers(value: str) -> tuple[int, ...]:
    try:
        parsed = tuple(int(item) for item in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("RTT cycles must be comma-separated integers") from error
    if len(parsed) != 5:
        raise argparse.ArgumentTypeError("RTT cycles must contain five tiers")
    return parsed


def comma_separated_floats(value: str) -> tuple[float, ...]:
    try:
        parsed = tuple(float(item) for item in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("tier values must be comma-separated numbers") from error
    if len(parsed) != 5:
        raise argparse.ArgumentTypeError("tier values must contain five tiers")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("total_npus", type=int)
    parser.add_argument("--profile", choices=("nonblocking", "balanced"), default="nonblocking")
    parser.add_argument("--active-planes", type=int, default=8)
    parser.add_argument("--active-slices", type=int, default=2)
    parser.add_argument("--cross-tier-fraction", type=float, default=1.0)
    parser.add_argument("--reduction-factor", type=float, default=1.0)
    parser.add_argument("--cross-tier-fractions", type=comma_separated_floats)
    parser.add_argument("--reduction-factors", type=comma_separated_floats)
    parser.add_argument("--rtt-cycles", type=comma_separated_integers, default=REFERENCE_RTT_CYCLES)
    parser.add_argument("--json", action="store_true", help="emit the complete plan as JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    oversubscription = (
        NONBLOCKING_OVERSUBSCRIPTION
        if args.profile == "nonblocking"
        else BALANCED_OVERSUBSCRIPTION
    )
    tier_fractions = args.cross_tier_fractions or (args.cross_tier_fraction,) * 5
    tier_reductions = args.reduction_factors or (args.reduction_factor,) * 5
    tier_demands = tuple(
        BandwidthTrafficDemand(
            f"caller_defined_tier_{index + 1}",
            cross_tier_fraction=fraction,
            reduction_factor=reduction,
        )
        for index, (fraction, reduction) in enumerate(
            zip(tier_fractions, tier_reductions, strict=True)
        )
    )
    plan = plan_hierarchical_bandwidth(
        args.total_npus,
        policies=reference_tier_policies(
            oversubscription,
            rtt_cycles=args.rtt_cycles,
        ),
        traffic_demand=tier_demands,
        active_planes=args.active_planes,
        active_slices_per_port=args.active_slices,
    )
    if args.json:
        print(json.dumps(asdict(plan), indent=2, sort_keys=True))
        return 0
    print(
        "tier leaves/group npus/group groups cross_fraction reduction link_GBps "
        "offered_GBps/plane required_GBps/plane required_links installed_links "
        "rtt_cycles bdp_bytes/link"
    )
    for tier in plan.tiers:
        print(
            f"{tier.tier_index:>4} "
            f"{tier.covered_leaf_domains_per_group:>12} "
            f"{tier.covered_npus_per_group:>10} "
            f"{tier.group_count:>6} "
            f"{tier.cross_tier_fraction:>14.4f} "
            f"{tier.reduction_factor:>9.4f} "
            f"{tier.payload_gbyte_s_per_link_per_direction:>9.1f} "
            f"{tier.offered_gbyte_s_per_plane_per_group:>19.1f} "
            f"{tier.required_gbyte_s_per_plane_per_group:>20.1f} "
            f"{tier.required_link_equivalents_per_plane_per_group:>14} "
            f"{tier.installed_link_equivalents_per_plane_per_group:>15} "
            f"{tier.round_trip_cycles:>10} "
            f"{tier.bdp_bytes_per_link:>14}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
