picocnn is a framework to map small Convolutional Neural Networks (CNN) fully on a FPGA.

# Approach

The full CNN is mapped to hardware. There is no communication outside of the FPGA needed. It is similar to the Direct Hardware Mapping approach of https://github.com/DreamIP/haddoc2.

# Requirements

For tests:
- ghdl: https://github.com/ghdl/ghdl
- vunit: https://github.com/vunit/vunit
- gtkwave (optional)
- cocotb (only until commit 05fa2417): https://github.com/potentialventures/cocotb

To train new models, one of:
- Caffe Ristretto: https://github.com/pmgysel/caffe
- Pytorch: https://github.com/pytorch/pytorch

For synthesis:
- A generated top_wrapper.vhd and corresponding weight files.
- A synthesis tool of your choice. For now, the design was synthesized only using Xilinx Vivado.

# Installation and Usage

```bash
# install requirements
git clone https://gitlab.com/Marph/picocnn.git
export PYTHONPATH="$PWD"picocnn/code/python_tools:/PATH/TO/CAFFE/RISTRETTO/python
export CAFFE_ROOT=/PATH/TO/CAFFE/RISTRETTO
cd picocnn

cp cnn_config.sh.example cnn_config.sh
# edit your cnn_config.sh
./cnn.sh all
```

To run the vunit based tests, execute:
```bash
cd picocnn/code/vhdl/sim/vunit/
python3 run_all.py
```
Further cocotb based tests can be found in the folder `cocotb` and run by executing `make` in the corresponding subdirectory.

# TODO

- Add more documentation.
- Clean up code and folder structure.

## Testing
- Fix numerical errors when inferring the CNN with CPU. GPU inference yields bit accurate results. Maybe related to https://groups.google.com/forum/#!searchin/caffe-users/cpu$20gpu$20difference|sort:date/caffe-users/zwCmin767SE/tz4C8pPpBAAJ.
- Add more unit tests for cocotb and vunit.
- Find a good way to run all cocotb tests with changing generics and summary at the end. Probably a similar implementation like at cocotb repository (cocotb/Makefile) is the best solution. See https://github.com/potentialventures/cocotb/issues/756 and https://dornerworks.com/blog/setting-vhdl-generics-fpga-verification-made-easy-cocotb.
- Use a second simulator, f. e. modelsim or nvc.
- Use jenkins or similar CI.

## HDL
- Handle top.vhd_Xpe better. Currently these files only exists, because of the missing vpi array support of ghdl. See https://github.com/ghdl/ghdl/issues/237.
- Add more layers, f. e. fully connected layer.
- Check if CE is correctly implemented and useful at all. See http://arantxa.ii.uam.es/~ivan/spl12-clock-gating.pdf.

## CNN Frameworks
- Fix pytorch saving and loading. The extra layers always have to be in a relative directory when loading the model due to pickle. See https://pytorch.org/docs/stable/notes/serialization.html. Currently the files are duplicated.
- Improve pytorch and caffe tooling. Currently there are many absolute paths and duplicated code.
- Add tensorflow support. Currently the quantization we need, is not available at this framework. See https://www.tensorflow.org/api_docs/python/tf/quantization/quantize.