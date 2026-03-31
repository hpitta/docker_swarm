terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 4.0.0"
    }
  }

  # Configuração do Backend HTTP
  backend "http" {
    update_method = "PUT"
    # Não colocamos a URL aqui por segurança.
    # Vamos passar ela via variável no Bitbucket.
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key = base64decode(var.private_key)
  region       = var.region
}
