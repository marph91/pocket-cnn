# Some useful snippets, that can be used around the CNN

## generate test files from test image
./img2bin.py abc.png 32 32 test 4

## get a visualization of the CNN model
/PATH/TO/CAFFE/python/draw_net.py --rankdir TB /PATH/TO/PROTOTXT model.png

## extract files from NVIDIA DIGITS archive and create hierarchy
./untar_digits.py /PATH/TO/TAR/GZ

## format VHDL
./format_vhdl.sh /PATH/TO/VHDL/FILES