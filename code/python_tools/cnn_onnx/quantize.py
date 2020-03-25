"""Helper functions to quantize an arbitrary CNN in ONNX format."""

import math
from typing import Any, List, Tuple, Union

import onnx
from onnx import helper, numpy_helper, TensorProto
import numpy as np

from cnn_onnx import parse_param
from cnn_onnx import graph_generator as gg
from fixfloat import v_float2ffloat


def is_power_of_two(val: Union[int, float]) -> bool:
    """Check whether a number is a power of two.

    >>> is_power_of_two(-1)
    True
    >>> is_power_of_two(-0.125)
    True
    >>> is_power_of_two(0)
    False
    >>> is_power_of_two(0.25)
    True
    >>> is_power_of_two(1)
    True
    >>> is_power_of_two(2)
    True
    >>> is_power_of_two(5)
    False
    >>> is_power_of_two(2048)
    True
    >>> is_power_of_two(2049)
    False
    """
    if not val:
        return False
    bits = math.log2(abs(val))
    return int(bits) == bits


def v_is_power_of_two(val: Union[int, float]):
    """Vectorized version of "is_power_of_two()"."""
    vector_is_power_of_two = np.vectorize(is_power_of_two, otypes=[np.int])
    return vector_is_power_of_two(val)


def get_integer_width(val: Union[int, float], max_bitwidth: int = 8) -> int:
    """Obtain the needed signed integer bitwidth to cover the value.
    >>> get_integer_width(0.1)
    1
    >>> get_integer_width(1.5)
    2
    >>> get_integer_width(3.3)
    3
    >>> get_integer_width(122)
    8
    >>> get_integer_width(1000)
    8
    """
    return min(math.ceil(max(math.log2(val), 0)) + 1, max_bitwidth)


def analyze_and_quantize(original_weights, original_bias):
    """Analyze and quantize the weights."""
    max_val = max(np.amax(original_weights), np.amax(original_bias))
    min_val = min(np.amin(original_weights), np.amin(original_bias))
    highest_val = max(abs(max_val), abs(min_val))
    int_width = get_integer_width(highest_val)

    print("weight quantization: ", int_width, 8-int_width)
    print("stats: ", max_val, min_val, highest_val)

    # TODO: quantize bias properly
    #       i. e. consider quantization of weights and activations
    quantized_weights = v_float2ffloat(
        original_weights, int_width, 8 - int_width)
    quantized_bias = v_float2ffloat(
        original_bias, int_width, 8 - int_width)
    quantized_weights_int = (
        quantized_weights * 2 ** (8 - int_width)).astype(np.int8)
    quantized_bias_int = (
        quantized_bias * 2 ** (8 - int_width)).astype(np.int32)
    print("average error per weight:",
          np.average(np.abs(original_weights - quantized_weights)))

    total_cnt = quantized_weights.size
    zero_cnt = np.count_nonzero(np.where(quantized_weights == 0))
    po2_cnt = np.count_nonzero(v_is_power_of_two(quantized_weights))
    left_cnt = total_cnt - zero_cnt - po2_cnt
    print("total weights:", total_cnt)
    print("zero weights:", zero_cnt, zero_cnt / total_cnt)
    print("po2 weights:", po2_cnt, po2_cnt / total_cnt)
    print("left weights:", left_cnt, left_cnt / total_cnt)

    return quantized_weights_int, quantized_bias_int


def make_conv_quant(node, weights_dict: dict,
                    quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a convolution node and quantize the weights."""
    assert is_power_of_two(quant[0]), "only power of two scale supported"
    assert quant[1] == 0, "only zero point = 0 supported"

    node_name = node.output[0] if node.name == "" else node.name

    # TODO: get input scale -> calculate weight and output scale

    # Create a node (NodeProto)
    node_def = helper.make_node(
        "QLinearConv",
        name=node_name + "_qconv",
        inputs=[node.input[0] + "_quant",
                node.input[0] + "_quant_scale",
                node.input[0] + "_quant_zero_point",
                node_name + "_quant_weights",
                node_name + "_quant_weights_scale",
                node_name + "_quant_weights_zero_point",
                node_name + "_quant_scale",
                node_name + "_quant_zero_point",
                node_name + "_quant_bias"],
        outputs=[node_name + "_dequant"],
        **parse_param.parse_node_attributes(node),
    )

    # quantize the weights
    print("#"*50)
    print("layer: ", node_name + "_qconv")
    weights_quant, bias_quant = analyze_and_quantize(
        weights_dict[node.input[1]], weights_dict[node.input[2]])

    # setup the initializer
    initializer = [
        helper.make_tensor(
            name=node_name + "_quant_weights",
            data_type=TensorProto.INT8,
            dims=weights_quant.shape,
            vals=weights_quant.flatten().tolist()
        ),
        helper.make_tensor(
            name=node_name + "_quant_bias",
            data_type=TensorProto.INT32,
            dims=bias_quant.shape,
            vals=bias_quant.flatten().tolist()
        ),
    ]
    # quantization parameter
    initializer.extend(
        gg.make_quant_tensors(node_name + "_quant_weights", quant))
    initializer.extend(
        gg.make_quant_tensors(node_name + "_quant", (16, 0)))
    return node_def, initializer


def make_dequant(input_name: str, output_name: str,
                 quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a quantization node, which converts fixedint to float."""
    assert is_power_of_two(quant[0]), "only power of two scale supported"
    assert quant[1] == 0, "only zero point = 0 supported"

    node_def = helper.make_node(
        "DequantizeLinear",
        name=input_name + "_dequant",
        inputs=[input_name + "_dequant",
                input_name + "_dequant_scale",
                input_name + "_dequant_zero_point"],
        outputs=[output_name],
    )

    # quantization parameter
    initializer = gg.make_quant_tensors(input_name + "_dequant", quant)
    return node_def, initializer


def make_quant(input_name: str, quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a quantization node, which converts float to fixedint."""
    assert is_power_of_two(quant[0]), "only power of two scale supported"
    assert quant[1] == 0, "only zero point = 0 supported"

    node_def = helper.make_node(
        "QuantizeLinear",
        name=input_name + "_quant",
        inputs=[input_name,
                input_name + "_quant_scale",
                input_name + "_quant_zero_point"],
        outputs=[input_name + "_quant"],
    )

    # quantization parameter
    initializer = gg.make_quant_tensors(input_name + "_quant", quant)
    return node_def, initializer


def quantize(model):
    """Quantize an arbitrary CNN model."""
    new_nodes = []
    new_initializers = []

    weights_dict = {init.name: numpy_helper.to_array(init)
                    for init in model.graph.initializer}

    for node in model.graph.node:
        if node.op_type == "Conv":
            # add the three quantization "replacements":
            # QuantizeLinear, QLinearConv and DequantizeLinear
            node_name = node.output[0] if node.name == "" else node.name

            quant_in = (16, 0) if new_nodes else (1, 0)
            if node.input[0] + "_quant" not in [nn.name for nn in new_nodes]:
                # prevent duplicated nodes when input is already quantized
                node_q, init = make_quant(node.input[0], quant_in)
                new_nodes.append(node_q)
                new_initializers.extend(init)

            node_q, init = make_conv_quant(node, weights_dict, quant_in)
            quant_out = (16, 0)
            new_nodes.append(node_q)
            new_initializers.extend(init)

            node_q, init = make_dequant(node_name, node.output[0], quant_out)
            new_nodes.append(node_q)
            new_initializers.extend(init)

            # remove original weight and bias
            inits_to_delete = [init for init in model.graph.initializer
                               if init.name in node.input[1:3]]
            assert len(inits_to_delete) == 2
            for init in inits_to_delete:
                model.graph.initializer.remove(init)

            # remove corresponding inputs
            inputs_to_delete = [input_ for input_ in model.graph.input
                                if input_.name in node.input[1:3]]
            # TODO: assert len(inputs_to_delete) == 2
            for input_ in inputs_to_delete:
                model.graph.input.remove(input_)
        else:
            new_nodes.append(node)

    # update nodes
    model.graph.ClearField("node")
    model.graph.node.extend(new_nodes)

    # add new initializer and corresponding inputs
    model.graph.initializer.extend(new_initializers)
    model.graph.input.extend(
        [helper.make_tensor_value_info(i.name, i.data_type, i.dims)
         for i in new_initializers])

    # update opset
    model.ClearField("opset_import")
    model.opset_import.extend([onnx.helper.make_opsetid("", 11)])
    model.opset_import.extend([onnx.helper.make_opsetid("ai.onnx", 11)])

    return model


def main():
    """Main function to demonstrate the usage."""
    # filename = "squeezenet1.1.onnx"
    # filename_q = "squeezenet1.1_quantized.onnx"
    filename = "mnist_cnn.onnx"
    filename_q = "mnist_cnn_quantized.onnx"

    model = onnx.load(filename)
    onnx.checker.check_model(model)

    model_q = quantize(model)
    onnx.checker.check_model(model_q)
    onnx.save(model_q, filename_q)


if __name__ == "__main__":
    main()
