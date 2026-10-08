data "azurerm_client_config" "current" {}

# Created by bootstrap — referenced, not managed, so the pipeline needs only RG-scoped rights.
data "azurerm_resource_group" "lab" {
  name = var.lab_rg_name
}

locals {
  location = data.azurerm_resource_group.lab.location
  # Deterministic per-subscription suffix for globally unique names (no random provider/state drift).
  suffix = substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 6)

  tags = {
    workload   = var.prefix
    env        = "lab"
    managed_by = "terraform"
  }
}
