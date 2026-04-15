terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

resource "oci_nosql_table" "main" {
  compartment_id = var.compartment_id
  name           = var.table_name

  ddl_statement = <<DDL
CREATE TABLE IF NOT EXISTS ${var.table_name} (
  id STRING,
  name STRING,
  created_at STRING,
  PRIMARY KEY(id)
)
DDL

  table_limits {
    max_read_units  = 50
    max_write_units = 50
    max_storage_in_gbs = 1
  }
}