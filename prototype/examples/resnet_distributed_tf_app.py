import json
import subprocess
from typing import Dict, List

import sky

IPAddr = str

with sky.Dag() as dag:
    # The working directory contains all code and will be synced to remote.
    workdir = '~/Downloads/tpu'
    subprocess.run(
        'cd ~/Downloads; '
        '(git clone https://github.com/concretevitamin/tpu || true); '
        f'cd {workdir} && git checkout 9459fee',
        shell=True,
        check=True)

    docker_image = None  # 'rayproject/ray-ml:latest-gpu'

    # Total Nodes, INCLUDING Head Node
    num_nodes = 2

    # The setup command.  Will be run under the working directory.
    setup = 'pip3 install --upgrade pip && \
           pip3 install ray[default] awscli botocore boto3 && \
           conda create -n resnet python=3.7 -y && \
           conda activate resnet && \
           pip install tensorflow==2.4.0 pyyaml ray[default] awscli botocore boto3 && \
           cd models && pip install -e .'

    # Post setup function. Run after `ray up *.yml` completes. Returns
    # dictionary of commands to be run on each corresponding node.
    # 'ip_list': List of IPs, 0th index denoting head worker.
    def post_setup_fn(ip_list: List[IPAddr]) -> Dict[IPAddr, str]:
        command_dict = {}
        tf_config = {
            'cluster': {
                'worker': [ip + ':8008' for ip in ip_list]
            },
            'task': {
                'type': 'worker',
                'index': -1
            }
        }
        for i, ip in enumerate(ip_list):
            tf_config['task']['index'] = i
            str_tf_config = json.dumps(tf_config).replace('"', '\\"')
            command_dict[
                ip] = "echo \"export TF_CONFIG='" + str_tf_config + "'\" >> ~/.bashrc"
        return command_dict

    # The command to run.  Will be run under the working directory.
    # If a str, run the same command on all nodes.
    # If a function, run per-node command on each node.
    def run_fn(ip_list: List[IPAddr]) -> Dict[IPAddr, str]:
        run = 'conda activate resnet && \
            rm -rf resnet_model-dir && \
            export XLA_FLAGS=\'--xla_gpu_cuda_data_dir=/usr/local/cuda/\' && \
            python models/official/resnet/resnet_main.py --use_tpu=False \
            --mode=train --train_batch_size=256 --train_steps=500 \
            --iterations_per_loop=125 \
            --data_dir=gs://cloud-tpu-test-datasets/fake_imagenet \
            --model_dir=resnet-model-dir \
            --amp --xla --loss_scale=128'

        return {ip: run for ip in ip_list}

    train = sky.Task(
        'train',
        workdir=workdir,
        setup=setup,
        post_setup_fn=post_setup_fn,
        docker_image=docker_image,
        num_nodes=num_nodes,
        run=run_fn,
    )

    train.set_inputs('gs://cloud-tpu-test-datasets/fake_imagenet',
                     estimated_size_gigabytes=70)
    train.set_outputs('resnet-model-dir', estimated_size_gigabytes=0.1)
    train.set_resources(sky.Resources(sky.AWS(), accelerators='V100'))

# sky.launch(dag, dryrun=True)
sky.launch(dag, cluster_name='dtf')
