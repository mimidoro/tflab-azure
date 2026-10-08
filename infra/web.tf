# React front end — Static Web Apps Free tier (NZ$0, global edge, managed TLS).
resource "azurerm_static_web_app" "web" {
  name                = "stapp-${var.prefix}-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = var.swa_location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = local.tags
}
