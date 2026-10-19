-- STEP 4b — Grant the API's managed identity READ-ONLY access (least privilege).
-- sqlcmd variables supplied by the pipeline from Terraform outputs:
--   $(ApiName)     = web app name (label for the database user)
--   $(ApiClientId) = API managed identity APPLICATION (client) ID — not the object ID
-- WITH SID ... TYPE = E creates the user without any Entra lookup, so the server
-- needs no identity, Directory Readers role or Graph permissions.
-- Drop + recreate keeps this idempotent and self-heals if the identity changes.
SET NOCOUNT ON;

DROP USER IF EXISTS [$(ApiName)];

DECLARE @sid varbinary(16) = CAST(CAST('$(ApiClientId)' AS uniqueidentifier) AS varbinary(16));
DECLARE @sql nvarchar(max) =
  N'CREATE USER [$(ApiName)] WITH SID = ' + CONVERT(nvarchar(max), @sid, 1) + N', TYPE = E;';
EXEC (@sql);

ALTER ROLE db_datareader ADD MEMBER [$(ApiName)];
