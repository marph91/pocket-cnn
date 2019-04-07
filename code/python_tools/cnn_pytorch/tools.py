#!/usr/bin/env python3
import torch
import torchvision
import torchvision.transforms as transforms
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim

import numpy as np

import tools_common as common
import weights2files
import fixfloat

import models
import quant


classes = ("plane", "car", "bird", "cat", "deer", "dog", "frog", "horse",
           "ship", "truck")
# classes = ("adult", "object")


def set_fractional_digits(digits):
    torch.set_printoptions(precision=digits)


def detect_device():
    """set device to cpu/gpu"""
    torch.device("cuda" if torch.cuda.is_available() else "cpu")


def prepare_data():
    transform = transforms.Compose([transforms.Grayscale(),
                                    transforms.Resize((32, 32)),
                                    transforms.ToTensor()])
    # TODO: transform from range [0, 1] to [-1, 1]
    # transform = transforms.Compose(
    #     [transforms.Normalize((0.5, 0.5, 0.5), (0.5, 0.5, 0.5))])

    # cifar10 dataset
    trainset = torchvision.datasets.CIFAR10(
        root="./data", train=True, download=True, transform=transform)
    testset = torchvision.datasets.CIFAR10(
        root="./data", train=False, download=True, transform=transform)

    # FESEQ dataset
    # trainset = torchvision.datasets.ImageFolder("../../../../datasets/FESEQ-807_test1/train", transform=transform)
    # testset = torchvision.datasets.ImageFolder("../../../../datasets/FESEQ-807_test1/test", transform=transform)

    trainloader = torch.utils.data.DataLoader(
        trainset, batch_size=64, shuffle=True, num_workers=2)
    testloader = torch.utils.data.DataLoader(
        testset, batch_size=32, shuffle=False, num_workers=2)
    return trainloader, testloader


def load_model2():
    if pretrained:
        net = torch.load("data/test.pt")
        for param in net.features.parameters():
            param.requires_grad = False
        # TODO: unique layer names to prevent errors
        net.classifier.final_conv = nn.Conv2d(64, len(classes), 1)
    return net


def load_model(path, pretrained=False):
    net = torch.load(path)
    if pretrained:
        for param in net.features.parameters():
            param.requires_grad = False
        # TODO: unique layer names to prevent errors
        net.classifier.final_conv = nn.Conv2d(64, len(classes), 1)
        return net
    return net


def save_model(net, path):
    torch.save(net, path)


def autodetect_device():
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def setup_training(net, pretrained=False):
    """Define a loss function and optimizer."""
    criterion = nn.CrossEntropyLoss()
    if pretrained:
        param = filter(lambda p: p.requires_grad, net.parameters())
    else:
        param = net.parameters()
    # optimizer = optim.SGD(param, lr=0.005, momentum=0.9)
    optimizer = optim.Adam(param, lr=0.001)
    return criterion, optimizer


def train_net(net, trainloader, criterion, optimizer, pretrained=False):
    """Train the network."""
    # TODO: add validation set/metrics
    # https://stackoverflow.com/questions/50207001/pytorch-add-validation-error-in-training
    for epoch in range(10):
        running_loss = 0.0
        for i, data in enumerate(trainloader, 0):
            # get the inputs
            inputs, labels = data

            # zero the parameter gradients
            optimizer.zero_grad()

            # forward + backward + optimize
            outputs = net(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            # print statistics every X mini-batches
            minibatch = 50
            running_loss += loss.item()
            if i % minibatch == minibatch-1:
                print("[{}, {: >4}] loss: {:.3f}".format(
                      epoch + 1, i + 1, running_loss / minibatch))
                running_loss = 0.0

    print("Finished Training")


def test_net(net, testloader):
    """Test the network on the test data."""
    correct = 0
    total = 0
    with torch.no_grad():
        for data in testloader:
            images, labels = data
            outputs = net(images)
            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()

    print("Test accuracy: {} %".format(100 * correct / total))

    class_correct = list(0. for i in range(len(classes)))
    class_total = list(0. for i in range(len(classes)))
    with torch.no_grad():
        for data in testloader:
            images, labels = data
            outputs = net(images)
            _, predicted = torch.max(outputs, 1)
            c = (predicted == labels).squeeze()
            for i in range(4):
                label = labels[i]
                class_correct[label] += c[i].item()
                class_total[label] += 1

    for i in range(len(classes)):
        print("  Class {}: {:.2f} %".format(
            classes[i], 100 * class_correct[i] / class_total[i]))


def preprocess_image(image):
    # scale values down by factor 128 (2**7) from 0...255 to 0...2
    image = image * 2**-7
    # quantize scaled values
    # TODO: why doesnt first quantization layer at model work?
    vf2ff = np.vectorize(fixfloat.float2ffloat, otypes=[float])
    image = vf2ff(image, 3, 5)
    # H x W x C
    image = image[np.newaxis, :]
    # C x H x W
    image = torch.from_numpy(image).float()
    # B x C x H x W, B = 1
    image = image.unsqueeze_(0)
    image = torch.autograd.Variable(image)
    return image


def forward_image(net, image_file):
    """Forward single image and collect data of every activation/module."""
    net.eval()
    activations = []  # list of numpy arrays respectively tensors
    image = common.load_image(image_file, 32, 32, mode="L")
    activations.append(image[np.newaxis, np.newaxis, :])

    image = preprocess_image(image)

    # get activations of each (important) layer
    x = image
    for part in net.children():
        for cnt, l in enumerate(part.children()):
            if len(activations) == 1:
                activations.append(x.data.numpy())
            x = l(x)
            if isinstance(l, (nn.ReLU, nn.MaxPool2d)):
                activations.append(x.data.numpy())
            elif cnt == len(list(part.children()))-1:
                # get next layer to nn.AdaptiveAvgPool2d
                # because its not quantized
                activations.append(x.data.numpy())
                # TODO: calculate softmax properly
                # (maybe best without pytorch module?)
                activations.append(x.data.numpy())
                # activations.append(nn.Softmax(x))
    return activations

if __name__ == "__main__":
    # set mode
    train = True

    # set device to cpu/gpu
    device = autodetect_device()

    # enable/disable transfer learning
    pretrained = False

    if train:
        train, test = prepare_data()
        net = models.Baseline()
        crit, opt = setup_training(net, pretrained=pretrained)
        train_net(net, train, crit, opt)
        # TODO: use net.eval()?
        test_net(net, test)
        save_model(net, "data/train.pt")
    else:
        net = load_model("data/train.pt")
        # print(net)
        a = forward_image(net, "../../../test_images/adam_s_000725.png")

        # test quantized model
        net = load_model("data/quant.pt")
        print(net)
        train, test = prepare_data()
        test_net(net, test)
