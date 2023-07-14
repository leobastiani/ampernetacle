resource "oci_identity_compartment" "_" {
  name          = local.name
  description   = local.name
  enable_delete = true
}

locals {
  compartment_id = oci_identity_compartment._.id

  nodes = {
    for i in range(local.nodes_number) : i => {
      node_name  = format("node%d", i + 1)
      ip_address = cidrhost(oci_core_subnet._.cidr_block, 10 + i)
      role       = i == 0 ? "control-plane" : "worker"
    }
  }
}

data "oci_identity_availability_domains" "_" {
  compartment_id = local.compartment_id
}

data "oci_core_images" "_" {
  compartment_id           = local.compartment_id
  shape                    = local.shape
  operating_system         = "Canonical Ubuntu"
  operating_system_version = ""
}

resource "oci_core_instance" "_" {
  for_each            = local.nodes
  display_name        = each.value.node_name
  availability_domain = data.oci_identity_availability_domains._.availability_domains[local.availability_domain].name
  compartment_id      = local.compartment_id
  shape               = local.shape
  dynamic "shape_config" {
    for_each = local.ocpus != null ? [1] : []
    content {
      memory_in_gbs = local.memory_in_gbs
      ocpus         = local.ocpus
    }
  }
  source_details {
    source_id   = data.oci_core_images._.images[0].id
    source_type = "image"
  }
  create_vnic_details {
    subnet_id  = oci_core_subnet._.id
    private_ip = each.value.ip_address
  }
  metadata = {
    ssh_authorized_keys = file("~/.ssh/id_rsa.pub")
  }
}
