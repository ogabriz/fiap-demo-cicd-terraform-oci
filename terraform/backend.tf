terraform {
  backend "oci" {
    bucket    = "terraform-state-bucket"
    namespace = "grqkmwwimskh"
    key       = "fiap-demo/terraform.tfstate"
    region    = "sa-saopaulo-1"
  }
}