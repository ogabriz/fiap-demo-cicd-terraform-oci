resource "oci_core_instance" "redis" {

  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_id
  display_name        = "redis-instance"

  shape = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = true
    hostname_label   = "redis-vm"
  }

  source_details {
    source_type = "image"
    source_id   = var.image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(<<-EOF
      #!/bin/bash
      # Instalação do Redis (Oracle Linux / RHEL style)
      sudo dnf install -y redis
      
      # Configuração para aceitar conexões de outros hosts
      sudo sed -i 's/bind 127.0.0.1 -::1/bind 0.0.0.0/' /etc/redis/redis.conf
      sudo sed -i 's/protected-mode yes/protected-mode no/' /etc/redis/redis.conf
      
      # Inicia e habilita o serviço
      sudo systemctl enable --now redis
      
      # Ajusta o firewall local da instância (se houver)
      sudo firewall-cmd --permanent --add-port=6379/tcp
      sudo firewall-cmd --reload
    EOF
    )
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}