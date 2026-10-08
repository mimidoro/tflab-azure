# Azure SQL logical server — Entra-only auth (no SQL logins/passwords exist).
resource "azurerm_mssql_server" "sql" {
  name                          = "sql-${var.prefix}-${local.suffix}"
  resource_group_name           = data.azurerm_resource_group.lab.name
  location                      = local.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true # F1 App Service can't use VNet integration/private endpoints

  azuread_administrator {
    login_username              = var.sql_admin_group_name
    object_id                   = var.sql_admin_group_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  tags = local.tags
}

# "Allow Azure services" — required for F1 App Service (no fixed outbound IPs / VNet).
# Risk accepted for the lab: network allows any Azure-hosted caller, but Entra-only
# auth still blocks anyone without a database user. Remove for anything real.
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Database via AzAPI because azurerm has no argument for the Azure SQL free offer.
# Free offer: 100k vCore-seconds + 32 GB per month; AutoPause when exhausted = NO overage bill.
resource "azapi_resource" "db" {
  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  name      = "sqldb-${var.prefix}"
  parent_id = azurerm_mssql_server.sql.id
  location  = local.location
  tags      = local.tags

  body = {
    sku = {
      name     = "GP_S_Gen5_2"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 2
    }
    properties = {
      useFreeLimit                     = true
      freeLimitExhaustionBehavior      = "AutoPause"
      autoPauseDelay                   = 60
      minCapacity                      = 0.5
      maxSizeBytes                     = 34359738368 # 32 GB
      requestedBackupStorageRedundancy = "Local"
      zoneRedundant                    = false
    }
  }
}
