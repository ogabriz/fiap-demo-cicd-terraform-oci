terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = "10.0.0.0/16"
  display_name   = "togglemaster-vcn"
  dns_label      = "togglemastervcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "togglemaster-igw"
  enabled        = true
}

# Route Table para acesso à internet
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Security List
resource "oci_core_security_list" "public_sl" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-security-list"

  # SSH acesso externo
  ingress_security_rules {

    protocol = "6" # TCP

    source = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # Kubernetes API server (necessário para kubectl externo / GitHub Actions)
  ingress_security_rules {

    protocol = "6" # TCP

    source = "0.0.0.0/0"

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # HTTP para Load Balancer
  ingress_security_rules {

    protocol = "6" # TCP

    source = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS para Load Balancer
  ingress_security_rules {

    protocol = "6" # TCP

    source = "0.0.0.0/0"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Comunicação interna da VCN (necessário para OKE)
  ingress_security_rules {

    protocol = "all"

    source = "10.0.0.0/16"

  }

  # Saída liberada para internet
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Subnet Workers
resource "oci_core_subnet" "workers" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  cidr_block     = "10.0.3.0/24"
  display_name   = "workers-subnet"

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_sl.id
  ]
}

# Subnet DB
resource "oci_core_subnet" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  cidr_block     = "10.0.5.0/24"
  display_name   = "db-subnet"
  dns_label      = "dbsubnet"

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_sl.id
  ]
}

# Subnet OKE Nodes
resource "oci_core_subnet" "oke_nodes" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  cidr_block     = "10.0.10.0/24"
  display_name   = "oke-nodes-subnet"

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_sl.id
  ]
}

# Subnet OKE Load Balancer
resource "oci_core_subnet" "oke_lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  cidr_block     = "10.0.20.0/24"
  display_name   = "oke-lb-subnet"

  route_table_id = oci_core_route_table.public_rt.id

  security_list_ids = [
    oci_core_security_list.public_sl.id
  ]
}
