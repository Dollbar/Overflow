import pytest

from kdlink_model.bonding import BondedPortDistributor, BondedPortReorder


def test_dual_slice_round_robin_and_degraded_mode() -> None:
    distributor = BondedPortDistributor()
    assert [distributor.assign(seq) for seq in range(6)] == [0, 1, 0, 1, 0, 1]
    distributor.disable(1)
    assert [distributor.assign(seq) for seq in range(6, 10)] == [0, 0, 0, 0]
    distributor.disable(0)
    with pytest.raises(RuntimeError, match="no active slice"):
        distributor.assign(10)


def test_out_of_order_dual_slice_receive_releases_in_order() -> None:
    reorder = BondedPortReorder()
    assert reorder.accept(1, b"one") == []
    assert reorder.accept(3, b"three") == []
    assert reorder.accept(0, b"zero") == [(0, b"zero"), (1, b"one")]
    assert reorder.accept(2, b"two") == [(2, b"two"), (3, b"three")]


def test_reorder_detects_duplicate_and_stale_packets() -> None:
    reorder = BondedPortReorder()
    reorder.accept(1, b"one")
    with pytest.raises(RuntimeError, match="duplicate"):
        reorder.accept(1, b"duplicate")
    with pytest.raises(RuntimeError, match="stale"):
        reorder.accept(4095, b"stale")
