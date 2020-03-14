# picoCNN

picoCNN is a framework to map small Convolutional Neural Networks (CNN) fully on a FPGA. There is no communication outside of the FPGA needed, except of providing the image and reading the result.

## Requirements

For tests:

- ghdl: <https://github.com/ghdl/ghdl>
- vunit: <https://github.com/vunit/vunit>
- gtkwave (optional)

For synthesis:

- A generated top_wrapper.vhd and corresponding weight files.
- A synthesis tool of your choice. For now, the design was synthesized only using Xilinx Vivado.

## Installation and Usage

Generate a toplevel template for synthesis, which represents the CNN architecture:

```bash
git clone https://gitlab.com/Marph/picocnn.git
cd picocnn

# create a toplevel module
python3 code/python_tools/vhdl_top_template.py

# synthesize the design with the generated toplevel module
```

To run the tests, simply execute:

```bash
cd picocnn/code/vhdl/sim/vunit/
python3 run_all.py
```

### Supported layers

- Convolution (Kernel: 1x1, 2x2, 3x3, Stride: 1, 2, 3)
- Maximum Pooling (Kernel: 2x2, 3x3, Stride: 1, 2, 3)
- Average Pooling (Quantized averaging factor: 1 / height * width to 16 bit)
- Zero Padding (only same padding at each edge)
- ReLU, Leaky ReLU (only with alpha = 0.125)

## TODO

Can be found at the [documentation folder](documentation/todo.md) or in the issues.

## History

The tag `weights_in_bram` marks the last commit with:

- Weights and bias stored in BRAM.
- Using DSP for the matrix multiplications.

&rarr; This got depracated by "Direct Hardware Mapping".

The tag `cocotb_caffe` marks the last commit with:

- Cocotb testbenches.
- Integration of caffe and pytorch.

&rarr; This got deprecated by using VUnit as test runner and ONNX as CNN representation.
