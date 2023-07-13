output "ip" {
  value = oci_core_instance._[0].public_ip
}

output "nodes_number" {
  value = local.nodes_number
}
