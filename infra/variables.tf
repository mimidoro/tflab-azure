variable "prefix" {
  description = "Short workload prefix used in resource names."
  type        = string
  default     = "tflab"
}

variable "lab_rg_name" {
  description = "Lab resource group (created by bootstrap; pipeline is scoped to it)."
  type        = string
}

variable "swa_location" {
  description = "Static Web Apps region. SWA is not offered in Australia East; content is served from the global edge regardless."
  type        = string
  default     = "eastasia"
}

variable "sql_admin_group_name" {
  description = "Entra group display name that is the Azure SQL admin (bootstrap)."
  type        = string
}

variable "sql_admin_group_object_id" {
  description = "Entra group object ID that is the Azure SQL admin (bootstrap)."
  type        = string
}
