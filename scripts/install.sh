#!/bin/bash

set -e

# display help
display_help() {
    echo "Usage: $0  "
    echo
    echo "  -h,--help          Display this help message."
    echo "  -p,--precision     Precision to use FLOAT/HALF/INT8."
    echo "  -t,--threads       Threads per GPU/CPU cores."
    echo
    echo "Example: ./install.sh -p INT8 -t 160"
    echo
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    display_help
    exit 0
fi

# number of cores and gpus
CPUS=`grep -c ^processor /proc/cpuinfo`
if [ ! -z `which nvidia-smi` ]; then
    GPUS=0
    DEV=gpu
else
    GPUS=1
    DEV=cpu
fi

# Autodetect operating system
OSD=windows
if [[ "$OSTYPE" == "linux-gnu" ]]; then
  OSD=ubuntu
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OSD=macosx
fi

# Select
OS=${1:-$OSD}      # OS is either ubuntu/centos/windows/android
DEV=${2:-$DEV}     # Device is either gpu/cpu
VERSION=3.0        # Version of scorpio

# paths
VR=`echo $VERSION | tr -d '.'`
EGBB=nnprobe-${OS}-${DEV}
NET="nets-scorpio"

# download
SCORPIO=Scorpio-$(date '+%d-%b-%Y')
mkdir -p $SCORPIO
[ -L Scorpio ] && rm -rf Scorpio
ln -sf $SCORPIO Scorpio
cd $SCORPIO

# egbbdll & linnnprobe
LNK=https://github.com/dshawul/Scorpio/releases/download
wget --no-check-certificate ${LNK}/${VERSION}/${EGBB}.zip
unzip -o ${EGBB}.zip
# networks
for N in $NET; do
    wget --no-check-certificate ${LNK}/${VERSION}/$N.zip
    unzip -o $N.zip
done
# scorpio binary
wget --no-check-certificate ${LNK}/${VERSION}/scorpio${VR}-mcts-nn.zip
unzip -o scorpio${VR}-mcts-nn.zip

rm -rf *.zip
chmod 755 ${EGBB}
cd ${EGBB}
chmod 755 *
cd ../..

#paths
cd $SCORPIO
PD=`pwd`
PD=`echo $PD | sed 's/\/cygdrive//g'`
PD=`echo $PD | sed 's/\/c\//c:\//g'`
egbbp=${PD}/${EGBB}
if [ $DEV = "gpu" ]; then
    nnp=${PD}/nets-scorpio/ens-net-20x256.uff
    nnp_e=${PD}/nets-maddex/ME.uff
    nnp_m=
    nn_type=0
    nn_type_e=-1
    nn_type_m=-1
    wdl_head=0
    wdl_head_e=1
    wdl_head_m=0
else
    nnp=${PD}/nets-scorpio/ens-net-12x128.pb
    nnp_e=${PD}/nets-scorpio/ens-net-12x128.pb
    nnp_m=
    nn_type=0
    nn_type_e=-1
    nn_type_m=-1
    wdl_head=0
    wdl_head_e=0
    wdl_head_m=0
fi
if [ $OS = "windows" ]; then
    exep=${PD}/bin/Windows
elif [ $OS = "android" ]; then
    exep=${PD}/bin/Android
else
    exep=${PD}/bin/Linux
fi
cd $exep

#determin GPU props
if [ $DEV = "gpu" ]; then
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${egbbp}
    cd $egbbp
    ./device
    THREADS=`./device --mp`
    PREC=HALF
    HAS=`./device --fp16`
    if [ "$HAS" = "N" ]; then
        PREC=FLOAT
    fi
    cd $exep
else
    PREC=FLOAT
    THREADS=4
fi

# process cmd line arguments
while ! [ -z "$1" ]; do
    case $1 in
        -p | --precision )
            shift
            PREC=$1
            ;;
        -t | --threads )
            shift
            THREADS=$1
            ;;
    esac
    shift
done

# number of threads
delay=0
if [ $DEV = "gpu" ]; then
    mt=$((GPUS*THREADS))
    rt=$((mt/CPUS))
    if [ $rt -ge 10 ]; then
       delay=1
    fi
else
    mt=$((CPUS*THREADS))
    delay=1
fi

# Edit scorpio.ini
egbbp_=$(echo $egbbp | sed 's_/_\\/_g')
nnp_=$(echo $nnp | sed 's_/_\\/_g')
nnp_e_=$(echo $nnp_e | sed 's_/_\\/_g')
nnp_m_=$(echo $nnp_m | sed 's_/_\\/_g')

sed -i "s/^egbb_path.*/egbb_path                ${egbbp_}/g" scorpio.ini
sed -i "s/^delay.*/delay                    ${delay}/g" scorpio.ini
sed -i "s/^float_type.*/float_type               ${PREC}/g" scorpio.ini

if [ $DEV = "gpu" ]; then
    sed -i "s/^device_type.*/device_type              GPU/g" scorpio.ini
    sed -i "s/^n_devices.*/n_devices                ${GPUS}/g" scorpio.ini
    sed -i "s/^mt.*/mt                  ${mt}/g" scorpio.ini
else
    sed -i "s/^device_type.*/device_type              CPU/g" scorpio.ini
    sed -i "s/^n_devices.*/n_devices                1/g" scorpio.ini
    sed -i "s/^mt.*/mt                  ${mt}/g" scorpio.ini
fi
if [ $nn_type -ge 0 ]; then
    sed -i "s/^nn_path .*/nn_path                  ${nnp_}/g" scorpio.ini
    sed -i "s/^nn_type .*/nn_type                  ${nn_type}/g" scorpio.ini
    if [ $wdl_head -gt 0 ]; then
      sed -i "s/^wdl_head.*/wdl_head               1/g" scorpio.ini
    fi
fi
if [ $nn_type_m -ge 0 ]; then
    sed -i "s/^nn_path_m.*/nn_path_m                ${nnp_m_}/g" scorpio.ini
    sed -i "s/^nn_type_m.*/nn_type_m                ${nn_type_m}/g" scorpio.ini
    if [ $wdl_head_m -gt 0 ]; then
      sed -i "s/^wdl_head_m.*/wdl_head_m               1/g" scorpio.ini
    fi
fi
if [ $nn_type_e -ge 0 ]; then
    sed -i "s/^nn_path_e.*/nn_path_e                ${nnp_e_}/g" scorpio.ini
    sed -i "s/^nn_type_e.*/nn_type_e                ${nn_type_e}/g" scorpio.ini
    if [ $wdl_head_e -gt 0 ]; then
      sed -i "s/^wdl_head_e.*/wdl_head_e               1/g" scorpio.ini
    fi
fi

# Prepare script for scorpio and set PATH env variable
if [ $OS = "windows" ]; then
    EXE=scorpio.bat
else
    EXE=scorpio.sh
fi

cd ../..

# Test
echo "Making a test run"
$exep/$EXE go quit
