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
        $normalized.Contains('troque')
}

function Wait-HttpOk {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return
            }
        }
        catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "Timeout aguardando $Url"
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$composeFile = Join-Path $root 'infra/docker-compose.yml'
$composeEnvFile = Join-Path $root 'infra/.env.compose.local'
$localDotnetSettings = Join-Path $root 'backend_dotnet/src/WebApi/appsettings.Development.local.json'
$localPythonEnv = Join-Path $root 'backend_python/.env'

if (-not (Test-Path $composeEnvFile)) {
    throw "Arquivo local ausente: $composeEnvFile. Execute scripts/bootstrap-local-config.ps1 e preencha os placeholders."
}

if (-not (Test-Path $localDotnetSettings)) {
    throw "Arquivo local ausente: $localDotnetSettings. Execute scripts/bootstrap-local-config.ps1 e preencha os placeholders."
}

if (-not (Test-Path $localPythonEnv)) {
    throw "Arquivo local ausente: $localPythonEnv. Execute scripts/bootstrap-local-config.ps1 e preencha os placeholders."
}

$composeEnv = Import-SimpleEnvFile -Path $composeEnvFile
$postgresPassword = if ($composeEnv.ContainsKey('POSTGRES_PASSWORD')) {
    [string]$composeEnv['POSTGRES_PASSWORD']
}
else {
    ''
}
if (Test-PlaceholderValue $postgresPassword) {
    throw "infra/.env.compose.local ainda contém placeholder em POSTGRES_PASSWORD."
}

$profile = if ($env:OLLAMA_PULL_PROFILE) { $env:OLLAMA_PULL_PROFILE } else { 'balanced' }

docker compose --env-file $composeEnvFile -f $composeFile up -d postgres ollama
docker compose --env-file $composeEnvFile -f $composeFile run --rm -e OLLAMA_PULL_PROFILE=$profile ollama-init

Start-Process powershell -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-python.ps1'))
Wait-HttpOk -Url 'http://127.0.0.1:8001/health' -TimeoutSeconds 180

Start-Process powershell -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-dotnet.ps1'))
Wait-HttpOk -Url 'http://127.0.0.1:5045/health' -TimeoutSeconds 180

Start-Process powershell -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run-flutter.ps1'))
