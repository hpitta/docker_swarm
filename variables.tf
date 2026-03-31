variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key" {}
variable "region" {}
variable "compartment_ocid" {}

# A estrela da vez:
variable "subnet_ocid" {
  description = "OCID da Subnet passado pelo Bitbucket"
  type        = string
}

# Outras variáveis necessárias
variable "image_ocid" {
  description = "OCID da imagem Oracle Linux"
  type        = string
}

variable "availability_domain" {
  description = "Availability Domain (ex: Uocm:SA-SAOPAULO-1-AD-1)"
  type        = string
}

variable "ssh_public_key" {
  description = "Chave Publica SSH"
  type        = string
}
