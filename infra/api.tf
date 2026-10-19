# .NET Web API — App Service Linux F1 (Free). Limits: 60 CPU-min/day, no Always On, cold starts.
resource "azurerm_service_plan" "plan" {
  name                = "asp-${var.prefix}-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = local.location
  os_type             = "Linux"
  sku_name            = "F1"
  tags                = local.tags
}

# User-assigned identity: ARM exposes client_id directly (no Microsoft Graph lookup),
# and it survives web app recreation, so the SQL user's SID stays valid.
resource "azurerm_user_assigned_identity" "api" {
  name                = "id-${var.prefix}-api-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_linux_web_app" "api" {
  name                = "app-${var.prefix}-api-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.lab.name
  location            = local.location
  service_plan_id     = azurerm_service_plan.plan.id
  https_only          = true

  # Deploy via Entra/RBAC only — no publish-profile passwords.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type         = "UserAssigned" # used to reach Azure SQL; no secrets
    identity_ids = [azurerm_user_assigned_identity.api.id]
  }

  site_config {
    always_on           = false # mandatory on F1
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    http2_enabled       = true

    application_stack {
      dotnet_version = "10.0"
    }

    cors {
      allowed_origins = ["https://${azurerm_static_web_app.web.default_host_name}"]
    }
  }

  # Non-secret: identity-based auth, no password in the string.
  connection_string {
    name  = "LabDb"
    type  = "SQLAzure"
    value = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Database=${azapi_resource.db.name};Authentication=Active Directory Managed Identity;User Id=${azurerm_user_assigned_identity.api.client_id};Encrypt=True;TrustServerCertificate=False;Connect Timeout=60;"
  }

  app_settings = {
    ASPNETCORE_ENVIRONMENT = "Production"
  }

  tags = local.tags
}
