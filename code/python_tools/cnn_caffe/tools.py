#!/usr/bin/env python3
import argparse
import os
import time

import numpy as np

from fixfloat import float2fixed, float2pow2
import tools_common as common

from google.protobuf import text_format
common.set_log_level(3)
import caffe
from caffe import layers as L
from caffe.proto import caffe_pb2


def load_net(deploy_file):
    net = caffe.proto.caffe_pb2.NetParameter()
    with open(deploy_file) as infile:
        text_format.Merge(infile.read(), net)
    return net


def get_net(caffemodel, deploy_file, use_gpu=False):
    """
    Returns an instance of caffe.Net

    Arguments:
    caffemodel -- path to a .caffemodel file
    deploy_file -- path to a .prototxt file

    Keyword arguments:
    use_gpu -- if True, use the GPU for inference
    """
    if use_gpu is True:
        caffe.set_mode_gpu()
    else:
        caffe.set_mode_cpu()

    # load a new model
    return caffe.Net(deploy_file, caffemodel, caffe.TEST)


def deploy_filename(train_file):
    """Create filename of deploy file based on filename of train file."""
    train = train_file.rsplit(".", 1)
    return train[0] + "_deploy." + train[1]


def train2deploy(train_file, deploy_file):
    """convert training architecture to deploy architecture
    input: quantized model (training)
    output: quantized model (deploy)
    note: https://github.com/BVLC/caffe/wiki/Using-a-Trained-Network:-Deploy
    """
    # pylint: disable=E1101
    # open train.prototxt file and parse parameter
    # TODO: easier with flag TEST?
    net = caffe_pb2.NetParameter()
    with open(train_file) as infile:
        text_format.Merge(infile.read(), net)

    lay = net.layer

    # replace first layer with data layer (== input)
    dims = lay[0].input_param.shape[0]
    lay[0].CopyFrom(
        L.Input(input_param={"shape": dims}).to_proto().layer[0])
    lay[0].name = "data"
    lay[0].top[0] = "data"

    # check every layer
    i = 1
    while True:
        try:
            if lay[i].type == "Power":
                pass
            elif lay[i].type == "ConvolutionRistretto":
                # keep bit and frac width for average pooling and leaky relu
                bitwidth_tmp = lay[i].quantization_param.bw_layer_in
                fracwidth_tmp = lay[i].quantization_param.fl_layer_out
            elif (lay[i].type == "ReLU" or
                  lay[i].type == "Python" and
                  lay[i].python_param.layer == "QuantizedRelu"):
                if lay[i].relu_param.negative_slope:
                    slope_tmp = lay[i].relu_param.negative_slope
                    print("Warning: replacing leaky relu with "
                          "quantized leaky relu")
                    lay[i].type = "Python"
                    lay[i].python_param.module = "cnn_caffe.custom_layers"
                    lay[i].python_param.layer = "QuantizedRelu"
                    str_tmp = "{'negative_slope': %f, 'bw_layer': %d, 'fl_layer': %d}" % (slope_tmp, bitwidth_tmp, fracwidth_tmp)
                    lay[i].python_param.param_str = str_tmp
            elif (lay[i].type == "Pooling" or
                  lay[i].type == "Python" and
                  lay[i].python_param.layer ==
                  "QuantizedAveragePooling"):
                if lay[i].pooling_param.pool == 1:
                    # pooling_param.pool: 0 - max, 1 average
                    print("Warning: replacing average pooling with "
                          "quantized average pooling")
                    lay[i].type = "Python"
                    lay[i].python_param.module = "cnn_caffe.custom_layers"
                    lay[i].python_param.layer = "QuantizedAveragePooling"
                    str_tmp = "{'bw_layer': %d, 'fl_layer': %d}" %\
                        (bitwidth_tmp, fracwidth_tmp)
                    lay[i].python_param.param_str = str_tmp
            elif lay[i].type == "Convolution":
                print("Warning: net isn't quantized")
            else:
                del lay[i]
                i -= 1
            i += 1
        except IndexError:
            break

    # add softmax layer (== output)
    new_layer = lay.add()
    new_layer.CopyFrom(L.Softmax().to_proto().layer[0])
    new_layer.name = "softmax"
    new_layer.top[0] = "softmax"
    new_layer.bottom.append(lay[i-1].name)

    with open(deploy_file, "w") as outfile:
        outfile.write(str(net))


def get_transformer(deploy_file, mean_file=None):
    """
    Returns an instance of caffe.io.Transformer

    Arguments:
    deploy_file -- path to a .prototxt file

    Keyword arguments:
    mean_file -- path to a .binaryproto file (optional)
    """
    # pylint: disable=E1101
    net = load_net(deploy_file)

    if net.input_shape:
        dims = net.input_shape[0].dim
    else:
        dims = net.layer[0].input_param.shape[0].dim

    # transpose to (channels, height, width)
    transform = caffe.io.Transformer(inputs={"data": dims})
    transform.set_transpose("data", (2, 0, 1))

    if dims[1] == 3:
        # channel swap for colored images
        transform.set_channel_swap("data", (2, 1, 0))

    if mean_file:
        # set mean pixel
        with open(mean_file, "rb") as infile:
            # pylint: disable=E1101
            blob = caffe.proto.caffe_pb2.BlobProto()
            blob.MergeFromString(infile.read())
            if blob.HasField("shape"):
                blob_dims = blob.shape
            elif blob.HasField("num") and blob.HasField("channels") and \
                    blob.HasField("height") and blob.HasField("width"):
                blob_dims = (blob.num, blob.channels, blob.height, blob.width)
            else:
                raise ValueError("Blob doesn't provide shape or 4d dimensions")
            pixel = np.reshape(blob.data, blob_dims[1:]).mean(1).mean(1)
            transform.set_mean("data", pixel)
    return transform


def forward_pass(images, net, transformer, deploy_file, batch_size=1,
                 out_layer=None, use_gpu=False):
    """
    Returns scores for each image as an np.ndarray (nImages x nClasses)

    Arguments:
    images -- a list of np.ndarrays
    net -- a caffe.Net
    transformer -- a caffe.io.Transformer

    Keyword arguments:
    batch_size -- how many images can be processed at once
        (a high value may result in out-of-memory errors)
    """
    if use_gpu is True:
        caffe.set_mode_gpu()
    else:
        caffe.set_mode_cpu()

    caffe_images = []
    for image in images:
        if image.ndim == 2:
            caffe_images.append(image[:, :, np.newaxis])
        else:
            caffe_images.append(image)

    dims = transformer.inputs["data"][1:]

    scores = None
    for chunk in [caffe_images[x:x + batch_size]
                  for x in range(0, len(caffe_images), batch_size)]:
        new_shape = (len(chunk),) + tuple(dims)
        if net.blobs["data"].data.shape != new_shape:
            net.blobs["data"].reshape(*new_shape)
        for index, image in enumerate(chunk):
            image_data = transformer.preprocess("data", image).astype(int)
            net.blobs["data"].data[index] = image_data

        start = time.time()
        net.forward()
        end = time.time()

        if out_layer is None:
            out_layer = net.blobs.keys()[-1]
            output = net.blobs[out_layer].data
        elif out_layer == "all":
            output = [net.blobs[l].data for l in net.blobs.keys()]
        else:
            output = net.blobs[out_layer].data

        if out_layer == "all":
            scores = output
        else:
            if scores is None:
                scores = np.copy(output)
            else:
                scores = np.vstack((scores, output))
    return scores, end-start


def read_labels(labels_file):
    """Returns a list of strings.
    """
    if not labels_file:
        print("WARNING: No labels file provided. Results will be difficult to "
              "interpret.")
        return None

    labels = []
    with open(labels_file) as infile:
        for line in infile:
            label = line.strip()
            if label:
                labels.append(label)
    return labels


def classify(caffemodel, deploy_file, image_files, mean_file=None,
             labels_file=None, batch_size=None, use_gpu=True):
    """Classify images against with a caffe model and print the results.
    """
    # load the model and images
    net = get_net(caffemodel, deploy_file, use_gpu)
    transformer = get_transformer(deploy_file, mean_file)
    _, channels, height, width = transformer.inputs["data"]
    if channels == 3:
        mode = "RGB"
    elif channels == 1:
        mode = "L"
    else:
        raise ValueError("Invalid number for channels: %s" % channels)
    images = [common.load_image(image_file, height, width, mode)
              for image_file in image_files]
    labels = read_labels(labels_file)

    # classify the images
    scores, forward_time = forward_pass(
        images, net, transformer, deploy_file, batch_size=batch_size,
        use_gpu=use_gpu)

    # for global average pooling architecture
    if len(scores.shape) == 4:
        scores = scores[:, :, 0, 0]

    # process the results
    indices = (-scores).argsort()[:, :5]  # take top 5 results
    classifications = []
    for image_index, index_list in enumerate(indices):
        result = []
        for i in index_list:
            # "i" is a category in labels and also an index into scores
            if labels is None:
                label = "Class #%s" % i
            else:
                label = labels[i]
            result.append((label, round(100.0 * scores[image_index, i], 4)))
        classifications.append(result)

    print("Caffe took {} seconds to forward the image.".format(forward_time))

    for index, classification in enumerate(classifications):
        print("{:-^80}".format(" Prediction for " + str(image_files[index])))
        for label, confidence in classification:
            print('{:9.4%} - "{}"'.format(confidence / 100.0, label))


def classify_many(caffemodel, deploy_file, image_files, mean_file=None,
                  batch_size=None, use_gpu=False):
    """Classify images against a Caffe model to get a mean execution time."""
    # Load the model and images
    net = get_net(caffemodel, deploy_file, use_gpu)
    transformer = get_transformer(deploy_file, mean_file)
    _, channels, height, width = transformer.inputs["data"]
    if channels == 3:
        mode = "RGB"
    elif channels == 1:
        mode = "L"
    else:
        raise ValueError("Invalid number for channels: %s" % channels)
    images = [common.load_image(image_file, height, width, mode)
              for image_file in image_files]

    # Classify the images and take the time
    total_time = 0
    for image in images:
        _, forward_time = forward_pass(
            [image], net, transformer, deploy_file, batch_size=batch_size,
            use_gpu=use_gpu)
        total_time += forward_time

    print("Caffe took {} seconds to forward {} images. Avg: {} s/Image".format(
        total_time, len(image_files), total_time/len(image_files)))

if __name__ == "__main__":
    # pylint: disable=C0103
    parser = argparse.ArgumentParser(description="Classification with DIGITS")

    parser.add_argument("mode", type=int, help="Which programs to execute")
    parser.add_argument("caffemodel", help="Path to a .caffemodel")
    parser.add_argument("deploy_file", help="Path to the deploy file")

    parser.add_argument("-i", "--image", nargs="+", help="Path[s] to an image")
    parser.add_argument("-m", "--mean", help="Path to a mean file (*.npy)")
    parser.add_argument("-l", "--labels", help="Path to a labels file")
    parser.add_argument("--batch-size", type=int)
    parser.add_argument("--use_gpu", type=bool, help="Use the GPU")
    parser.add_argument(
        "--mem_init", type=str, help="Output directory of weights")

    args = parser.parse_args()

    if args.mode == 1:
        print("no mode 1. use get_params.py")

    if args.mode == 0 or args.mode == 2:
        classify(
            args.caffemodel,
            args.deploy_file,
            args.image,
            args.mean,
            args.labels,
            args.batch_size,
            args.use_gpu
        )

    if args.mode == 3:
        classify_many(
            args.caffemodel,
            args.deploy_file,
            args.image,
            args.mean,
            args.batch_size,
            args.use_gpu
        )
