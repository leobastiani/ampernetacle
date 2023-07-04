output "ip" {
  value = oci_core_instance._[0].public_ip
}

output "how_many_nodes" {
  value = var.how_many_nodes
}
