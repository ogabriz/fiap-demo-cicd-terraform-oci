resource "oci_nosql_table" "analytics" {
  compartment_id = var.compartment_id
  name           = "ToggleMasterAnalytics"

  ddl_statement = <<EOF
CREATE TABLE ToggleMasterAnalytics (
  id STRING,
  PRIMARY KEY(id)
)
EOF
}