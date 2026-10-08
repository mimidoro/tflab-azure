# Consumed by the deploy workflow (db, api, web jobs).
output "api_name" { value = azurerm_linux_web_app.api.name }
output "api_hostname" { value = azurerm_linux_web_app.api.default_hostname }
output "api_principal_id" { value = azurerm_linux_web_app.api.identity[0].principal_id }
output "web_name" { value = azurerm_static_web_app.web.name }
output "web_hostname" { value = azurerm_static_web_app.web.default_host_name }
output "sql_server_name" { value = azurerm_mssql_server.sql.name }
output "sql_fqdn" { value = azurerm_mssql_server.sql.fully_qualified_domain_name }
output "db_name" { value = azapi_resource.db.name }
