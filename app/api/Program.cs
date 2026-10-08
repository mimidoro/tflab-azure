using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Liveness probe for the smoke test (no DB call — keeps the free DB paused when idle).
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

// Hello world: proves front end -> API -> Azure SQL (via managed identity) end to end.
app.MapGet("/api/hello", async (IConfiguration config, ILogger<Program> log, CancellationToken ct) =>
{
    // In Azure: App Service connection string "LabDb" (Managed Identity, no password).
    // Locally: set ConnectionStrings__LabDb with "Authentication=Active Directory Default".
    var cs = config.GetConnectionString("LabDb");
    if (string.IsNullOrWhiteSpace(cs))
        return Results.Ok(new { message = "Hello from .NET API", db = "not configured" });

    try
    {
        await using var conn = new SqlConnection(cs);
        await conn.OpenAsync(ct);
        await using var cmd = new SqlCommand("SELECT TOP (1) Message FROM dbo.Greeting ORDER BY Id;", conn);
        var dbMessage = await cmd.ExecuteScalarAsync(ct) as string;
        return Results.Ok(new { message = "Hello from .NET API", db = dbMessage ?? "no rows" });
    }
    catch (SqlException ex)
    {
        // Free-offer DB auto-pauses; first call after idle can take ~1 minute to resume.
        log.LogError(ex, "Database call failed");
        return Results.Problem(
            title: "Database unavailable",
            detail: "The database may be resuming from auto-pause. Retry in about a minute.",
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.Run();
