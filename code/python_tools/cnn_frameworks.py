import os

# caffe
try:
    import cnn_caffe.tools
    import cnn_caffe.parse_param
except ImportError:
    print("No caffe detected.")

# pytorch
try:
    import cnn_pytorch.tools
    import cnn_pytorch.parse_param
except ImportError:
    print("No pytorch detected.")

import tools_common as common


class CnnBase:
    def __init__(self):
        self.deploy_file = self.get_deploy(os.environ["MODEL_QUANT"])
        self.weights = os.environ["WEIGHTS_QUANT"]
        self.use_gpu = bool(int(os.environ["GPU"]))
        self.param = None

    def parse_bitwidths(self):
        """Getting list of bitwidths out of deploy_file, because VHDL bitwidth
        array isn't accessable.
        """
        bw = self.param["bitwidth"]
        maxpool = self.param["pool_kernel"]
        bitwidths = []
        bitwidths.append([bw[0][0], 0])  # toplevel
        bitwidths.append([bw[0][0] - bw[0][1], bw[0][1]])  # prepr
        for x in range(len(bw)):
            bitwidths.append([bw[x][0] - bw[x][2], bw[x][2]])
            if maxpool[x] != 0:
                bitwidths.append(bitwidths[-1])
        bitwidths.append(bitwidths[-1])  # average pool
        return bitwidths

    def inference(self, image, width, height):
        """Forward image through cnn and return output for each layer.
        """
        pass

    def get_deploy(self, filename):
        return filename


class Caffe(CnnBase):
    def parse_bitwidths(self):
        self.param = cnn_caffe.parse_param.parse_param(self.deploy_file)
        return super().parse_bitwidths()

    def inference(self, image, width, height):
        images = [common.load_image(image, width, height, mode="L")]
        net = cnn_caffe.tools.get_net(self.weights, self.deploy_file, use_gpu=self.use_gpu)
        trafo = cnn_caffe.tools.get_transformer(self.deploy_file, None)
        result, _ = cnn_caffe.tools.forward_pass(
            images, net, trafo, self.deploy_file, out_layer="all", use_gpu=self.use_gpu)
        return result

    def get_deploy(self, filename):
        return cnn_caffe.tools.deploy_filename(filename)


class Pytorch(CnnBase):
    def parse_bitwidths(self):
        self.param = cnn_pytorch.parse_param.parse_param(self.deploy_file)
        return super().parse_bitwidths()

    def inference(self, image, width, height):
        net = cnn_pytorch.tools.load_model(self.deploy_file)
        # TODO: would manual gpu flag be useful?
        # use_gpu = bool(int(os.environ["GPU"]))
        net.eval()
        result = cnn_pytorch.tools.forward_image(net, image)
        return result
