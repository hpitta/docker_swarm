# Definição dos Nomes e IPs das máquinas (Garantia de IP Fixo)
locals {
  nodes = {
    "node01" = { name = "cidk01", ip = "172.16.13.213" }
    "node02" = { name = "cidk02", ip = "172.16.13.214" }
    "node03" = { name = "cidk03", ip = "172.16.13.215" }
  }
}

resource "oci_core_instance" "swarm_nodes" {
  # Cria uma instância para cada item definido em 'locals'
  for_each = local.nodes

  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = each.value.name

  # IMPORTANTE: Se você pegou o ID da imagem para E5, mude abaixo para "VM.Standard.E5.Flex"
  shape = "VM.Standard.E5.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 4
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = false
    
    # Fixando o IP Privado e o Hostname interno
    private_ip       = each.value.ip
    hostname_label   = each.value.name
  }

  source_details {
    source_type = "image"
    source_id   = var.image_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    
    # CORREÇÃO:
    # 1. Mudamos a chave para 'nfs_server_ip' (o nome que o script espera)
    # 2. Mantivemos sem o [0] (correção do erro de índice)
    user_data           = base64encode(templatefile("${path.module}/scripts/docker_install.sh", {
      nfs_server_ip = oci_file_storage_mount_target.swarm_mt.ip_address
      nfs_path      = "/swarm_data"
    }))
  }

  # --- GOVERNANÇA: TAGS SOLICITADAS ---
  defined_tags = {
    "Ambiente_Datacenter.AMBIENTE" = "PRODUCAO"
  }
}
