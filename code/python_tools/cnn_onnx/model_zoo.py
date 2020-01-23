"""Model zoo for generating various CNN models in ONNX format.
Includes helper functions as well as the model definitions."""

import math
from typing import Any, List, Tuple

from onnx import helper
from onnx import TensorProto

from fixfloat import random_fixed_array


# somehow the onnx members aren't detected properly
# pylint: disable=no-member
# allow more expressive names for the cnn models
# pylint: disable=invalid-name

# helper functions

def make_conv_quant(last_layer_info: tuple, name: str, ch_in: int, ch_out: int,
                    param: Tuple[int, int, int]) -> Tuple[Any, List[Any]]:
    """Create a convolution node and corresponding (random) weights."""
    weights_scale = 16
    ksize, stride, pad = param

    frac_bits = int(math.log2(weights_scale))
    int_bits = 8 - frac_bits

    # Create a node (NodeProto)
    node_def = helper.make_node(
        "QLinearConv",
        inputs=[*last_layer_info,
                name + "_weights",
                name + "_weights_scale", name + "_weights_zero_point",
                name + "_scale", name + "_zero_point",
                name + "_bias"],
        outputs=[name + "_out"],
        kernel_shape=[ksize]*2,
        strides=[stride]*2,
        pads=[pad]*4,
    )

    initializer = []

    np_array = random_fixed_array(
        (ch_out, ch_in, ksize, ksize), int_bits, frac_bits)
    initializer.append(
        helper.make_tensor(
            name=name + "_weights",
            data_type=TensorProto.FLOAT,
            dims=(ch_out, ch_in, ksize, ksize),
            vals=np_array.reshape(ch_out * ch_in * ksize * ksize).tolist()
        )
    )

    np_array = random_fixed_array((ch_out,), int_bits, frac_bits)
    initializer.append(
        helper.make_tensor(
            name=name + "_bias",
            data_type=TensorProto.FLOAT,
            dims=(ch_out,),
            vals=np_array.reshape(ch_out).tolist()
        )
    )

    # quantization parameter
    initializer.extend([
        helper.make_tensor(
            name=name + "_scale",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[weights_scale]
        ),
        helper.make_tensor(
            name=name + "_zero_point",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[0]
        ),
        helper.make_tensor(
            name=name + "_weights_scale",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[weights_scale]
        ),
        helper.make_tensor(
            name=name + "_weights_zero_point",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[0]
        ),
    ])
    return node_def, initializer


def make_pool_max(name_prev: str, name: str,
                  ksize: int, stride: int) -> Tuple[Any, List[Any]]:
    """Create a local maximum pooling relu node."""
    node_def = helper.make_node(
        "MaxPool",
        inputs=[name_prev[0] + "_out"],
        outputs=[name + "_out"],
        kernel_shape=[ksize]*2,
        strides=[stride]*2,
    )
    return node_def, []


def make_relu(name_prev: str, name: str):
    """Create a relu node."""
    node_def = helper.make_node(
        "Relu",
        inputs=[name_prev[0] + "_out"],
        outputs=[name + "_out"],
    )
    return node_def, []


def make_leaky_relu(name_prev: str, name: str) -> Tuple[Any, List[Any]]:
    """Create a leaky relu node."""
    node_def = helper.make_node(
        "LeakyRelu",
        inputs=[name_prev[0] + "_out"],
        outputs=[name + "_out"],
        alpha=0.125,
    )
    return node_def, []


def make_pool_ave(name_prev: str, name: str) -> Tuple[Any, List[Any]]:
    """Create a global average pooling node."""
    node_def = helper.make_node(
        "GlobalAveragePool",
        inputs=[name_prev[0] + "_out"],
        outputs=[name + "_out"],
    )
    return node_def, []


def make_scale(name_prev: str, name: str,
               quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a scale node and corresponding quantization information."""
    node_def = helper.make_node(
        "QuantizeLinear",
        inputs=[name_prev[0] + "_out", name + "_scale", name + "_zero_point"],
        outputs=[name + "_out"],
    )

    # quantization parameter
    initializer = [
        helper.make_tensor(
            name=name + "_scale",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[quant[0]]
        ),
        helper.make_tensor(
            name=name + "_zero_point",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[quant[1]]
        ),
    ]
    return node_def, initializer


class GraphGenerator:
    """Utility to simplify creation of ONNX CNN models a bit."""
    def __init__(self):
        self.previous_layer_name = "data_in"
        self.last_quant_name = None

        self.node_defs = []
        self.initializers = []

    def add(self, func, *args):
        """Add a function, which generates a node definition and optionally
        initializer. The function represents a layer of the CNN."""
        last_layer_info = [self.previous_layer_name]
        if func.__name__ == "make_conv_quant":
            assert self.last_quant_name is not None
            last_layer_info.extend([self.last_quant_name + "_scale",
                                    self.last_quant_name + "_zero_point"])

        node_def, initializer = func(last_layer_info, *args)
        self.node_defs.append(node_def)
        self.initializers.extend(initializer)

        if func.__name__ in ["make_scale", "make_conv_quant"]:
            self.last_quant_name = args[0]
        self.previous_layer_name = args[0]

    def get_graph(self, graph_name, shape_in, shape_out):
        """Generate a graph, based on the added layers."""
        data_in = helper.make_tensor_value_info(
            "data_in", TensorProto.FLOAT, shape_in)
        data_out = helper.make_tensor_value_info(
            self.previous_layer_name + "_out", TensorProto.FLOAT, shape_out)

        graph_def = helper.make_graph(
            self.node_defs,
            graph_name,
            [data_in],
            [data_out],
        )
        graph_def.initializer.extend(self.initializers)
        return graph_def


# model definitions

def conv_3x1_1x1_max_2x2():
    """Baseline model. size: 6x6 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 6, 6), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_leaky_relu():
    """Baseline model with one leaky relu."""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_leaky_relu, "lrelu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 6, 6), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_nonsquare_input():
    """Baseline model with a nonsquare input."""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 5, 9), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_odd_input():
    """Baseline model with an odd input."""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 7, 7), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_colored_input():
    """Baseline model with a colored input, i. e. three input channel."""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 3, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (3, 6, 6), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_odd_channel():
    """Baseline model with an odd number of channel. The channel depth is
    specified on purpose. There was a bug with channel depth = 2^x+1."""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 5, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 5, 9, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 6, 6), (9, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_one_channel():
    """Baseline model with only one channel in every layer."""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 1, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 1, 1, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 6, 6), (1, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x1():
    """size: 6x6 -> 4x4 -> 3x3"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 1)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 6, 6), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x2_1x1_max_2x1():
    """size: 9x9 -> 4x4 -> 3x3"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 2, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 1)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 9, 9), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_2x1_1x1_max_3x2():
    """size: 8x8 -> 7x7 -> 3x3"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (2, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 3, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 8, 8), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x3_2x2_1x1():
    """size: 12x12 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 3, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_conv_quant, "conv2", 4, 6, (2, 2, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_conv_quant, "conv3", 6, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu3")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 8, 8), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_3x1():
    """size: 6x6 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 3, 1)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 6, 6), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_3x3():
    """size: 8x8 -> 6x6 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 3, 3)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 8, 8), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_3x1_1x1_max_2x2_padding():
    """size: 4x4 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 4, (3, 1, 1))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 4, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 4, 4), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_4x3x1_1x1():
    """size: 10x10 -> 8x8 -> 6x6 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 8, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_conv_quant, "conv2", 8, 10, (3, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_conv_quant, "conv3", 10, 12, (3, 1, 0))
    graph_gen.add(make_relu, "relu3")
    graph_gen.add(make_conv_quant, "conv4", 12, 14, (3, 1, 0))
    graph_gen.add(make_relu, "relu4")
    graph_gen.add(make_conv_quant, "conv5", 14, 16, (1, 1, 0))
    graph_gen.add(make_relu, "relu5")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 10, 10), (16, 1, 1))
    return helper.make_model(graph_def)


def conv_2x_3x1_1x1_max_2x2():
    """size: 14x14 -> 12x12 -> 6x6 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 8, (3, 1, 0))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 8, 16, (3, 1, 0))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_max, "max2", 2, 2)
    graph_gen.add(make_conv_quant, "conv3", 16, 32, (1, 1, 0))
    graph_gen.add(make_relu, "relu3")
    graph_gen.add(make_conv_quant, "conv4", 32, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu4")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 14, 14), (8, 1, 1))
    return helper.make_model(graph_def)


def conv_2x_3x1_1x1_max_2x2_padding():
    """size: 8x8 -> 8x8 -> 4x4 -> 4x4 -> 2x2"""
    graph_gen = GraphGenerator()
    graph_gen.add(make_scale, "scale1", (16, 0))
    graph_gen.add(make_conv_quant, "conv1", 1, 8, (3, 1, 1))
    graph_gen.add(make_relu, "relu1")
    graph_gen.add(make_pool_max, "max1", 2, 2)
    graph_gen.add(make_conv_quant, "conv2", 8, 16, (3, 1, 1))
    graph_gen.add(make_relu, "relu2")
    graph_gen.add(make_pool_max, "max2", 2, 2)
    graph_gen.add(make_conv_quant, "conv3", 16, 32, (1, 1, 0))
    graph_gen.add(make_relu, "relu3")
    graph_gen.add(make_conv_quant, "conv4", 32, 8, (1, 1, 0))
    graph_gen.add(make_relu, "relu4")
    graph_gen.add(make_pool_ave, "ave1")

    graph_def = graph_gen.get_graph("cnn", (1, 14, 14), (8, 1, 1))
    return helper.make_model(graph_def)
