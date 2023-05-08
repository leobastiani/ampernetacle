variable "name" {
  type    = string
  default = "kubernetes-on-arm-with-oracle"
}

/*
Available flex shapes:
"VM.Optimized3.Flex"  # Intel Ice Lake
"VM.Standard3.Flex"   # Intel Ice Lake
"VM.Standard.A1.Flex" # Ampere Altra
"VM.Standard.E3.Flex" # AMD Rome
"VM.Standard.E4.Flex" # AMD Milan
*/

variable "shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "how_many_nodes" {
  type    = number
  default = 4
}

variable "availability_domain" {
  type    = number
  default = 0
}

variable "ocpus_per_node" {
  type    = number
  default = 1
}

variable "memory_in_gbs_per_node" {
  type    = number
  default = 6
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "pod_network_cidr" {
  type    = string
  default = "10.244.0.0/16"
}

variable "service_network_cidr" {
  type    = string
  default = "10.96.0.0/12"
}

variable "cni_flannel_yaml" {
  type    = string
  default = "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
}

variable "cni_weave_yaml" {
  type    = string
  default = null
  # https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml
}

# a valid version from https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-arm64/Packages
variable "kubernetes_version" {
  type = string
  default = null
}
