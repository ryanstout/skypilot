# Script for testing backward compatibility of skypilot.
#
# To run this script, you need to uninstall the skypilot and ray in the base
# conda environment, and run it in the base conda environment.
#
# It's recommended to use a smoke-test VM to run this.
#
# Usage:
#
#   cd skypilot-repo
#   git checkout <feature branch>
#   pip uninstall -y skypilot ray
#   bash tests/backward_compatibility_tests.sh

#!/bin/bash
set -evx

need_launch=${1:-0}
start_from=${2:-0}

source ~/.bashrc
CLUSTER_NAME="test-back-compat-$USER"
source $(conda info --base 2> /dev/null)/etc/profile.d/conda.sh
CLOUD="aws"

git clone https://github.com/skypilot-org/skypilot.git ../sky-master || true


# Create environment for compatibility tests
conda env list | grep sky-back-compat-master || conda create -n sky-back-compat-master -y python=3.9

conda activate sky-back-compat-master
conda install -c conda-forge google-cloud-sdk -y
rm -r  ~/.sky/wheels || true
cd ../sky-master
git pull origin master
pip uninstall -y skypilot
pip install uv
uv pip install --prerelease=allow "azure-cli>=2.65.0"
uv pip install -e ".[all]"
cd -

conda env list | grep sky-back-compat-current || conda create -n sky-back-compat-current -y python=3.9
conda activate sky-back-compat-current
conda install -c conda-forge google-cloud-sdk -y
rm -r  ~/.sky/wheels || true
pip uninstall -y skypilot
pip install uv
uv pip install --prerelease=allow "azure-cli>=2.65.0"
uv pip install -e ".[all]"


clear_resources() {
  sky down ${CLUSTER_NAME}* -y
  sky jobs cancel -n ${MANAGED_JOB_JOB_NAME}* -y
}

# Set trap to call cleanup on script exit
trap clear_resources EXIT

# exec + launch
if [ "$start_from" -le 1 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
which sky
# Job 1
sky launch --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -c ${CLUSTER_NAME} examples/minimal.yaml
sky autostop -i 10 -y ${CLUSTER_NAME}
# Job 2
sky exec -d --cloud ${CLOUD} --num-nodes 2 ${CLUSTER_NAME} sleep 100

conda activate sky-back-compat-current
sky status -r ${CLUSTER_NAME} | grep ${CLUSTER_NAME} | grep UP
rm -r  ~/.sky/wheels || true
if [ "$need_launch" -eq "1" ]; then
  sky launch --cloud ${CLOUD} -y -c ${CLUSTER_NAME}
fi
# Job 3
sky exec -d --cloud ${CLOUD} ${CLUSTER_NAME} sleep 50
q=$(sky queue ${CLUSTER_NAME})
echo "$q"
echo "$q" | grep "RUNNING" | wc -l | grep 2 || exit 1
# Job 4
s=$(sky launch --cloud ${CLOUD} -d -c ${CLUSTER_NAME} examples/minimal.yaml)
sky logs ${CLUSTER_NAME} 2 --status | grep RUNNING || exit 1
# remove color and find the job id
echo "$s" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | grep "Job ID: 4" || exit 1
# wait for ready
sky logs ${CLUSTER_NAME} 2
q=$(sky queue ${CLUSTER_NAME})
echo "$q"
echo "$q" | grep "SUCCEEDED" | wc -l | grep 4 || exit 1
fi

# sky stop + sky start + sky exec
if [ "$start_from" -le 2 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
sky launch --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -c ${CLUSTER_NAME}-2 examples/minimal.yaml
conda activate sky-back-compat-current
rm -r  ~/.sky/wheels || true
sky stop -y ${CLUSTER_NAME}-2
sky start -y ${CLUSTER_NAME}-2
s=$(sky exec --cloud ${CLOUD} -d ${CLUSTER_NAME}-2 examples/minimal.yaml)
echo "$s"
echo "$s" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | grep "Job ID: 2" || exit 1
fi

# `sky autostop` + `sky status -r`
if [ "$start_from" -le 3 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
sky launch --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -c ${CLUSTER_NAME}-3 examples/minimal.yaml
conda activate sky-back-compat-current
rm -r  ~/.sky/wheels || true
sky autostop -y -i0 ${CLUSTER_NAME}-3
sleep 120
sky status -r | grep ${CLUSTER_NAME}-3 | grep STOPPED || exit 1
fi


# (1 node) sky launch --cloud ${CLOUD} + sky exec + sky queue + sky logs
if [ "$start_from" -le 4 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
sky launch --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -c ${CLUSTER_NAME}-4 examples/minimal.yaml
sky stop -y ${CLUSTER_NAME}-4
conda activate sky-back-compat-current
rm -r  ~/.sky/wheels || true
sky launch --cloud ${CLOUD} -y --num-nodes 2 -c ${CLUSTER_NAME}-4 examples/minimal.yaml
sky queue ${CLUSTER_NAME}-4
sky logs ${CLUSTER_NAME}-4 1 --status
sky logs ${CLUSTER_NAME}-4 2 --status
sky logs ${CLUSTER_NAME}-4 1
sky logs ${CLUSTER_NAME}-4 2
fi

# (1 node) sky start + sky exec + sky queue + sky logs
if [ "$start_from" -le 5 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
sky launch --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -c ${CLUSTER_NAME}-5 examples/minimal.yaml
sky stop -y ${CLUSTER_NAME}-5
conda activate sky-back-compat-current
rm -r  ~/.sky/wheels || true
sky start -y ${CLUSTER_NAME}-5
sky queue ${CLUSTER_NAME}-5
sky logs ${CLUSTER_NAME}-5 1 --status
sky logs ${CLUSTER_NAME}-5 1
sky launch --cloud ${CLOUD} -y -c ${CLUSTER_NAME}-5 examples/minimal.yaml
sky queue ${CLUSTER_NAME}-5
sky logs ${CLUSTER_NAME}-5 2 --status
sky logs ${CLUSTER_NAME}-5 2
fi

# (2 nodes) sky launch --cloud ${CLOUD} + sky exec + sky queue + sky logs
if [ "$start_from" -le 6 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
sky launch --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -c ${CLUSTER_NAME}-6 examples/multi_hostname.yaml
sky stop -y ${CLUSTER_NAME}-6
conda activate sky-back-compat-current
rm -r  ~/.sky/wheels || true
sky start -y ${CLUSTER_NAME}-6
sky queue ${CLUSTER_NAME}-6
sky logs ${CLUSTER_NAME}-6 1 --status
sky logs ${CLUSTER_NAME}-6 1
sky exec --cloud ${CLOUD} ${CLUSTER_NAME}-6 examples/multi_hostname.yaml
sky queue ${CLUSTER_NAME}-6
sky logs ${CLUSTER_NAME}-6 2 --status
sky logs ${CLUSTER_NAME}-6 2
fi

# Test managed jobs to make sure existing jobs and new job can run correctly,
# after the jobs controller is updated.
# Get a new uuid to avoid conflict with previous back-compat tests.
uuid=$(uuidgen)
MANAGED_JOB_JOB_NAME=${CLUSTER_NAME}-${uuid:0:4}
if [ "$start_from" -le 7 ]; then
conda activate sky-back-compat-master
rm -r  ~/.sky/wheels || true
sky jobs launch -d --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -n ${MANAGED_JOB_JOB_NAME}-7-0 "echo hi; sleep 1000"
sky jobs launch -d --cloud ${CLOUD} -y --cpus 2 --num-nodes 2 -n ${MANAGED_JOB_JOB_NAME}-7-1 "echo hi; sleep 400"
conda activate sky-back-compat-current
rm -r  ~/.sky/wheels || true
s=$(sky jobs queue | grep ${MANAGED_JOB_JOB_NAME}-7 | grep "RUNNING" | wc -l)
s=$(sky jobs logs --no-follow -n ${MANAGED_JOB_JOB_NAME}-7-1)
echo "$s"
echo "$s" | grep " hi" || exit 1
sky jobs launch -d --cloud ${CLOUD} --num-nodes 2 -y -n ${MANAGED_JOB_JOB_NAME}-7-2 "echo hi; sleep 40"
s=$(sky jobs logs --no-follow -n ${MANAGED_JOB_JOB_NAME}-7-2)
echo "$s"
echo "$s" | grep " hi" || exit 1
s=$(sky jobs queue | grep ${MANAGED_JOB_JOB_NAME}-7)
echo "$s"
echo "$s" | grep "RUNNING" | wc -l | grep 3 || exit 1
sky jobs cancel -y -n ${MANAGED_JOB_JOB_NAME}-7-0
sky jobs logs -n "${MANAGED_JOB_JOB_NAME}-7-1" || exit 1
s=$(sky jobs queue | grep ${MANAGED_JOB_JOB_NAME}-7)
echo "$s"
echo "$s" | grep "SUCCEEDED" | wc -l | grep 2 || exit 1
echo "$s" | grep "CANCELLING\|CANCELLED" | wc -l | grep 1 || exit 1
fi
