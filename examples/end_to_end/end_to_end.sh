#!/bin/bash

set -e

ROOT=../..

mkdir -p work

echo "# train the CNN"
python3 lenet.py --save-model "work/lenet_mnist.onnx"

echo "# quantizing the model"
python3 "$ROOT"/code/python_tools/cnn_onnx/quantize.py --model-path "work/lenet_mnist.onnx"

echo "# creating a toplevel wrapper"
python3 "$ROOT"/code/python_tools/vhdl_top_template.py \
  --model-path "work/lenet_mnist_quantized.onnx" \
  --weights-path-full "$(pwd)/work/weights" \
  --top-name "work/top_wrapper.vhd"
