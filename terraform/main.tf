module "networking" {
  source         = "./modules/networking"
  compartment_id = var.compartment_id
}

module "ocir" {
  source         = "./modules/ocir"
  compartment_id = var.compartment_id
}

module "nosql" {
  source = "./modules/nosql"

  compartment_id = var.compartment_id
  table_name     = "togglemaster_table"
}