"""Helper functions to quantize an arbitrary CNN in ONNX format."""

import argparse
import math
import os
from typing import Any, List, Tuple, Union

import onnx
from onnx import helper, numpy_helper, TensorProto
import numpy as np

from common import CnnArchitectureError, NotSupportedError
from cnn_onnx import parse_param
from cnn_onnx import graph_generator as gg
from fp_helper import to_fixed_point_array, v_to_fixedint
from fp_helper import is_power_of_two, v_is_power_of_two


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


def analyze_and_quantize(original_weights, original_bias,
                         aggressive: bool = False) -> dict:
    """Analyze and quantize the weights."""
    max_val = max(np.amax(original_weights), np.amax(original_bias))
    min_val = min(np.amin(original_weights), np.amin(original_bias))
    highest_val = max(abs(max_val), abs(min_val))
    int_width = get_integer_width(highest_val)
    print("weight quantization: ", int_width, 8-int_width)
    print("stats: ", max_val, min_val, highest_val)

    # quantize the weights
    quantized_weights = to_fixed_point_array(
        original_weights, int_bits=int_width, frac_bits=8 - int_width,
        aggressive=aggressive)
    quantized_bias = to_fixed_point_array(
        original_bias, int_bits=int_width, frac_bits=8 - int_width,
        aggressive=aggressive)
    quantized_weights_int = v_to_fixedint(quantized_weights)
    quantized_bias_int = v_to_fixedint(quantized_bias)
    print("average error per weight:",
          np.mean(np.abs(original_weights - quantized_weights)))
    avg_val = np.mean(np.abs(quantized_weights))
    print("average absolute weight value:", avg_val)

    # print the weight stats (bias is omitted for now)
    count = {"total": quantized_weights.size}
    count["zeros"] = count["total"] - np.count_nonzero(quantized_weights)
    count["power_of_two"] = np.count_nonzero(
        v_is_power_of_two(quantized_weights))
    count["other"] = count["total"] - count["zeros"] - count["power_of_two"]
    print("total weights:", count["total"])
    print("zero weights:", count["zeros"], count["zeros"] / count["total"])
    print("power of two weights:", count["power_of_two"],
          count["power_of_two"] / count["total"])
    print("left weights:", count["other"], count["other"] / count["total"])

    if aggressive and count["other"]:
        Warning("At aggressive quantization all weights should be"
                "0 or power of two.")

    return {
        "weights": quantized_weights_int,
        "bias": quantized_bias_int,
        "quant": (int_width, 8-int_width),
        "avg_val": avg_val,
    }


def verify_quant(quant: tuple):
    """Verify that the given quantization is valid."""
    if not is_power_of_two(quant[0]):
        raise NotSupportedError(
            f"Only power of two scale supported. Got {quant[0]}.")
    if quant[1] != 0:
        raise NotSupportedError(
            f"Only zero point = 0 supported. Got {quant[1]}.")


def make_conv_quant(node, weights_dict: dict, quant_in: tuple,
                    aggressive: bool = False
                    ) -> Tuple[Any, List[Any], Tuple[int, int]]:
    """Create a convolution node and quantize the weights.
    Quantizations get calculated as follows:
    - input quantization is given
    - weight quantization gets calculated based on the actual weights
    - output quantization is input quantization * average weight value
    """
    verify_quant(quant_in)

    node_name = node.output[0] if node.name == "" else node.name

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
    quantized_weights = analyze_and_quantize(
        weights_dict[node.input[1]], weights_dict[node.input[2]],
        aggressive=aggressive)

    # calculate output scale
    quant_factor = round(math.log2(quantized_weights["avg_val"]))
    quant_scale_bits = math.log2(quant_in[0]) - quant_factor
    quant_scale = max(min(2 ** quant_scale_bits, 2 ** 8), 1)
    quant_out = (int(quant_scale), 0)

    # setup the initializer
    initializer = [
        helper.make_tensor(
            name=node_name + "_quant_weights",
            data_type=TensorProto.INT8,
            dims=quantized_weights["weights"].shape,
            vals=quantized_weights["weights"].flatten().tolist()
        ),
        helper.make_tensor(
            name=node_name + "_quant_bias",
            data_type=TensorProto.INT32,
            dims=quantized_weights["bias"].shape,
            vals=quantized_weights["bias"].flatten().tolist()
        ),
    ]
    # quantization parameter
    initializer.extend(
        gg.make_quant_tensors(node_name + "_quant_weights",
                              quantized_weights["quant"]))
    initializer.extend(
        gg.make_quant_tensors(node_name + "_quant", (16, 0)))
    return node_def, initializer, quant_out


def make_dequant(input_name: str, output_name: str,
                 quant: tuple) -> Tuple[Any, List[Any]]:
    """Create a quantization node, which converts fixedint to float."""
    verify_quant(quant)

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
    verify_quant(quant)

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


def quantize(model, aggressive=False):
    """Quantize an arbitrary CNN model."""
    # TODO: add types
    new_nodes = []
    new_initializers = []

    weights_dict = {init.name: numpy_helper.to_array(init)
                    for init in model.graph.initializer}

    quant_out = (1, 0)
    for node in model.graph.node:
        if node.op_type == "Conv":
            # add the three quantization "replacements":
            # QuantizeLinear, QLinearConv and DequantizeLinear
            node_name = node.output[0] if node.name == "" else node.name

            if node.input[0] + "_quant" not in [nn.name for nn in new_nodes]:
                # prevent duplicated nodes when input is already quantized
                quant_in = quant_out
                node_q, init = make_quant(node.input[0], quant_in)
                new_nodes.append(node_q)
                new_initializers.extend(init)

            node_q, init, quant_out = make_conv_quant(
                node, weights_dict, quant_in, aggressive=aggressive)
            new_nodes.append(node_q)
            new_initializers.extend(init)

            node_q, init = make_dequant(node_name, node.output[0], quant_out)
            new_nodes.append(node_q)
            new_initializers.extend(init)

            # remove original weight and bias
            inits_to_delete = [init for init in model.graph.initializer
                               if init.name in node.input[1:3]]
            if len(inits_to_delete) != 2:
                raise CnnArchitectureError(
                    f"There should be exactly two inits to delete. "
                    f"Found {len(inits_to_delete)}.")
            for init in inits_to_delete:
                model.graph.initializer.remove(init)

            # remove corresponding inputs
            inputs_to_delete = [input_ for input_ in model.graph.input
                                if input_.name in node.input[1:3]]
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-path", default="model.onnx",
                        help="Path to the onnx model.")
    parser.add_argument(
        "--aggressive", action="store_true",
        help="Use aggressive quantization."
             "Lower ressource usage, but worse classification.")
    args = parser.parse_args()

    model = onnx.load(args.model_path)
    onnx.checker.check_model(model)

    model_q = quantize(model, aggressive=args.aggressive)
    onnx.checker.check_model(model_q)

    name, extension = os.path.splitext(args.model_path)
    output_path = f"{name}_quantized{extension}"
    onnx.save(model_q, output_path)


if __name__ == "__main__":
    main()
