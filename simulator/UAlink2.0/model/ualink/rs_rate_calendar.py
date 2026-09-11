"""UALink DL/PL2.0 §3.3.5–3.3.7 / table3-5 transmitted-codeword calendar.

This independent RS reference applies to DL up and DL NOP. The ordinal is relative
to the common alignment-marker epoch; it does not count local/UPLI clock edges.
The caller supplies the established steady normal or rapid-marker mode. Power-up
RAM countdown, mode transitions, wire encoding, FEC and Rx edits are separate.

Run: python3 -m unittest verification.model.test_rs_rate_calendar -v
Output: normative calendar checks. Next: actual RS commit/state integration.
"""

_AM_PERIODS = {
    (100, 1): 4096,
    (100, 2): 4096,
    (100, 4): 8192,
    (200, 1): 4096,
    (200, 2): 8192,
    (200, 4): 16384,
}


def tx_codeword_kind(serial_gbps, lanes, codeword_index, *, rapid_alignment=False):
    """Return the RS event for one transmitted codeword in the given AM epoch.

    ``dl_flit`` leaves payload versus NOP selection to the DL. Alignment slots
    replace a rate-matching Idle slot; steady RAM mode adds no separate Idles.
    """
    if type(serial_gbps) is not int or type(lanes) is not int:
        raise ValueError('serial_gbps and lanes must be integer profile values')
    if (serial_gbps, lanes) not in _AM_PERIODS:
        raise ValueError('supported profiles: 100/200 Gb/s serial, 1/2/4 lanes')
    if type(codeword_index) is not int or codeword_index < 0:
        raise ValueError('codeword_index must be a nonnegative transmitted-codeword ordinal')
    if type(rapid_alignment) is not bool:
        raise ValueError('rapid_alignment must explicitly be True or False')
    period = _AM_PERIODS[serial_gbps, lanes]
    if rapid_alignment:
        return 'rapid_alignment_marker' if codeword_index % (period // 128) == 0 else 'dl_flit'
    if codeword_index % period == 0:
        return 'alignment_marker'
    if codeword_index % 1024 == 0:
        return 'rate_idle'
    return 'dl_flit'
