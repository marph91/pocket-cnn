import cocotb
from cocotb.monitors import Monitor
from cocotb.triggers import RisingEdge


class GeneralMonitor(Monitor):
    """Represents a general monitor. It takes clock, valid and data signals
    and returns the received integer value.
    """
    def __init__(self, name, clk, valid, data, callback=None, event=None):
        self.clk = clk
        self.name = name
        self.valid = valid
        self.data = data
        super().__init__(callback, event)

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.clk)
            if bool(self.valid.value.integer):
                print("recv:", self.data.value.integer)
                self._recv(self.data.value.integer)


def split_slv(data: int, bitwidth, total_width) -> list:
    """Split a "stacked" integer to multiple integers, based on the bitwidth.
    """
    data_split = []
    for _ in range(total_width // bitwidth):
        data, splitted = divmod(data, 2**bitwidth)
        data_split.append(splitted)
    return list(reversed(data_split))


def concatenate(data: list, bitwidth) -> int:
    """Concatenate a list of integers to one integer."""
    data_concat = 0
    for i, d in enumerate(data):
        data_concat += d << (bitwidth*i)
    return data_concat
