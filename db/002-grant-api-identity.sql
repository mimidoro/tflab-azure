-- STEP 4b — Grant the API's managed identity READ-ONLY access (least privilege).
-- sqlcmd variables supplied by the pipeline from Terraform outputs:
--   $(ApiName)        = web app name (MI display name)
--   $(ApiPrincipalId) = web app MI object ID
-- Drop + recreate keeps this idempotent AND self-heals if the web app is recreated
-- (new identity, same name). WITH OBJECT_ID avoids needing Directory Readers on the server.
SET NOCOUNT ON;

DROP USER IF EXISTS [$(ApiName)];

DECLARE @sid varbinary(16) = CAST(CAST('$(ApiClientId)' AS uniqueidentifier) AS varbinary(16));
DECLARE @sql nvarchar(max) =
  N'CREATE USER [$(ApiName)] WITH SID = ' + CONVERT(nvarchar(max), @sid, 1) + N', TYPE = E;';
EXEC (@sql);

ALTER ROLE db_datareader ADD MEMBER [$(ApiName)];
