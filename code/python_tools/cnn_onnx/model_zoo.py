"""Model zoo, which contains various small CNN models in ONNX format."""

import cnn_onnx.graph_generator as gg

# allow more expressive names for the cnn models
# pylint: disable=invalid-name


def conv_3x1_1x1_max_2x2():
    """Baseline model. size: 6x6 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 6, 6), (1, 8, 1, 1))


# models to test specific configurations and layers


def conv_3x1_1x1_max_2x2_leaky_relu():
    """Baseline model with one leaky relu."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_leaky_relu, "lrelu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 6, 6), (1, 8, 1, 1))


def conv_3x1_1x1_max_2x2_no_relu():
    """Baseline model without relu."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 6, 6), (1, 8, 1, 1))


def conv_3x1_1x1_max_2x2_nonsquare_input():
    """Baseline model with a nonsquare input."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 4, 8), (1, 8, 1, 1))


def conv_3x1_1x1_max_2x2_odd_input():
    """Baseline model with an odd input."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 7, 7), (1, 8, 1, 1))


def conv_3x1_1x1_max_2x2_colored_input():
    """Baseline model with a colored input, i. e. three input channel."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 3, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 3, 6, 6), (1, 8, 1, 1))


def conv_3x1_1x1_max_2x2_odd_channel():
    """Baseline model with an odd number of channel. The channel depth is
    specified on purpose. There was a bug with channel depth = 2^x+1."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 5, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 5, 9, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 6, 6), (1, 9, 1, 1))


def conv_3x1_1x1_max_2x2_one_channel():
    """Baseline model with only one channel in every layer."""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 1, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 1, 1, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 6, 6), (1, 1, 1, 1))


def conv_3x1_1x1_max_2x1():
    """size: 12x12 -> 10x10 -> 9x9"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 1)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 12, 12), (1, 8, 1, 1))


def conv_3x2_1x1_max_2x1():
    """size: 17x17 -> 8x8 -> 7x7"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 2, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 1)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 17, 17), (1, 8, 1, 1))


def conv_3x2_1x1_max_2x1_padding():
    """size: 15x15 -> 17x17 -> 8x8 -> 7x7"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 2, 1))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 1)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 15, 15), (1, 8, 1, 1))


def conv_2x1_1x1_max_3x2():
    """size: 16x16 -> 15x15 -> 7x7"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (2, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 3, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 16, 16), (1, 8, 1, 1))


def conv_3x3_2x2_1x1():
    """size: 12x12 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 3, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 6, (2, 2, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_conv_quant, "conv3", 6, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu3")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 8, 8), (1, 8, 1, 1))


def conv_3x1_1x1_max_3x1():
    """size: 12x12 -> 10x10 -> 8x8"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 3, 1)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 12, 12), (1, 8, 1, 1))


def conv_3x1_1x1_max_3x3():
    """size: 14x14 -> 12x12 -> 4x4"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 3, 3)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 14, 14), (1, 8, 1, 1))


def conv_3x1_1x1_max_2x2_padding():
    """size: 4x4 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (3, 1, 1))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 4, 4), (1, 8, 1, 1))


def conv_5x1_1x1_max_2x2():
    """size: 8x8 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 4, (5, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 8, 8), (1, 8, 1, 1))


# larger models to test stacking of layers and general behaviour


def conv_4x3x1_1x1():
    """size: 10x10 -> 8x8 -> 6x6 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 8, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_conv_quant, "conv2", 8, 10, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_conv_quant, "conv3", 10, 12, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu3")
    graph_gen.add(gg.make_conv_quant, "conv4", 12, 14, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu4")
    graph_gen.add(gg.make_conv_quant, "conv5", 14, 16, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu5")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 10, 10), (1, 16, 1, 1))


def conv_2x_3x1_1x1_max_2x2():
    """size: 14x14 -> 12x12 -> 6x6 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 8, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 8, 16, (3, 1, 0))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_max, "max2", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv3", 16, 32, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu3")
    graph_gen.add(gg.make_conv_quant, "conv4", 32, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu4")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 14, 14), (1, 8, 1, 1))


def conv_2x_3x1_1x1_max_2x2_padding():
    """size: 8x8 -> 8x8 -> 4x4 -> 4x4 -> 2x2"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 8, (3, 1, 1))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 8, 16, (3, 1, 1))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_max, "max2", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv3", 16, 32, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu3")
    graph_gen.add(gg.make_conv_quant, "conv4", 32, 8, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu4")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 14, 14), (1, 8, 1, 1))


def conv_2x_3x1_1x1_max_2x2_mt():
    """Model of my master thesis, for comparison.
    size: 48x24 -> 24x12 -> 12x6"""
    graph_gen = gg.GraphGenerator()
    graph_gen.add(gg.make_conv_quant, "conv1", 1, 16, (3, 1, 1))
    graph_gen.add(gg.make_relu, "relu1")
    graph_gen.add(gg.make_pool_max, "max1", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv2", 16, 32, (3, 1, 1))
    graph_gen.add(gg.make_relu, "relu2")
    graph_gen.add(gg.make_pool_max, "max2", 2, 2)
    graph_gen.add(gg.make_conv_quant, "conv3", 32, 64, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu3")
    graph_gen.add(gg.make_conv_quant, "conv4", 64, 2, (1, 1, 0))
    graph_gen.add(gg.make_relu, "relu4")
    graph_gen.add(gg.make_pool_ave, "ave1")
    return graph_gen.get_model("cnn", (1, 1, 48, 24), (1, 2, 1, 1))
