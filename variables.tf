variable "arch" {
  type        = string
  description = "Architecture type"

  validation {
    condition     = can(regex("^(arm|x86)$", var.arch))
    error_message = "Invalid architecture. Only 'arm' and 'x86' are allowed."
  }
}

variable "nodes_number" {
  type    = number
  default = null
}

variable "name" {
  type = string
}

variable "ocpus" {
  type    = number
  default = null
}

variable "memory_in_gbs" {
  type    = number
  default = null
}

variable "boot_volume_size_in_gbs" {
  type    = number
  default = null
}

locals {
  name                = var.name
  vcn_cidr            = "10.0.0.0/16"
  availability_domain = 0
}

locals {
  shape         = var.arch == "x86" ? "VM.Standard.E2.1.Micro" : "VM.Standard.A1.Flex"
  nodes_number  = var.nodes_number != null ? var.nodes_number : (var.arch == "x86" ? 2 : 4)
  ocpus         = var.ocpus == null ? (var.arch == "x86" ? null : 1) : var.ocpus
  memory_in_gbs = var.memory_in_gbs == null ? (var.arch == "x86" ? null : 6) : var.memory_in_gbs
}
