from os.path import join, dirname
from random import randint

from vunit import VUnit


def create_stimuli(root, bits, channel):
    a_in = [str(randint(0, 2 ** bits - 1)) for _ in range(channel)]
    with open(join(root, "src", "input_output.csv"), "w") as outfile:
        outfile.write(", ".join(a_in))


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "src", "*.vhd"))
    tb_channel_burst = unittest.entity("tb_channel_burst")

    bits = 8
    channel = randint(1, 16)
    for interval in (1, 2, 3, 32):  # data sending interval in cycles
        generics = {"interval": interval,
                    "C_DATA_WIDTH": bits,
                    "C_CH": channel}
        tb_channel_burst.add_config(name="interval=%d" % (interval),
                                    generics=generics,
                                    pre_config=create_stimuli(root, bits, channel))
        tb_channel_burst.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
