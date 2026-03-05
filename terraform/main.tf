module "networking" {
  source         = "./modules/networking"
  compartment_id = var.compartment_id
}

module "oke" {
  source         = "./modules/oke"
  compartment_id = var.compartment_id
  vcn_id         = module.networking.vcn_id
  subnet_id      = module.networking.workers_subnet_id
  availability_domain = local.availability_domain
}

module "postgres" {
  source              = "./modules/postgres"
  compartment_id      = var.compartment_id
  availability_domain = local.availability_domain
  subnet_id           = module.networking.db_subnet_id
  db_admin_password   = var.db_admin_password
}

module "redis" {
  source              = "./modules/redis"
  compartment_id      = var.compartment_id
  availability_domain = local.availability_domain
  subnet_id           = module.networking.db_subnet_id
}

module "nosql" {
  source         = "./modules/nosql"
  compartment_id = var.compartment_id
}

module "ocir" {
  source         = "./modules/ocir"
  compartment_id = var.compartment_id
}