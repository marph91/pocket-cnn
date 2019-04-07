# Requirements

- GHDL: https://github.com/tgingold/ghdl
- gtkwave
- cocotb: https://github.com/potentialventures/cocotb
- vunit: https://github.com/vunit/vunit

One of:
- Caffe Ristretto: https://github.com/pmgysel/caffe
- Pytorch: https://github.com/pytorch/pytorch

# TODO

- Add usage and documentation.
- Clean up code and folder structure.

## Testing
- Add more unit tests for cocotb and vunit.
- Find a good way to run all cocotb tests with changing generics and summary at the end. See https://github.com/potentialventures/cocotb/issues/756 and https://dornerworks.com/blog/setting-vhdl-generics-fpga-verification-made-easy-cocotb.
- Configure modelsim as second simulator.
- Use jenkins or similar CI.

## HDL
- Handle top.vhd_Xpe better. Currently these files only exists, because of the missing vpi array support of ghdl. See https://github.com/ghdl/ghdl/issues/237.
- Add more layers, f. e. fully connected layer.

## CNN Frameworks
- Fix pytorch saving and loading. The extra layers always have to be in a relative directory when loading the model. Currently the files are duplicated.
- Add tensorflow support. Currently the quantization we need, is not available at this framework. See https://www.tensorflow.org/api_docs/python/tf/quantization/quantize.