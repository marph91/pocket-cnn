# End-to-end example from training a CNN to getting the VHDL toplevel wrapper

## Workflow

1. Set the pythonpath: `export PYTHONPATH=/path/to/pocket-cnn/code/python_tools`

2. Choose a framework of your choice to train the CNN. In this example, **Pytorch** is used, because it has built in ONNX export. A list of available frameworks can be found at <https://github.com/onnx/tutorials>.

3. Install the python modules numpy, onnx and fpbinary.

4. Clone the repository: `git clone git@github.com:marph91/pocket-cnn.git`

5. Run the script: `cd pocket-cnn/examples/end_to_end && ./end_to_end.sh`
The script executes the following steps:

   - Train a CNN and save it in ONNX format. The model is an adapted Lenet, which is trained on the MNIST dataset. Example training results are an accuracy of 91% and a loss of 0.3253 on the test images.
   - Quantize the exported ONNX model.
   - Create a synthesizable toplevel wrapper and corresponding weights files from the ONNX model.

6. Import the generated VHDL toplevel file (`examples/end_to_end/work/top_wrapper.vhd`) in the project, like the other sources from `code/vhdl/src`. Make sure the weights path is set correctly and the weights files don't get moved later.

7. Synthesize with a tool of your choice. Right now it was only tested with Xilinx Vivado.
