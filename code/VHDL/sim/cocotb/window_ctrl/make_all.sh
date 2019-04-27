wipe="\033[1m\033[0m"
yellow="\E[1;33m"

function echoc
{
    echo -e "${yellow}$1${wipe}"
}

echoc "############################################################################"
echoc "config: 1, 1, 8, 2"
make SIM_ARGS="-gC_KSIZE=1 -gC_STRIDE=1 -gC_CH_IN=8 -gC_CH_OUT=2" | grep -n "TestError" && echoc "failure" || echoc "success"
echoc "config: 1, 1, 8, 1"
make SIM_ARGS="-gC_KSIZE=1 -gC_STRIDE=1 -gC_CH_IN=8 -gC_CH_OUT=1" | grep -n "TestError" && echoc "failure" || echoc "success"

for ksize in 1 2 3; do
    for stride in 1 2 3; do
        for ch_in in 1 4; do
            echoc "config: ${ksize}, ${stride}, ${ch_in}"
            make SIM_ARGS="-gC_KSIZE=${ksize} -gC_STRIDE=${stride} -gC_CH_IN=${ch_in}" | grep -n "TestError" && echoc "failure" || echoc "success"
        done
    done
done
