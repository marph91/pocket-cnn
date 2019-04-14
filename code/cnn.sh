#!/bin/bash

# export CAFFE_ROOT=/home/Programme/caffe-ristretto
# export PYTHONPATH=/home/Programme/caffe-ristretto/python
# export PYTHONPATH=~/workspace/opencnn/code/python_tools

# disabled to detect errors early
# export PYTHONDONTWRITEBYTECODE=1

source cnn.config

# finds latest file that matches pattern $1
function find_latest {
	unset -v latest
	for file in $1; do
		[[ $file -nt $latest ]] && latest="$file"
	done
}

if ((GPU == 1)); then
	PRE=optirun
	GPU_NR=--gpu=0
else
	PRE=""
	GPU_NR=""
fi

# TODO: should this be moved to the config?
if [ "$CNN_FW" = "caffe" ]; then
	# TODO: run caffe(-ristretto) training from python script
	# https://stackoverflow.com/questions/32379878/cheat-sheet-for-caffe-pycaffe
	# would simplify first workflow steps
	# full precision
	MODEL_FULL="$DIR/caffe/train_val.prototxt"
	find_latest "$DIR/caffe/*.caffemodel"
	WEIGHTS_FULL="$latest"
	# quantized
	MODEL_QUANT="$DIR/caffe_ristretto/ristretto_quantized.prototxt"
	SOLVER_QUANT="$DIR/caffe_ristretto/ristretto_solver.prototxt"
	find_latest "$DIR/caffe_ristretto/finetune/*.caffemodel"
	WEIGHTS_QUANT="$latest"
elif [ "$CNN_FW" = "pytorch" ]; then
	# full precision
	MODEL_FULL="$DIR/pytorch/train.pt"
	WEIGHTS_FULL="$DIR/pytorch/train.pt"
	# quantized
	MODEL_QUANT="$DIR/pytorch/quant.pt"
	SOLVER_QUANT="$DIR/pytorch/quant.pt"
	WEIGHTS_QUANT="$DIR/pytorch/quant.pt"
fi
printf "\\nFramework: %s\\n\\n" "$CNN_FW"


# overriding patterns is intended to select multiple cases via fallthrough
# shellcheck disable=SC2221,SC2222
case $1 in
	# train CNN from prototxt, solver and dataset
	1a) echo "train CNN
		tool: caffe
		input: model, (solver), dataset
		output: weights
		note: to be implemented -> train manually" ;;

	1b) echo "extract files from archive and create hierarchy
		tool: custom python script
		input: DIGITS tar archive
		output: folder hierarchy with files"
		"./python_tools/cnn_$CNN_FW/untar_digits.py" "$DIR/*.tar.gz" ;;

	# quantize prototxt model -> recommendation -> modify on own needs
	2a) echo "quantize prototxt
		tool: caffe ristretto
		input: model, weights, trimming mode, error
		output: quantized model" 
		if [ ! -f "$MODEL_FULL" ]; then
			echo "Error: model file isnt valid!"
			exit 1
		fi
		# check if weights file exists
		if [ ! -f "$WEIGHTS_FULL" ]; then
			echo "Error: weights file isnt valid!"
			exit 1
		fi
		mkdir -p "$DIR/caffe_ristretto"
		"$PRE $CAFFE_RISTRETTO_ROOT/build/tools/ristretto" quantize \
			--model="$MODEL_FULL" \
			--weights="$WEIGHTS_FULL" \
			--model_quantized="$MODEL_QUANT" \
			--trimming_mode=dynamic_fixed_point "$GPU_NR" --iterations=2000 \
			--error_margin=5 ;;

	# sanity check of quantized prototxt == run steps 3 and 4 -> prevent time consuming step 2b with invalid model
	2a_check) echo "sanity check of quantized prototxt
		tool: custom python script
		input: quantized model (train)
		output: Warnings/hints"
		"./python_tools/cnn_$CNN_FW/parse_param.py" \
			"$MODEL_QUANT" \
			"$DIR/caffe_ristretto/mem_init" \
			"$VHDL_DIR/src/cnn_parameter.vhd" ;;

	# finetune 32 bit float model to configured fixed point representation
	2b) echo "quantize weights
		tool: caffe ristretto
		input: quantized model, weights, (solver)
		output: quantized weights
		note: solver file with default parameter generated"
		if ((GPU == 0)); then
			echo "Warning: net should be trained with GPU acceleration"
		fi
		if [ ! -f "$MODEL_QUANT" ]; then
			echo "Error: quantized model file isnt valid!"
			exit 1
		fi
		# check if weights file exists
		if [ ! -f "$WEIGHTS_FULL" ]; then
			echo "Error: weights file isnt valid!"
			exit 1
		fi
		mkdir -p "$DIR/caffe_ristretto/finetune"
		"./python_tools/cnn_$CNN_FW/create_solver.py" \
			"$DIR/caffe_ristretto/finetune/quantized" \
			"$MODEL_QUANT" \
			"$SOLVER_QUANT" \
			--fixed 1 --use_gpu "$GPU"
		$PRE "$CAFFE_RISTRETTO_ROOT/build/tools/caffe" train \
			--solver="$SOLVER_QUANT" \
			--weights="$WEIGHTS_FULL" \
			"$GPU_NR" ;;

	# benchmark finetuned model
	2b_benchmark) echo "benchmark quantized model and weights
		tool: caffe ristretto
		input: quantized model and weights
		output: accuracy" 
		$PRE "$CAFFE_RISTRETTO_ROOT/build/tools/caffe" test \
			--model="$MODEL_QUANT" \
			--weights="$WEIGHTS_QUANT" \
			"$GPU_NR" --iterations=2000 ;;

	# extract weights from net for usage in vhdl model
	3 | all) echo "extract weights from net
		tool: custom python script
		input: (quantized) model and weights
		output: one file per conv layer with binary weights"
		$PRE "./python_tools/cnn_$CNN_FW/convert_weights.py" \
			"$WEIGHTS_QUANT" \
			"$MODEL_QUANT" \
			--mem_init "$DIR/caffe_ristretto/mem_init" ;;&

	# generate toplevel from quantized net architecture
	4 | all) echo "generate toplevel parameters from net architecture
		tool: custom python script
		input: quantized model, binary weight files directory
		output: VHDL toplevel"
		if [ "$1" = "4" ]; then
			# just ask for input in manual mode
			read -r -p "This step will overwrite the current parameter file! Continue? [y/N] " response
		else
			response="y"
		fi
		case "$response" in
		[yY][eE][sS]|[yY])
			"./python_tools/cnn_$CNN_FW/parse_param.py" \
				"$MODEL_QUANT" \
				"$DIR/caffe_ristretto/mem_init" \
				"$VHDL_DIR/cnn_parameter.vhd" ;;
		*) ;;
		esac ;;&

	# cosimulation of finetuned model
	5 | all) echo "simulate VHDL CNN and compare with Caffe results
		tool: cocotb (testbench), ghdl (simulator) and caffe (reference values)
		input: python testbench, VHDL (code + toplevel), reference model and weights, (input image)
		output: verification of VHDL design"
		cd "$PWD/VHDL/sim/cocotb/top" || exit 1
		$PRE make -s \
			VHDL_DIR="$VHDL_DIR" \
			CNN_FW="$CNN_FW" \
			COCOTB_ROOT="$COCOTB_ROOT" \
			GPU="$GPU" \
			DEBUG="$DEBUG" \
			TB_ROOT="$PWD" \
			TEST_FILES="$TEST_FILES" \
			MODEL_QUANT="$MODEL_QUANT" \
			WEIGHTS_QUANT="$WEIGHTS_QUANT" ;;

	# display results
	6) echo "display results
		tool: octave, vivado, gtkwave, debug textfile" ;;

	# generate test files from test image
	test_img) echo "generate test files from test image
		tool: custom python script
		input: test image
		output: binary test image, image text and debug files"
		if [ -z "$3" ]; then
			echo "Please specify input image"
		else
			./python_tools/img2bin.py "$3" "$DIR"
		fi ;;

	draw) echo "print model to file
		tool: caffe
		input: model
		output: picture of model structure"
		$CAFFE_RISTRETTO_ROOT/python/draw_net.py --rankdir TB "$MODEL_FULL" "$DIR/caffe/model.png" ;;


	-h | --help) echo "Workflow:
		1a           - train CNN
		1b           - extract files from archive and create hierarchy
		2a           - quantize prototxt
		2a_check     - sanity check of quantized prototxt
		2b           - quantize weights
		2b_benchmark - benchmark quantized model and weights
		3a           - generate deploy.prototxt
		3b           - extract weights from caffemodel
		4            - generate toplevel parameters from prototxt
		5            - simulate VHDL CNN and compare with Caffe results
		6            - display results
		all          - perform all necessary steps from generating deploy.prototxt to simulation
		test_img     - generate test files from test image
		draw         - print model to file" ;;
esac