locals {
  packages = [
    "apt-transport-https",
    "ca-certificates",
    "curl"
  ]
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
      users:
        - default
      EOF
  }
}
