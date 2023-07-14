output "ips" {
  value = [
    for i in range(local.nodes_number) : i == 0 ? oci_core_public_ip._.ip_address : oci_core_instance._[i].public_ip
  ]
}

output "nodes_number" {
  value = local.nodes_number
}
