# --- 1. O Sistema de Arquivos (O "Disco") ---
resource "oci_file_storage_file_system" "swarm_fs" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "Swarm-Volume"

  defined_tags = {
    "Ambiente_Datacenter.AMBIENTE" = "PRODUCAO"
  }
}

# --- 2. O Mount Target (A "Placa de Rede" do NFS) ---
resource "oci_file_storage_mount_target" "swarm_mt" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  subnet_id           = var.subnet_ocid
  display_name        = "Swarm-Mount-Target"

  # --- AQUI ESTÁ A MÁGICA ---
  ip_address          = "172.16.13.250"
  # --------------------------

  defined_tags = {
    "Ambiente_Datacenter.AMBIENTE" = "PRODUCAO"
  }
}

# --- 3. A Exportação (Permite que o disco seja acessado) ---
resource "oci_file_storage_export_set" "swarm_export_set" {
  mount_target_id = oci_file_storage_mount_target.swarm_mt.id
  display_name    = "Swarm Export Set"
}

resource "oci_file_storage_export" "swarm_export" {
  export_set_id  = oci_file_storage_export_set.swarm_export_set.id
  file_system_id = oci_file_storage_file_system.swarm_fs.id
  path           = "/swarm_data"
}

# --- SAÍDA (CORRIGIDA) ---
output "nfs_ip_address" {
  # CORREÇÃO: Removemos o [0] pois ip_address já é um valor único
  value = oci_file_storage_mount_target.swarm_mt.ip_address
}
