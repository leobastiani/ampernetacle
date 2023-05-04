data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

resource "oci_core_vcn" "_" {
  compartment_id = local.compartment_id
  cidr_block     = var.vcn_cidr
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
    description = "Allow all access from VCN"
    protocol    = "all"
    source      = oci_core_vcn._.cidr_block
  }
  ingress_security_rules {
    description = "Allow SSH from my IP"
    protocol    = "6" # TCP
    source      = "${chomp(data.http.myip.body)}/32"
    tcp_options {
      max = 22
      min = 22
    }
  }
  ingress_security_rules {
    description = "Allow k8s apiserver from my IP"
    protocol    = "6" # TCP
    source      = "${chomp(data.http.myip.body)}/32"
    tcp_options {
      max = 6443
      min = 6443
    }
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
