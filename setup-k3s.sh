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

cmd_control_plane() {
  ssh "ubuntu@$(get_ip 0)" "$@"
}

# ack
for ((i = 0; i < nodes_number; i++)); do
  ssh "ubuntu@$(get_ip $i)" "true"
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

install_k3s_control_plane="$(
  cat <<EOF
set -x
if [ ! "\$(command -v k3s)" ]; then
  curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="--tls-san $(get_ip 0)" sh -s -
fi
EOF
)"
cmd_control_plane "$install_k3s_control_plane"

cmd_control_plane "cat /etc/rancher/k3s/k3s.yaml | sed 's|server: https://127.0.0.1:6443|server: https://$(get_ip 0):6443|g'" >kubeconfig

token=$(cmd_control_plane "sudo cat /var/lib/rancher/k3s/server/node-token")

install_k3s_worker="$(
  cat <<EOF
set -x
if ! sudo iptables -C INPUT -j ACCEPT &>/dev/null; then
  sudo iptables -I INPUT 1 -j ACCEPT
fi

if [ ! "\$(command -v k3s)" ]; then
  curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.10:6443 K3S_TOKEN=$token sh -
fi
EOF
)"

cmd_workers "$install_k3s_worker"

export KUBECONFIG=kubeconfig

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.12.2/cert-manager.yaml
kubectl apply -f lets-encrypt.yaml

if ! kubectl get secrets/docker-registry; then
  echo "docker hub password: "
  read -rs password
  if [ -n "$password" ]; then
    kubectl create secret docker-registry docker-registry \
      --docker-server=docker.io \
      --docker-username=leobastiani \
      "--docker-password=${password}" \
      --docker-email=leogbastiani@gmail.com
  fi
fi
