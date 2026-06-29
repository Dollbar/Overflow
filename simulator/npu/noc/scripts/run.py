#!/usr/bin/env python3
"""Run the portable NPU NoC analytical and route-contract checks."""

from __future__ import annotations

import json
import pathlib
import sys


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
MODEL_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(MODEL_DIR))

import model  # noqa: E402


def main() -> int:
    """Validate every route and print the checked analytical summary."""

    legal_links = model.directed_links()
    routes_checked = 0
    maximum_hops = 0
    for source in range(model.PODS):
        for destination in range(model.PODS):
            route = model.route_xy(source, destination)
            links = model.route_links(source, destination)
            if route[0] != source or route[-1] != destination:
                raise RuntimeError("route endpoint mismatch")
            if len(set(route)) != len(route):
                raise RuntimeError("deterministic route contains a cycle")
            if any(link not in legal_links for link in links):
                raise RuntimeError("deterministic route uses an illegal link")
            maximum_hops = max(maximum_hops, len(links))
            if source != destination:
                routes_checked += 1

    if len(legal_links) != 20 or routes_checked != 56 or maximum_hops != 4:
        raise RuntimeError("fixed Mesh geometry mismatch")

    summary = model.analytical_payload_rates()
    expected = {
        "data_lane_gbytes_per_second": 256.0,
        "directed_edge_gbytes_per_second": 512.0,
        "middle_bisection_gbytes_per_second": 1024.0,
        "control_gbytes_per_second": 32.0,
        "maximum_data_packet_bytes": 4096,
        "maximum_nonlocal_hbm_gbytes_per_second": 1000.0,
    }
    if summary != expected:
        raise RuntimeError(f"analytical summary mismatch: {summary}")

    print(json.dumps({
        "evidence": "ANALYTICAL",
        "directed_links": len(legal_links),
        "directed_routes": routes_checked,
        "maximum_hops": maximum_hops,
        **summary,
    }, sort_keys=True))
    print("NPU_NOC_MODEL_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
