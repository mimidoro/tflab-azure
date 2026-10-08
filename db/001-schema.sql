-- STEP 4a — Schema + seed. Idempotent. Run by the pipeline as the SQL admin group.
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.Greeting', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Greeting
    (
        Id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Greeting PRIMARY KEY,
        Message    NVARCHAR(200)     NOT NULL,
        CreatedUtc DATETIME2(0)      NOT NULL CONSTRAINT DF_Greeting_CreatedUtc DEFAULT SYSUTCDATETIME()
    );
END;

IF NOT EXISTS (SELECT 1 FROM dbo.Greeting)
    INSERT dbo.Greeting (Message) VALUES (N'Hello from Azure SQL');
