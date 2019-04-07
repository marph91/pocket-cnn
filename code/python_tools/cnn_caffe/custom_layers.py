import numpy as np
import caffe
import fixfloat


class QuantizedRelu(caffe.Layer):
    """Compute quantized leaky ReLU."""
    def setup(self, bottom, top):
        params = eval(self.param_str)
        self.negative_slope = params["negative_slope"]
        self.int_bits = params["bw_layer"] - params["fl_layer"]
        self.frac_bits = params["fl_layer"]

    def reshape(self, bottom, top):
        top[0].reshape(*bottom[0].shape)

    def forward(self, bottom, top):
        vf2ff = np.vectorize(fixfloat.float2ffloat, otypes=[float])
        top[0].data[...] = np.where(
            bottom[0].data < 0, vf2ff(bottom[0].data * self.negative_slope,
                                      self.int_bits, self.frac_bits),
            bottom[0].data)

    def backward(self, bottom, propagate_down, top):
        pass


class QuantizedAveragePooling(caffe.Layer):
    """Compute quantized average pooling."""
    def setup(self, bottom, top):
        params = eval(self.param_str)
        self.int_bits = params["bw_layer"] - params["fl_layer"]
        self.frac_bits = params["fl_layer"]

    def reshape(self, bottom, top):
        top[0].reshape(*[bottom[0].shape[0], bottom[0].shape[1], 1, 1])

    def forward(self, bottom, top):
        top[0].data[...] = self.quantized_average(bottom[0].data)

    def backward(self, bottom, propagate_down, top):
        pass

    def quantized_average(self, array_in):
        # input: array, output: scalar
        reciprocal = fixfloat.float2ffloat(
            1./(array_in.shape[2] * array_in.shape[3]), 1, 16)
        array_out = np.empty([array_in.shape[0], array_in.shape[1], 1, 1])
        for batch in range(array_in.shape[0]):
            for axis in range(array_in.shape[1]):
                array_out[batch, axis, 0, 0] = fixfloat.float2ffloat(
                    np.sum(array_in[batch][axis][:][:]) * reciprocal,
                    self.int_bits, self.frac_bits)
        return array_out
