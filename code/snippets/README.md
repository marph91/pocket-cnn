# generate test files from test image
./img2bin.py

# get a visualization of the CNN model
$CAFFE_RISTRETTO_ROOT/python/draw_net.py --rankdir TB "$MODEL_FULL" "$CNN_DIR/caffe/model.png"

# extract files from NVIDIA DIGITS archive and create hierarchy
"./python_tools/cnn_$CNN_FW/untar_digits.py" "$CNN_DIR/*.tar.gz"

# format VHDL
./format_vhdl.sh