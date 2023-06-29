resource "oci_identity_compartment" "_" {
  name          = var.name
  description   = var.name
  enable_delete = true
}

locals {
  compartment_id = oci_identity_compartment._.id

  nodes = {
    for i in range(1, 1 + var.how_many_nodes) :
    i => {
      node_name  = format("node%d", i)
      ip_address = cidrhost(oci_core_subnet._.cidr_block, 10 + i)
      role       = i == 1 ? "controlplane" : "worker"
    }
  }
}

data "oci_identity_availability_domains" "_" {
  compartment_id = local.compartment_id
}

data "oci_core_images" "_" {
  compartment_id           = local.compartment_id
  shape                    = var.shape
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
}

resource "oci_core_instance" "_" {
  for_each            = local.nodes
  display_name        = each.value.node_name
  availability_domain = data.oci_identity_availability_domains._.availability_domains[var.availability_domain].name
  compartment_id      = local.compartment_id
  shape               = var.shape
  shape_config {
    memory_in_gbs = var.memory_in_gbs_per_node
    ocpus         = var.ocpus_per_node
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
    user_data           = data.cloudinit_config._[each.key].rendered
  }
  connection {
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
  }
  provisioner "remote-exec" {
    inline = [
      "sudo iptables -I INPUT 1 -j ACCEPT",
      "tail -f /var/log/cloud-init-output.log &",
      "cloud-init status --wait >/dev/null",
    ]
  }
}
