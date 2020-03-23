"""Helper functions to create CNN in ONNX format."""

from typing import Any, List, Tuple

import numpy as np
from onnx import helper
from onnx import TensorProto


def make_quant_tensors(node_name: str, quant: tuple) -> list:
    """Create generic quantization tensors."""
    return [
        helper.make_tensor(
            name=node_name + "_scale",
            data_type=TensorProto.FLOAT,
            dims=(1,),
            vals=[quant[0]]
        ),
        helper.make_tensor(
            name=node_name + "_zero_point",
            data_type=TensorProto.INT8,
            dims=(1,),
            vals=[quant[1]]
        ),
    ]


def make_conv_quant(last_layer_info: tuple, name: str, ch_in: int, ch_out: int,
                    param: Tuple[int, int, int]) -> Tuple[Any, List[Any]]:
    """Create a convolution node and corresponding (random) weights."""
    ksize, stride, pad = param

    # Create a node (NodeProto)
    node_def = helper.make_node(
        "QLinearConv",
        inputs=[last_layer_info[0] + "_out", *last_layer_info[1:],
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

    np_array = np.random.randint(
        -2 ** 7, 2 ** 7 - 1, size=(ch_out, ch_in, ksize, ksize), dtype=np.int8)
    initializer.append(
        helper.make_tensor(
            name=name + "_weights",
            data_type=TensorProto.INT8,
            dims=(ch_out, ch_in, ksize, ksize),
            vals=np_array.reshape(ch_out * ch_in * ksize * ksize).tolist()
        )
    )

    np_array = np.random.randint(-2 ** 7, 2 ** 7 - 1, size=(ch_out,),
                                 dtype=np.int32)
    initializer.append(
        helper.make_tensor(
            name=name + "_bias",
            data_type=TensorProto.INT32,
            dims=(ch_out,),
            vals=np_array.reshape(ch_out).tolist()
        )
    )

    # quantization parameter
    quant = (16, 0)
    initializer.extend(make_quant_tensors(name, quant))
    initializer.extend(make_quant_tensors(name + "_weights", quant))
    initializer.extend(make_quant_tensors(name + "_bias", quant))
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


def make_dequant(name_prev: str, name: str,
                 quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a quantization node, which converts fixedint to float."""
    input_ = name_prev[0] + "_out"
    node_def = helper.make_node(
        "DequantizeLinear",
        inputs=[input_, name + "_scale", name + "_zero_point"],
        outputs=[name + "_out"],
    )

    # quantization parameter
    initializer = make_quant_tensors(name, quant)
    return node_def, initializer


def make_quant(name_prev: str, name: str,
               quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a quantization node, which converts float to fixedint."""
    input_ = (name_prev[0] if name_prev[0] == "data_in"
              else name_prev[0] + "_out")
    node_def = helper.make_node(
        "QuantizeLinear",
        inputs=[input_, name + "_scale", name + "_zero_point"],
        outputs=[name + "_out"],
    )

    # quantization parameter
    initializer = make_quant_tensors(name, quant)
    return node_def, initializer


class GraphGenerator:
    """Utility to simplify creation of ONNX CNN models a bit."""
    def __init__(self):
        self.last_layer_name = "data_in"
        self.last_quant_name = "data_in"

        self.node_defs = []
        self.initializers = []

    def add(self, func, *args):
        """Add a function, which generates a node definition and optionally
        initializer. The function represents a layer of the CNN."""
        last_layer_info = [self.last_layer_name]
        if func.__name__ == "make_conv_quant":
            last_layer_info.extend([self.last_quant_name + "_scale",
                                    self.last_quant_name + "_zero_point"])

            scale = 1 if self.last_quant_name == "data_in" else 16
            node_def, initializer = make_quant(
                last_layer_info, args[0] + "_quant", (scale, 0))
            self.node_defs.append(node_def)
            self.initializers.extend(initializer)

            last_layer_info = [args[0] + "_quant", args[0] + "_quant_scale",
                               args[0] + "_quant_zero_point"]

        node_def, initializer = func(last_layer_info, *args)
        self.node_defs.append(node_def)
        self.initializers.extend(initializer)

        if func.__name__ == "make_conv_quant":
            last_layer_info = [args[0], args[0] + "_scale",
                               args[0] + "_zero_point"]
            node_def, initializer = make_dequant(
                last_layer_info, args[0] + "_dequant", (16, 0))
            self.node_defs.append(node_def)
            self.initializers.extend(initializer)

            self.last_quant_name = args[0] + "_dequant"
            self.last_layer_name = self.last_quant_name
        else:
            self.last_layer_name = args[0]

    def get_model(self, graph_name, shape_in, shape_out):
        """Generate a model, based on the added layers."""
        data_in = helper.make_tensor_value_info(
            "data_in", TensorProto.FLOAT, shape_in)
        data_out = helper.make_tensor_value_info(
            self.last_layer_name + "_out", TensorProto.FLOAT, shape_out)

        graph_def = helper.make_graph(
            self.node_defs,
            graph_name,
            [data_in],
            [data_out],
        )
        graph_def.initializer.extend(self.initializers)
        return helper.make_model(graph_def)
