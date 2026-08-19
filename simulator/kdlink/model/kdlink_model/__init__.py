"""Executable KDLink-v2 protocol, bonding, topology, PCS, and performance model."""

from .bonding import BondedPortDistributor, BondedPortReorder
from .performance import FabricPerformance, fabric_performance
from .protocol import KDLinkFlit, KDLinkHeader, KDLinkReverseWord
from .topology import FabricRoute, route_direct
from .chassis import ChassisTopology, EndpointLocation, LinkState, SliceLink

__all__ = [
    "BondedPortDistributor",
    "BondedPortReorder",
    "FabricPerformance",
    "FabricRoute",
    "KDLinkFlit",
    "KDLinkHeader",
    "KDLinkReverseWord",
    "fabric_performance",
    "route_direct",
]
