locals {
  name                = "kubernetes"
  vcn_cidr            = "10.0.0.0/16"
  availability_domain = 0
  arch                = "amd64" # or arm64
}

locals {
  shape         = local.arch == "amd64" ? "VM.Standard.E2.1.Micro" : "VM.Standard.A1.Flex"
  nodes_number  = local.arch == "amd64" ? 2 : 4
  ocpus         = local.arch == "amd64" ? null : 1
  memory_in_gbs = local.arch == "amd64" ? null : 6
}
