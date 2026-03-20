terraform {
  required_version = "~> 1.7"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }

  backend "oci" {
    bucket    = "terraform-state-bucket"
    namespace = "griog4pa3yfi"
    key       = "fiap-demo/terraform.tfstate"
    region    = "sa-saopaulo-1"
  }
}
