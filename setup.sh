#!/bin/bash

cd "$(dirname "$0")"

set -euo pipefail
IFS=$'\n\t'

ip=$(terraform output -raw ip)
install_k3s_control_plane="$(
  cat <<EOF
set -x
if ! sudo iptables -C INPUT -j ACCEPT &>/dev/null; then
  sudo iptables -I INPUT 1 -j ACCEPT
fi

if [ ! "\$(command -v k3s)" ]; then
  curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="--tls-san $ip" sh -s -
fi

cat /etc/rancher/k3s/k3s.yaml | sed 's|server: https://127.0.0.1:6443|server: https://$ip:6443|g'
EOF
)"

ssh "ubuntu@$ip" "$install_k3s_control_plane" >kubeconfig

node_token=$(ssh "ubuntu@$ip" "sudo cat /var/lib/rancher/k3s/server/node-token")

install_k3s_worker="$(
  cat <<EOF
set -x
if ! sudo iptables -C INPUT -j ACCEPT &>/dev/null; then
  sudo iptables -I INPUT 1 -j ACCEPT
fi

if [ ! "\$(command -v k3s)" ]; then
  curl -sfL https://get.k3s.io | K3S_URL=https://10.0.0.10:6443 K3S_TOKEN=$node_token sh -
fi
EOF
)"

worker_count=$(($(terraform output -raw nodes_number) - 1))
for ((i = 0; i < $worker_count; i++)); do
  ssh -J "ubuntu@$(terraform output -raw ip)" "ubuntu@10.0.0.$(($i + 11))" "$install_k3s_worker" &
done

wait

export KUBECONFIG=kubeconfig

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.12.2/cert-manager.yaml
kubectl apply -f lets-encrypt.yaml

if ! kubectl get secrets/docker-registry; then
  echo "docker hub password: "
  read -rs password
  kubectl create secret docker-registry docker-registry \
    --docker-server=docker.io \
    --docker-username=leobastiani \
    "--docker-password=${password}" \
    --docker-email=leogbastiani@gmail.com
fi
