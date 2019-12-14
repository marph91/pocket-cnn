#!/bin/bash

source cnn_config.sh
printf "\\nFramework: %s\\n\\n" "$CNN_FW"

# overriding patterns is intended to select multiple cases via fallthrough
# shellcheck disable=SC2221,SC2222
case $1 in
	# quantize prototxt model -> recommendation -> modify on own needs
	quantize_model) echo "quantize prototxt
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
		mkdir -p "$CNN_DIR/caffe_ristretto"
		"$PRE $CAFFE_RISTRETTO_ROOT/build/tools/ristretto" quantize \
			--model="$MODEL_FULL" \
			--weights="$WEIGHTS_FULL" \
			--model_quantized="$MODEL_QUANT" \
			--trimming_mode=dynamic_fixed_point "$GPU_NR" --iterations=2000 \
			--error_margin=5 ;;

	# sanity check of quantized prototxt == run steps 3 and 4 -> prevent time consuming step 2b with invalid model
	quantize_check) echo "sanity check of quantized prototxt
		tool: custom python script
		input: quantized model (train)
		output: Warnings/hints"
		"./python_tools/cnn_$CNN_FW/parse_param.py" \
			"$MODEL_QUANT" \
			"$CNN_DIR/caffe_ristretto/mem_init" \
			"$VHDL_DIR/src/top_wrapper.vhd" ;;

	# finetune 32 bit float model to configured fixed point representation
	quantize_weights) echo "quantize weights
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
		mkdir -p "$CNN_DIR/caffe_ristretto/finetune"
		"./python_tools/cnn_$CNN_FW/create_solver.py" \
			"$CNN_DIR/caffe_ristretto/finetune/quantized" \
			"$MODEL_QUANT" \
			"$SOLVER_QUANT" \
			--fixed 1 --use_gpu "$GPU"
		$PRE "$CAFFE_RISTRETTO_ROOT/build/tools/caffe" train \
			--solver="$SOLVER_QUANT" \
			--weights="$WEIGHTS_FULL" \
			"$GPU_NR" ;;

	# benchmark finetuned model
	benchmark) echo "benchmark quantized model and weights
		tool: caffe ristretto
		input: quantized model and weights
		output: accuracy" 
		$PRE "$CAFFE_RISTRETTO_ROOT/build/tools/caffe" test \
			--model="$MODEL_QUANT" \
			--weights="$WEIGHTS_QUANT" \
			"$GPU_NR" --iterations=2000 ;;

	# extract weights from net for usage in vhdl model
	extract | all) echo "extract weights from net
		tool: custom python script
		input: (quantized) model and weights
		output: one file per conv layer with binary weights"
		$PRE "./python_tools/cnn_$CNN_FW/convert_weights.py" \
			"$WEIGHTS_QUANT" \
			"$MODEL_QUANT" \
			--mem_init "$CNN_DIR/caffe_ristretto/mem_init" ;;&

	# generate toplevel from quantized net architecture
	generate | all) echo "generate toplevel parameters from net architecture
		tool: custom python script
		input: quantized model, binary weight files directory
		output: VHDL toplevel"
		if [ "$1" = "generate" ]; then
			# just ask for input in manual mode
			read -r -p "This step will overwrite the current parameter file! Continue? [y/N] " response
		else
			response="y"
		fi
		case "$response" in
		[yY][eE][sS]|[yY])
			"./python_tools/cnn_$CNN_FW/parse_param.py" \
				"$MODEL_QUANT" \
				"$CNN_DIR/caffe_ristretto/mem_init" \
				"$VHDL_DIR/top_wrapper.vhd" ;;
		*) ;;
		esac ;;&

	# cosimulation of finetuned model
	simulate | all) echo "simulate VHDL CNN and compare with Caffe results
		tool: cocotb (testbench), ghdl (simulator) and caffe (reference values)
		input: python testbench, VHDL (code + toplevel), reference model and weights, (input image)
		output: verification of VHDL design"
		cd "$PWD/vhdl/sim/cocotb/top" || exit 1
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

	-h | --help) echo "Workflow:
                          - train CNN
        quantize_model    - quantize CNN model
        quantize_check    - sanity check of the quantized model
        quantize_weights  - quantize weights
        benchmark         - benchmark quantized model and weights
        extract           - extract weights from model in VHDL readable form
        generate          - generate toplevel parameters from CNN model
        simulate          - simulate VHDL design and compare with caffe results
        all               - perform all necessary steps from extract to simulation" ;;
esac