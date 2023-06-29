output "ssh-with-ubuntu-user" {
  value = [for i in oci_core_instance._ :
    format(
      "ssh -i ~/.ssh/id_rsa ubuntu@%s # %s",
      i.public_ip,
      i.display_name
    )
  ]
}
