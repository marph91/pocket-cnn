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
        Monitor.__init__(self, callback, event)

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.clk)
            if bool(self.valid.value.integer):
                print("recv:", self.data.value.integer)
                self._recv(self.data.value.integer)
