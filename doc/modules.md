# Modules

module | purpose | typical location
-|-|-
top_wrapper | generated, definition of the cnn architecture | -
top | toplevel skeleton, contains (multiple) PE and average pooling | -
pe | control all modules of a "layer" | core of the CNN
conv_top | control the convolution operation | at the start of each PE
conv | perform the convolution operation | part of the convolution
mm | perform the matrix multiplication | part of the convolution
max_top | control the maximum pooling operation | after convolution, part of the PE
pool_max | perform a local maximum pooling operation | part of the maximum pooling
window_ctrl | control the stream to window assembly | before convolution and maximum pooling
line_buffer | buffer the incoming stream and assemble it to image lines | part of the window control
window_buffer | buffer the incoming lines and assemble them to windows  | part of the window control
channel_repeater | repeat the channels multiple times | before convolution, part of the window control
relu | perform the rectified linear operation | after convolution
pool_ave | perform a global average pooling operation | at the end of the CNN
zero_pad | pad zeros at the image borders | before convolution, part of the PE
