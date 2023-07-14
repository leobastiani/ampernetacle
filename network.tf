resource "oci_core_vcn" "_" {
  compartment_id = local.compartment_id
  cidr_block     = local.vcn_cidr
}

resource "oci_core_internet_gateway" "_" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn._.id
}

resource "oci_core_default_route_table" "_" {
  manage_default_resource_id = oci_core_vcn._.default_route_table_id
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway._.id
  }
}

resource "oci_core_default_security_list" "_" {
  manage_default_resource_id = oci_core_vcn._.default_security_list_id
  ingress_security_rules {
    protocol = "all"
    source   = "0.0.0.0/0"
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "_" {
  compartment_id    = local.compartment_id
  cidr_block        = cidrsubnet(oci_core_vcn._.cidr_block, 8, 0)
  vcn_id            = oci_core_vcn._.id
  route_table_id    = oci_core_default_route_table._.id
  security_list_ids = [oci_core_default_security_list._.id]
}

data "oci_core_private_ips" "_" {
  count      = local.nodes_number > 0 ? 1 : 0
  ip_address = oci_core_instance._[0].private_ip
  subnet_id  = oci_core_subnet._.id
}

resource "oci_core_public_ip" "_" {
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  private_ip_id  = local.nodes_number > 0 ? data.oci_core_private_ips._[0].private_ips[0]["id"] : ""
}
