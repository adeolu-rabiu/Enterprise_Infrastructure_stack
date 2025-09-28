terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
  required_version = ">= 1.0"
}

# Provider configuration for local VMs
provider "libvirt" {
  uri = "qemu:///system"
}

# Create storage pool
resource "libvirt_pool" "homelab" {
  name = "homelab"
  type = "dir"
  path = "/var/lib/libvirt/images/homelab"
}

# Create network
resource "libvirt_network" "homelab" {
  name      = "homelab"
  mode      = "nat"
  domain    = "homelab.local"
  addresses = ["192.168.100.0/24"]

  dns {
    enabled = true
  }

  dhcp {
    enabled = true
  }
}
