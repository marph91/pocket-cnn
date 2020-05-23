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

| Layer | Properties | Limitations |
| :---: | :--- | :--- |
| Convolution | <ul><li>Kernel: 1x1, 2x2, 3x3, 5x5</li><li>Stride: 1, 2, 3</li></ul> | Quantization of the activations and weights: Scale has to be power of two, zero point has to be zero. |
| Maximum Pooling | <ul><li>Kernel: 2x2, 3x3</li><li>Stride: 1, 2, 3</li></ul> | - |
| Global Average Pooling | - | The averaging factor is quantized to the 16 bit fixed point value of `1 / height * width`. |
| Zero Padding | - | The padding has to be the same at each edge. |
| (Leaky) ReLU | - | Leaky ReLU has a fixed alpha of 0.125 |

### Interface

Most of the toplevel generics are describing the CNN architecture. They get derived from the ONNX model and don't need to be specified manually by the user. A table, containing the most important toplevel generics and signals, can be found [here](doc/toplevel_interface.md). The communication protocol is similar in all submodules of this design.

## Architecture

pocket-cnn accepts ONNX models as input. Each convolution layer of the CNN gets converted to a processing element (PE). This is the central element of the hardware design.
The convolution in a PE can be preceeded by *zero padding* and followed by *ReLU* and/or *maximum pooling*. See also [pe.vhd](code/vhdl/src/pe.vhd). Below are a few common configurations.

![processing_element](doc/images/processing_element.svg)

The python framework takes care of converting the ONNX model into the VHDL representation. The VHDL toplevel can be found at [top.vhd](code/vhdl/src/top.vhd). The toplevel structure is illustrated in the following image.

![toplevel](doc/images/toplevel.svg)

More details about the specific modules can be found [here](doc/modules.md).

## TODO

Can be found at the [documentation folder](doc/todo.md) and in the issues.

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
