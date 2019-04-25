wipe="\033[1m\033[0m"
yellow="\E[1;33m"

function echoc
{
    echo -e "${yellow}$1${wipe}"
}

echoc "############################################################################"
echoc "config: 1, 1, 8"
make SIM_ARGS="-gC_KSIZE=1 -gC_CH_IN=8 -gC_CH_OUT=2" | grep -n "TestError" && echoc "failure" || echoc "success"
make SIM_ARGS="-gC_KSIZE=1 -gC_CH_IN=8 -gC_CH_OUT=1" | grep -n "TestError" && echoc "failure" || echoc "success"

for ksize in 1 3; do
    for ch_in in 1 4; do
        echoc "config: ${ksize}, ${ch_in}"
        make SIM_ARGS="-gC_KSIZE=${ksize} -gC_CH_IN=${ch_in}" | grep -n "TestError" && echoc "failure" || echoc "success"
    done
done
