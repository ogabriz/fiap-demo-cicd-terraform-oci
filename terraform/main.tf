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

module "postgres" {
  source = "./modules/postgres"

  compartment_id = var.compartment_id
  subnet_id      = module.networking.db_subnet_id
  ssh_public_key = var.ssh_public_key
  image_id       = var.image_id
}

module "redis" {
  source = "./modules/redis"

  compartment_id = var.compartment_id
  subnet_id      = module.networking.db_subnet_id
  ssh_public_key = var.ssh_public_key
  image_id       = var.image_id
}