Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-SimpleEnvFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $values = @{}
    foreach ($rawLine in Get-Content $Path) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $separator = $line.IndexOf('=')
        if ($separator -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        $values[$key] = $value
    }

    return $values
}

function Test-PlaceholderValue {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    return $normalized.Contains('change_me') -or
        $normalized.Contains('replace_with') -or
        $normalized.Contains('troque') -or
        $normalized.Contains('dev_only')
}

function Wait-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $client = $null
        try {
            $client = [System.Net.Sockets.TcpClient]::new()
            $connectTask = $client.ConnectAsync($HostName, $Port)
            if ($connectTask.Wait(1000) -and $client.Connected) {
                return
            }
        }
        catch {
        }
        finally {
            if ($client) {
                $client.Dispose()
            }
        }

        Start-Sleep -Seconds 2
    }

    throw "Timeout aguardando $HostName`:$Port"
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$localAppSettingsPath = Join-Path $root 'backend_dotnet/src/WebApi/appsettings.Development.local.json'
$composeEnvPath = Join-Path $root 'infra/.env.compose.local'

if (-not (Test-Path $localAppSettingsPath)) {
    throw "Arquivo local ausente: $localAppSettingsPath. Execute scripts/bootstrap-local-config.ps1 e preencha os placeholders."
}

if (-not (Test-Path $composeEnvPath)) {
    throw "Arquivo local ausente: $composeEnvPath. Execute scripts/bootstrap-local-config.ps1 e preencha os placeholders."
}

$localAppSettings = Get-Content $localAppSettingsPath -Raw | ConvertFrom-Json
$connectionString = [string]$localAppSettings.ConnectionStrings.Default
$jwtKey = [string]$localAppSettings.Jwt.Key
$internalApiKey = [string]$localAppSettings.PythonTranscription.InternalApiKey

if ((Test-PlaceholderValue $connectionString) -or (Test-PlaceholderValue $jwtKey) -or (Test-PlaceholderValue $internalApiKey)) {
    throw "appsettings.Development.local.json ainda contém placeholders. Preencha ConnectionStrings:Default, Jwt:Key e PythonTranscription:InternalApiKey."
}

$composeEnv = Import-SimpleEnvFile -Path $composeEnvPath
$postgresPort = if ($composeEnv.ContainsKey('POSTGRES_HOST_PORT')) {
    [int]$composeEnv['POSTGRES_HOST_PORT']
}
else {
    55432
}

$env:ASPNETCORE_ENVIRONMENT = 'Development'

Wait-TcpPort -HostName '127.0.0.1' -Port $postgresPort -TimeoutSeconds 120

dotnet ef database update --project backend_dotnet/src/Infrastructure --startup-project backend_dotnet/src/WebApi
dotnet run --project backend_dotnet/src/WebApi --launch-profile WebApi
