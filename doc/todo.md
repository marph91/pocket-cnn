# TODO

- Resolve the TODOs in the source code.
- Add an end to end example of ressource usage and accuracy/loss for one model.
  - Probably Lenet on Mnist would be best suited.
  - Run the created model on a real FPGA.

## Testing

- Fix the failing models, which are commented in `code/vhdl/sim/vunit/top/run.py`.
- Use a second simulator, f. e. modelsim or nvc.
- Add more tests.
- fix "NUMERIC_STD.TO_SIGNED: vector truncated" warnings
- consider generics as namedtuple/dataclass
- onnxruntime:
  - Extend the software inference by onnxruntime. This allows to have another sanity check. Currently INT activations and UINT weigths are not supported, which makes onnxruntime not usable. See also <https://github.com/microsoft/onnxruntime/issues/2964>. A fast check can be done with: `python3 -c 'import onnxruntime as rt; import numpy as np; sess = rt.InferenceSession("cnn_model.onnx"); input_name = sess.get_inputs()[0].name; test = np.ones((1, 1, 6, 6)); pred_onnx = sess.run(None, {input_name: test.astype(np.float32)})[0]; print(pred_onnx)'`.
  - Inspect if the existing tooling is useful: <https://github.com/microsoft/onnxruntime/blob/master/onnxruntime/python/tools/quantization/README.md>

## HDL

- Provide some more interfaces for the toplevel, for example AXI (Lite).
- Document the communication protocol (get, rdy, valid).
  - timing diagram
  - document the stream format (ch > w > h)
  - Consider using fixed latencies instead.
- Add more layers:
  - fully connected layer
  - fire layer (squeezenet)
  - flatten
  - 2x2 avg pool (local, global)
  - softmax
  - tanh activation
  - batchnorm
  - stem, inception, resnet
- figure out if/how "bigger" nets could be synthesized, like lenet/squeezenet/mobilenet
- Evaluate whether CE is needed. See <http://arantxa.ii.uam.es/~ivan/spl12-clock-gating.pdf>.
- document used and possibly useful parallelism:
  - inter kernel parallelism &rarr; not possible, because kernel have to be applied pixel by pixel
  - inter layer parallelism &rarr; implemented as a pipeline
  - inter output parallelism &rarr; not implemented; apply multiple kernel to the same roi; would require large bram bandwidths for line buffer
  - intra kernel parallelism &rarr; implemented; parametrize parallel channels (C_PARALLEL_CH=1 &rarr; all multiplications of one channel get calculated at once, C_PARALLEL_CH=C_CH &rarr; all multiplications of the kernel, i. e. all channels, get calculated at once)
- consider redesign of the toplevel generics, requirements:
  - readability (layerwise structure?)
  - compatibility to json for vunit tests
  - compatibility to vhdl wrapper for synth
- Synthesize the design with an open source toolchain (ghdl + ghdlsynth + yosys + nextpnr + icestorm).
  - Fixed point package and multidimensional arrays are not yet supported by ghdl synthesis.
  - See also: <https://github.com/ghdl/ghdl/issues/1159>

## CNN Frameworks

- Add an example, which contains the full workflow:
  - Pytorch/Tensorflow/... training
  - Exporting to ONNX
  - Modifying/quantizing the model according to the HDL requirements
  - Generating the hardware description with pocket-cnn
- Add a script, which converts an arbitrary ONNX model to an quantized ONNX model, which can be synthesized:
  - Document the requirements/limitations:
    - bitwidth/scale: limit to 2^x values or extend vhdl framework?
    - add support of offset?

## Documentation

### History

The tag `weights_in_bram` marks the last commit with:

- Weights and bias stored in BRAM.
- Using DSP for the matrix multiplications.

&rarr; This got deprecated by "Direct Hardware Mapping".

The tag `cocotb_caffe` marks the last commit with:

- Cocotb testbenches.
- Integration of caffe and pytorch.

&rarr; This got deprecated by using VUnit as test runner and ONNX as CNN representation.
