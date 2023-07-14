#!/bin/bash

cd "$(dirname "$0")"

set -euo pipefail
IFS=$'\n\t'

get_ip() {
  terraform output -json ips | jq -r ".[$1]"
}

nodes_number=$(terraform output -raw nodes_number)
cmd_nodes() {
  for ((i = 0; i < nodes_number; i++)); do
    ssh "ubuntu@$(get_ip "$i")" "$@" &
  done
  wait
}

cmd_workers() {
  for ((i = 1; i <= nodes_number; i++)); do
    ssh "ubuntu@$(get_ip $i)" "$@" &
  done
  wait
}

cmd_controlplane() {
  ssh "ubuntu@$(get_ip 0)" "$@"
}

# ack
for ((i = 0; i < nodes_number; i++)); do
  ssh "ubuntu@$(get_ip $i)" "echo"
done

# apt-update
cmd_nodes "sudo apt-get update"

patch_iptables="$(
  cat <<EOF
set -x
if ! sudo iptables -C INPUT -j ACCEPT &>/dev/null; then
  sudo iptables -I INPUT 1 -j ACCEPT
fi
EOF
)"
cmd_nodes "$patch_iptables"

install_docker="$(
  cat <<EOF
set -x
if [ ! "\$(command -v docker)" ]; then
  sudo apt-get install apt-transport-https ca-certificates curl software-properties-common iptables -y
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository --yes "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
  sudo apt-get install docker-ce -y
  sudo usermod -aG docker \$(whoami)
fi
EOF
)"
cmd_nodes "$install_docker"

setup_controlplane="$(
  cat <<EOF
set -x
if [ \$(docker info --format '{{.Swarm.LocalNodeState}}') != "active" ]; then
  docker swarm init
fi
EOF
)"
cmd_controlplane "$setup_controlplane"

token=$(cmd_controlplane "docker swarm join-token -q worker")

setup_workers="$(
  cat <<EOF
set -x
if [ \$(docker info --format '{{.Swarm.LocalNodeState}}') != "active" ]; then
  docker swarm join --token $token 10.0.0.10:2377
fi
EOF
)"
cmd_workers "$setup_workers"
