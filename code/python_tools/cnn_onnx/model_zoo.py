import math

import numpy as np
from onnx import helper
from onnx import TensorProto

from fixfloat import random_fixed_array


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def make_conv(name, name_prev, ch_in, ch_out, ksize, stride, pad):
    # Create a node (NodeProto)
    node_def = helper.make_node(
        "Conv",
        inputs=[name_prev + "_out", name + "_weights", name + "_bias"],
        outputs=[name + "_out"],
        kernel_shape=[ksize]*2,
        strides=[stride]*2,
        pads=[pad]*4,
    )

    np_array = np.random.randn(ch_out, ch_in, ksize, ksize).astype(np.float)
    weights_tensor = helper.make_tensor(
        name=name + "_weights",
        data_type=TensorProto.FLOAT,
        dims=(ch_out, ch_in, ksize, ksize),
        vals=np_array.reshape(ch_out * ch_in * ksize * ksize).tolist()
    )

    np_array = np.random.randn(ch_out).astype(np.float)
    bias_tensor = helper.make_tensor(
        name=name + "_bias",
        data_type=TensorProto.FLOAT,
        dims=(ch_out,),
        vals=np_array.reshape(ch_out).tolist()
    )

    return node_def, [weights_tensor, bias_tensor]


def make_conv_quant(name, name_prev, name_last_quant,
                    ch_in, ch_out, ksize, stride, pad):
    total_bits = 8
    weights_scale = 16

    frac_bits = int(math.log2(weights_scale))
    int_bits = total_bits - frac_bits

    # Create a node (NodeProto)
    node_def = helper.make_node(
        "QLinearConv",
        inputs=[name_prev + "_out", name_last_quant + "_scale",
                name_last_quant + "_zero_point",
                name + "_weights",
                name + "_weights_scale", name + "_weights_zero_point",
                name + "_scale", name + "_zero_point",
                name + "_bias"],
        outputs=[name + "_out"],
        kernel_shape=[ksize]*2,
        strides=[stride]*2,
        pads=[pad]*4,
    )

    np_array = random_fixed_array(
        (ch_out, ch_in, ksize, ksize), int_bits, frac_bits)
    weights_tensor = helper.make_tensor(
        name=name + "_weights",
        data_type=TensorProto.FLOAT,
        dims=(ch_out, ch_in, ksize, ksize),
        vals=np_array.reshape(ch_out * ch_in * ksize * ksize).tolist()
    )

    np_array = random_fixed_array((ch_out,), int_bits, frac_bits)
    bias_tensor = helper.make_tensor(
        name=name + "_bias",
        data_type=TensorProto.FLOAT,
        dims=(ch_out,),
        vals=np_array.reshape(ch_out).tolist()
    )

    # quantization parameter
    scale_tensor = helper.make_tensor(
        name=name + "_scale",
        data_type=TensorProto.FLOAT,
        dims=(1,),
        vals=[weights_scale]
    )

    zero_point_tensor = helper.make_tensor(
        name=name + "_zero_point",
        data_type=TensorProto.FLOAT,
        dims=(1,),
        vals=[0]
    )

    weights_scale_tensor = helper.make_tensor(
        name=name + "_weights_scale",
        data_type=TensorProto.FLOAT,
        dims=(1,),
        vals=[weights_scale]
    )

    weights_zero_point_tensor = helper.make_tensor(
        name=name + "_weights_zero_point",
        data_type=TensorProto.FLOAT,
        dims=(1,),
        vals=[0]
    )

    initializer = [weights_tensor, bias_tensor,
                   weights_scale_tensor, weights_zero_point_tensor,
                   scale_tensor, zero_point_tensor]
    return node_def, initializer


def make_pool_max(name, name_prev, ksize, stride):
    # Create a node (NodeProto)
    node_def = helper.make_node(
        "MaxPool",
        inputs=[name_prev + "_out"],
        outputs=[name + "_out"],
        kernel_shape=[ksize]*2,
        strides=[stride]*2,
    )
    return node_def, []


def make_relu(name, name_prev):
    # Create a node (NodeProto)
    node_def = helper.make_node(
        "Relu",
        inputs=[name_prev + "_out"],
        outputs=[name + "_out"],
    )
    return node_def, []


def make_leaky_relu(name, name_prev):
    # Create a node (NodeProto)
    node_def = helper.make_node(
        "LeakyRelu",
        inputs=[name_prev + "_out"],
        outputs=[name + "_out"],
        alpha=0.125,
    )
    return node_def, []


def make_pool_ave(name, name_prev):
    # Create a node (NodeProto)
    node_def = helper.make_node(
        "GlobalAveragePool",
        inputs=[name_prev + "_out"],
        outputs=[name + "_out"],
    )
    return node_def, []


def make_scale(name, name_prev, quant):
    # Create a node (NodeProto)
    node_def = helper.make_node(
        "QuantizeLinear",
        inputs=[name_prev + "_out", name + "_scale", name + "_zero_point"],
        outputs=[name + "_out"],
    )

    # quantization parameter
    scale_tensor = helper.make_tensor(
        name=name + "_scale",
        data_type=TensorProto.FLOAT,
        dims=(1,),
        vals=[quant[0]]
    )

    zero_point_tensor = helper.make_tensor(
        name=name + "_zero_point",
        data_type=TensorProto.FLOAT,
        dims=(1,),
        vals=[quant[1]]
    )

    return node_def, [scale_tensor, zero_point_tensor]


class GraphGenerator:
    # TODO: better abstraction
    def __init__(self, shape_in, shape_out):
        self.shape_in = shape_in
        self.shape_out = shape_out
        self.node_defs = []
        self.initializers = []

    def add(self, node_def, initializer):
        self.node_defs.append(node_def)
        self.initializers.extend(initializer)

    def get_graph(self, graph_name, name_in, name_out):
        # Create one input and output (ValueInfoProto)
        data_in = helper.make_tensor_value_info(
            name_in, TensorProto.FLOAT, self.shape_in)
        data_out = helper.make_tensor_value_info(
            name_out, TensorProto.FLOAT, self.shape_out)

        # Create the graph (GraphProto)
        graph_def = helper.make_graph(
            self.node_defs,
            graph_name,
            [data_in],
            [data_out],
        )
        graph_def.initializer.extend(self.initializers)

        return graph_def


def cnn1():
    # create cnn in onnx representation
    graph_gen = GraphGenerator((1, 6, 6), (4, 1, 1))

    graph_gen.add(*make_scale("scale1", "data", (16, 0)))
    graph_gen.add(*make_conv_quant("conv1", "scale1", "scale1", 1, 4, 3, 1, 0))
    # graph_gen.add(*make_leaky_relu("lrelu1", "conv1"))  # TODO: fix
    graph_gen.add(*make_relu("lrelu1", "conv1"))
    graph_gen.add(*make_pool_max("max1", "lrelu1", 2, 2))
    graph_gen.add(*make_conv_quant("conv2", "max1", "conv1", 4, 8, 1, 1, 0))
    graph_gen.add(*make_relu("relu2", "conv2"))
    graph_gen.add(*make_pool_ave("ave1", "relu2"))

    graph_def = graph_gen.get_graph("simple_net", "data_out", "ave1_out")

    # Create the model (ModelProto)
    model_def = helper.make_model(graph_def)
    return model_def
