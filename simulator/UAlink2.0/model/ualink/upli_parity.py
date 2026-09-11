"""Common 2.0 Table 2-21/3.1.1 UPLI parity subset, not Switch Core RAS."""


def _word(value, width):
    if type(width) is not int or type(value) is not int:
        raise TypeError("parity inputs and widths must be integers, not booleans")
    if width < 1 or not 0 <= value < (1 << width):
        raise ValueError("parity word is outside its explicit unsigned width")
    return value


def even_parity(value: int, width: int) -> int:
    """Parity bit which makes the protected word plus parity contain even ones."""
    value = _word(value, width)
    result = 0
    while value:
        result ^= value & 1
        value >>= 1
    return result


def check_orig_data(valid, data, byte_en, fields, valid_parity, data_parity, byte_en_parity, fields_parity):
    """Check 512-bit data/64-bit enables/9-bit packed controls; see contract.

    Packed controls: Last[0], Error[1], Offset[3:2], PortID[5:4], VC[7:6],
    Pool[8]. Returned names are local diagnostic labels, not protocol codes.
    """
    if type(valid) is not bool:
        raise TypeError("valid must be a boolean")
    errors = set()
    if int(valid) != _word(valid_parity, 1):
        errors.add("valid")
    if not valid:
        return frozenset(errors)
    _word(data, 512)
    _word(data_parity, 8)
    for group in range(8):
        protected = (data >> (64 * group)) & ((1 << 64) - 1)
        if even_parity(protected, 64) != ((data_parity >> group) & 1):
            errors.add("data" + str(group))
    if even_parity(byte_en, 64) != _word(byte_en_parity, 1):
        errors.add("byte_enable")
    if even_parity(fields, 9) != _word(fields_parity, 1):
        errors.add("control")
    return frozenset(errors)


def check_credit(valid_mask, vcs, nums, pool_mask, valid_parity, fields_parity):
    """Check all four ports' control fields whenever any CreditVld bit is set."""
    errors = set()
    if even_parity(valid_mask, 4) != _word(valid_parity, 1):
        errors.add("valid")
    if not valid_mask:
        return frozenset(errors)
    controls = _word(vcs, 8) | (_word(nums, 8) << 8) | (_word(pool_mask, 4) << 16)
    if even_parity(controls, 20) != _word(fields_parity, 1):
        errors.add("control")
    return frozenset(errors)
