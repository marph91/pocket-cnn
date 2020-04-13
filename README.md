# pocket-cnn

[![testsuite](https://github.com/marph91/pocket-cnn/workflows/testsuite/badge.svg)](https://github.com/marph91/pocket-cnn/actions?query=workflow%3Atestsuite)
[![check_scripts](https://github.com/marph91/pocket-cnn/workflows/check_scripts/badge.svg)](https://github.com/marph91/pocket-cnn/actions?query=workflow%3Acheck_scripts)
[![codecov](https://codecov.io/gh/marph91/pocket-cnn/branch/master/graph/badge.svg)](https://codecov.io/gh/marph91/pocket-cnn)

pocket-cnn is a framework to map small Convolutional Neural Networks (CNN) fully on a FPGA. There is no communication outside the FPGA needed, except of providing the image and reading the result.

## Requirements

For tests:

- ghdl: <https://github.com/ghdl/ghdl>
- vunit: <https://github.com/vunit/vunit>
- onnx: <https://github.com/onnx/onnx>
- gtkwave: <https://github.com/gtkwave/gtkwave> (optional)
- netron: <https://github.com/lutzroeder/netron> (optional)

For synthesis:

- A generated toplevel wrapper and corresponding weight files. See [Installation and Usage](#installation-and-usage).
- A synthesis tool of your choice. For now, the design was synthesized only using Xilinx Vivado.

## Limitations

Before using the framework, you should be aware of several limitations:

- It is not complete. There might be several bugs and things missing. Please open an issue.
- There will be a different accuracy and loss due to the 8 bit quantization.
- Only small CNN can be synthesized, because the weights get mapped to LUT.
- Only a [subset of layers](#supported-layers) is supported.

## Installation and Usage

Before using the framework, the `PYTHONPATH` has to be extended by `path/to/pocket-cnn/code/python_tools`.

A complete end-to-end example can be found at the [example folder](examples/end_to_end/README.md).

To run the tests, simply execute:

```bash
cd code/vhdl/sim/vunit
python3 run_all.py
```

### Supported layers

| Layer | <center>Properties</center> | <center>Limitations</center> |
| :---: | :--- | :--- |
| Convolution | <ul><li>Kernel: 1x1, 2x2, 3x3, 5x5</li><li>Stride: 1, 2, 3</li></ul> | Quantization of the activations and weights: Scale has to be power of two, zero point has to be zero. |
| Maximum Pooling | <ul><li>Kernel: 2x2, 3x3</li><li>Stride: 1, 2, 3</li></ul> | <center>-</center> |
| Global Average Pooling | <center>-</center> | The averaging factor is quantized to the 16 bit fixed point value of `1 / height * width`. |
| Zero Padding | <center>-</center> | The padding has to be the same at each edge. |
| (Leaky) ReLU | <center>-</center> | Leaky ReLU has a fixed alpha of 0.125 |

### Interface

Most of the toplevel generics are describing the CNN architecture and get derived from the ONNX model. In the following table only the most important generics, as well as all signals, are listed. The communication protocol is similar in all submodules of this design.

| <center>Generic/Signal</center> | <center>Datatype</center> | <center>Meaning</center> |
| :--- | :--- | :--- |
| C_PE | Integer | Number of processing elements (PE). A PE consists of one convolution layer and some optional layers. See the documentation folder for more details. |
| C_DATA_TOTAL_BITS | Integer | Bitwidth of the whole design. Currently limited to 8 bit. |
| C_BITWIDTH | Array of integer, C_PE elements | Specific bitwidths for data and weights of each layer. |
| C_IMG_WIDTH_IN | Integer | Width of the input image. |
| C_IMG_HEIGHT_IN | Integer | Height of the input image. |
| C_CH | Array of integer, C_PE+1 elements | Channel of each layer. The first element corresponds to the depth of the input image, i. e. 1 for grayscale and 3 for colored. |
| C_PARALLEL_CH | Array of integer, C_PE elements | Intra channel parallelization for each PE. |
| isl_clk | std_logic | Clock signal. |
| isl_get | std_logic | Signals that the next module is ready to process new data. |
| isl_start | std_logic | Start receiving the image data and process it afterwards. |
| isl_valid | std_logic | Signals valid input data. |
| islv_data | std_logic_vector, C_DATA_TOTAL_BITS bits | Input data. |
| oslv_data | std_logic_vector, C_DATA_TOTAL_BITS bits | Output data. |
| osl_valid | std_logic | Signals valid output data. |
| osl_rdy | std_logic | Signals that the module is ready to process new data. |
| osl_finish | std_logic | Impulse for signalling that the processing of the current image is finshed. Can be used for an interrupt. |

## TODO

Can be found at the [documentation folder](documentation/todo.md) and in the issues.

## History

The tag `weights_in_bram` marks the last commit with:

- Weights and bias stored in BRAM.
- Using DSP for the matrix multiplications.

&rarr; This got deprecated by "Direct Hardware Mapping".

The tag `cocotb_caffe` marks the last commit with:

- Cocotb testbenches.
- Integration of caffe and pytorch.

&rarr; This got deprecated by using VUnit as test runner and ONNX as CNN representation.

## Related work

- Haddoc2: <https://github.com/DreamIP/haddoc2>, <https://arxiv.org/pdf/1712.04322.pdf>
