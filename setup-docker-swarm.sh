#!/bin/bash

cd "$(dirname "$0")"

set -euo pipefail
IFS=$'\n\t'

nodes_number=$(terraform output -raw nodes_number)
cmd_nodes() {
  for ((i = 0; i < nodes_number; i++)); do
    ./ssh.sh "$i" "$@" &
  done
  wait
}

cmd_workers() {
  for ((i = 1; i <= nodes_number; i++)); do
    ./ssh.sh "$i" "$@" &
  done
  wait
}

cmd_control_plane() {
  ./ssh.sh 0 "$@"
}

# ack
for ((i = 0; i < nodes_number; i++)); do
  ./ssh.sh "$i" "echo"
done

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
apt-get-update() {
  if [ -z "\${has_updated:-}" ]; then
    sudo apt-get update
    has_updated=1
  fi
}

if [ ! -f ~/.zshrc ]; then
  apt-get-update
  sudo apt-get install -y zsh && \
    curl -fsSL https://raw.githubusercontent.com/gustavohellwig/gh-zsh/main/gh-zsh.sh | bash && \
    sudo chsh -s \$(which zsh) \$(whoami)
fi

if [ ! -f /swapfile ]; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  sudo cp /etc/fstab /etc/fstab.bak
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  sudo sysctl vm.swappiness=10
  echo vm.swappiness=10 | sudo tee -a /etc/sysctl.conf
  sudo sysctl vm.vfs_cache_pressure=50
  echo vm.vfs_cache_pressure=50 | sudo tee -a /etc/sysctl.conf
fi

if [ ! "\$(command -v docker)" ]; then
  apt-get-update
  sudo apt-get install apt-transport-https ca-certificates curl software-properties-common iptables -y
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo add-apt-repository --yes "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
  sudo apt-get install docker-ce -y
  sudo usermod -aG docker \$(whoami)
fi
EOF
)"
cmd_nodes "$install_docker"

setup_control_plane="$(
  cat <<EOF
set -x
if [ \$(docker info --format '{{.Swarm.LocalNodeState}}') != "active" ]; then
  docker swarm init
fi
EOF
)"
cmd_control_plane "$setup_control_plane"

token=$(cmd_control_plane "docker swarm join-token -q worker")

setup_workers="$(
  cat <<EOF
set -x
if [ \$(docker info --format '{{.Swarm.LocalNodeState}}') != "active" ]; then
  docker swarm join --token $token 10.0.0.10:2377
fi
EOF
)"
cmd_workers "$setup_workers"
