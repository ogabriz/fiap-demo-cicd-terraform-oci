# ============================================================================
# Configuração do Ambiente DEV
# ============================================================================
#
# Variáveis NÃO sensíveis do projeto.
# Credenciais ficam nos GitHub Secrets.
#
# Para outros ambientes, crie: staging.tfvars, prod.tfvars
# ============================================================================
tenancy_ocid = "ocid1.tenancy.oc1...."
# --- Projeto ---
project_name = "fiap-demo-oci"
environment  = "dev"
# --- Compartment ---
compartment_id = "ocid1.compartment.oc1..aaaaaaaanehxovyxoaobjbxqhbgdcubarphs5xuptwok4gbcpepxov75obpq"
# --- Rede ---
vcn_cidr    = "10.0.0.0/16"
subnet_cidr = "10.0.1.0/24"

# --- Compute ---
instance_image_id = "ocid1.image.oc1.sa-saopaulo-1.aaaaaaaaknaozajhsexgzwmcpthd6xa2kx4r2ofaqbfjk2mfrozvca7lbz3a"
instance_shape    = "VM.Standard.E2.1"
instance_count    = 1

# --- Security ---
ingress_ports = [22, 80]

# # ============================================================================
# # 🎯 LIVE: Descomentar as variáveis abaixo conforme for criando os recursos
# # ============================================================================

# # # --- Networking - VCN dedicada para OKE ---
 oke_vcn_cidr           = "10.0.0.0/16"
 oke_subnet_api_cidr    = "10.0.2.0/28"      # API Endpoint (pequena, /28 = 16 IPs)
 oke_subnet_workers_cidr = "10.0.3.0/24"    # Worker Nodes (256 IPs)
 oke_subnet_lb_cidr     = "10.0.4.0/24"     # Load Balancers (256 IPs)
 oke_subnet_pods_cidr   = "10.0.128.0/18"    # Pods VCN Native (16k IPs)
 oke_subnet_db_cidr     = "10.0.5.0/24"     # Databases/outros (256 IPs)

# # --- OKE (Oracle Kubernetes Engine) ---
 oke_kubernetes_version = "v1.34.1"
 oke_node_shape         = "VM.Standard.E3.Flex"
 oke_node_ocpus         = 2
 oke_node_memory_gb     = 16
 oke_node_count         = 2
 oke_node_image_id      = "ocid1.image.oc1.sa-saopaulo-1.aaaaaaaafod6xf2zv3w4itj2s7wqdttabeitvcbpsdez4yjng6i55cpi6qgq"
 oke_services_cidr      = "10.96.0.0/16"  # CIDR para Services (ClusterIP)

# # --- NoSQL (equivalente DynamoDB) ---
 nosql_read_units  = 50
 nosql_write_units = 50
 nosql_storage_gb  = 25 

# # --- Queue (equivalente SQS) ---
 queue_retention_seconds  = 345600  # 4 dias
 queue_timeout_seconds    = 30
 queue_visibility_seconds = 30
 queue_dead_letter_count  = 5
