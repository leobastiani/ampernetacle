locals {
  packages = [
    "libseccomp2",
    "cri-o",
    "cri-o-runc",
    "apt-transport-https",
    "ca-certificates",
    "curl", # used in provisioning scripts
    var.kubernetes_version == null ? "kubeadm" : "kubeadm=${var.kubernetes_version}",
    var.kubernetes_version == null ? "kubelet" : "kubelet=${var.kubernetes_version}"
  ]

  kubeadm_token = format("%s.%s", random_string.token1.result, random_string.token2.result)
}

data "http" "crio1_repo_key" {
  url = "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/Release.key"
}

data "http" "crio2_repo_key" {
  url = "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.24/xUbuntu_22.04/Release.key"
}

data "http" "kubernetes_repo_key" {
  url = "https://packages.cloud.google.com/apt/doc/apt-key.gpg.asc"
}

data "cloudinit_config" "_" {
  for_each = local.nodes

  part {
    filename     = "cloud-config.cfg"
    content_type = "text/cloud-config"
    content      = <<-EOF
      hostname: ${each.value.node_name}
      package_update: true
      package_upgrade: true
      packages:
      ${yamlencode(local.packages)}
      apt:
        sources:
          devel:kubic:libcontainers:stable.list:
            source: "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/ /"
            key: |
              ${indent(8, data.http.crio1_repo_key.response_body)}
          devel:kubic:libcontainers:stable:cri-o:1.24.list:
            source: "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.24/xUbuntu_22.04/ /"
            key: |
              ${indent(8, data.http.crio2_repo_key.response_body)}
          kubernetes.list:
            source: "deb https://apt.kubernetes.io/ kubernetes-xenial main"
            key: |
              ${indent(8, data.http.kubernetes_repo_key.response_body)}
      users:
      - default
      EOF
  }

  # By default, all inbound traffic is blocked (except SSH) so we need to change that.
  part {
    filename     = "1-allow-inbound-traffic.sh"
    content_type = "text/x-shellscript"
    content      = <<-EOF
      #!/bin/sh
      sed -i "s/-A INPUT -j REJECT --reject-with icmp-host-prohibited//" /etc/iptables/rules.v4
      # There appears to be a bug in the netfilter-persistent scripts:
      # the "reload" and "restart" actions seem to append the rules files
      # to the existing rules (instead of replacing them), perhaps because
      # the "stop" action is disabled. So instead, we need to flush the
      # rules first before we load the new rule set.
      netfilter-persistent flush
      netfilter-persistent start
    EOF
  }

  # kubeadm pre-requisites
  part {
    filename     = "2-kubeadm-prerequisites.sh"
    content_type = "text/x-shellscript"
    content      = <<-EOF
      #!/bin/sh
      cat <<EOC | sudo tee /etc/modules-load.d/k8s.conf
      overlay
      br_netfilter
      EOC

      modprobe overlay
      modprobe br_netfilter

      cat <<EOC | sudo tee /etc/sysctl.d/k8s.conf
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1
      EOC

      sysctl --system
    EOF
  }

  # start cri-o and enable start on boot
  part {
    filename     = "3-start-crio.sh"
    content_type = "text/x-shellscript"
    content      = <<-EOF
      #!/bin/sh
      service crio start
      systemctl enable crio
    EOF
  }

  dynamic "part" {
    for_each = each.value.role == "controlplane" ? ["yes"] : []
    content {
      filename     = "4-kubeadm-init.sh"
      content_type = "text/x-shellscript"
      content      = <<-EOF
#!/bin/sh
PUBLIC_IP_ADDRESS=$(curl -s https://icanhazip.com/)
kubeadm init --pod-network-cidr="${var.pod_network_cidr}" --service-cidr="${var.service_network_cidr}" --apiserver-cert-extra-sans $PUBLIC_IP_ADDRESS,${each.value.node_name} --token ${local.kubeadm_token} --ignore-preflight-errors=NumCPU
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config
EOF
    }
  }

  dynamic "part" {
    for_each = each.value.role == "controlplane" && var.cni_flannel_yaml != null ? ["yes"] : []
    content {
      filename     = "5-setup-flannel.sh"
      content_type = "text/x-shellscript"
      content      = <<-EOF
#!/bin/sh
export KUBECONFIG=/etc/kubernetes/admin.conf
curl -sLo /tmp/kube-flannel.yml ${var.cni_flannel_yaml}
sed -i s_10.244.0.0/16_${var.pod_network_cidr}_ /tmp/kube-flannel.yml
kubectl apply -f /tmp/kube-flannel.yml
sleep 20
iptables -F
iptables -F -tnat
EOF
    }
  }

  dynamic "part" {
    for_each = each.value.role == "controlplane" && var.cni_weave_yaml != null && var.cni_flannel_yaml == null ? ["yes"] : []
    content {
      filename     = "5-setup-weave.sh"
      content_type = "text/x-shellscript"
      content      = <<-EOF
#!/bin/sh
export KUBECONFIG=/etc/kubernetes/admin.conf
curl -sLo /tmp/kube-weave.yml ${var.cni_weave_yaml}
sed -i "s@name: INIT_CONTAINER@name: IPALLOC_RANGE\n                  value: ${var.pod_network_cidr}\n                - name: INIT_CONTAINER@" /tmp/kube-weave.yml
kubectl apply -f /tmp/kube-weave.yml
sleep 20
iptables -F
iptables -F -tnat
EOF
    }
  }

  dynamic "part" {
    for_each = each.value.role == "worker" ? ["yes"] : []
    content {
      filename     = "4-kubeadm-join.sh"
      content_type = "text/x-shellscript"
      content      = <<-EOF
#!/bin/sh
KUBE_API_SERVER=${local.nodes[1].ip_address}:6443
while ! curl -s --insecure https://$KUBE_API_SERVER; do
  echo "Kubernetes API server ($KUBE_API_SERVER) not responding."
  echo "Waiting 10 seconds before we try again."
  sleep 10
done
echo "Kubernetes API server ($KUBE_API_SERVER) appears to be up."
echo "Trying to join this node to the cluster."
kubeadm join --discovery-token-unsafe-skip-ca-verification --node-name ${each.value.node_name} --token ${local.kubeadm_token} $KUBE_API_SERVER
iptables -F
iptables -F -tnat
EOF
    }
  }
}

# The kubeadm token must follow a specific format:
# - 6 letters/numbers
# - a dot
# - 16 letters/numbers
resource "random_string" "token1" {
  length  = 6
  numeric = true
  lower   = true
  special = false
  upper   = false
}
resource "random_string" "token2" {
  length  = 16
  numeric = true
  lower   = true
  special = false
  upper   = false
}
