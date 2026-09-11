"""Common 2.0 section 2.5 TDM phase observer, separate from credit returns."""


class UpliTdm:
    """Track one shared req/data phase and independently learned response phases."""

    def __init__(self, num_ports: int):
        if type(num_ports) is not int:
            raise TypeError("num_ports must be an integer")
        if num_ports not in (1, 2, 4):
            raise ValueError("a UPLI station has one, two or four ports")
        self.num_ports = num_ports
        self._phase = {"req": None, "rd_rsp": None, "wr_rsp": None}

    def step(self, beats=(), reset: bool = False) -> None:
        """Observe valid (channel, port) pairs; invalid cycles convey no PortID."""
        if type(reset) is not bool:
            raise TypeError("reset must be a boolean")
        if reset:
            self._phase = {"req": None, "rd_rsp": None, "wr_rsp": None}
            return
        current = dict(self._phase)
        observed = {}
        for channel, port in beats:
            if channel not in ("req", "orig_data", "rd_rsp", "wr_rsp"):
                raise ValueError("unknown UPLI channel")
            if type(port) is not int:
                raise TypeError("PortID must be an integer")
            if not 0 <= port < self.num_ports or channel in observed:
                raise ValueError("unused PortID or multiple beats on one channel")
            observed[channel] = port
        if "req" in observed and current["req"] is None:
            current["req"] = observed["req"]
        for channel, port in observed.items():
            group = "req" if channel == "orig_data" else channel
            if current[group] is None:
                if channel == "orig_data":
                    raise ValueError("OrigData cannot establish phase before the first Request")
                current[group] = port
            if port != current[group]:
                raise ValueError("valid PortID does not match the established TDM phase")
        self._phase = {group: None if phase is None else (phase + 1) % self.num_ports
                       for group, phase in current.items()}
