picocnn is a framework to map small Convolutional Neural Networks (CNN) fully on a FPGA. There is no communication outside of the FPGA needed, except of providing the image and reading the result.

# Requirements

For tests:
- ghdl: https://github.com/ghdl/ghdl
- vunit: https://github.com/vunit/vunit
- gtkwave (optional)

For synthesis:
- A generated top_wrapper.vhd and corresponding weight files.
- A synthesis tool of your choice. For now, the design was synthesized only using Xilinx Vivado.

# Installation and Usage

```bash
git clone https://gitlab.com/Marph/picocnn.git
cd picocnn

# TODO: Example for creating top_wrapper.vhd from ONNX model.
# synthesize the design
```

To run the tests (vunit based), execute:
```bash
cd picocnn/code/vhdl/sim/vunit/
python3 run_all.py
```

## Supported layers

- Convolution (Kernel: 1x1, 2x2, 3x3, Stride: 1, 2, 3)
- Maximum Pooling (Kernel: 2x2, 3x3, Stride: 1, 2, 3)
- Average Pooling (Quantized factor: 1 / height * width to 16 bit)
- Zero Padding (only same padding at each edge)
- ReLU, Leaky ReLU (only with alpha = 0.125)

# TODO

- Add more documentation.
- Clean up code and folder structure.

## Testing
- Add more tests.
- Use a second simulator, f. e. modelsim or nvc.
- Use jenkins or similar CI.

## HDL
- Add more layers, f. e. fully connected layer.
- Check if CE is correctly implemented and useful at all. See http://arantxa.ii.uam.es/~ivan/spl12-clock-gating.pdf.

## CNN Frameworks
Add an example, which contains the full workflow:
- Pytorch/Tensorflow/... training
- Exporting to ONNX
- Generating the hardware description with picocnn

# Further notes

The legacy tag `cocotb_caffe` contains:
- Cocotb testbenches.
- Integration of caffe and pytorch without the intermediate representaion in ONNX.