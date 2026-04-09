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

$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'backend_python')

$pythonEnvPath = Join-Path (Get-Location) '.env'
$composeEnvPath = Join-Path $root 'infra/.env.compose.local'

if (-not (Test-Path $pythonEnvPath)) {
    throw "Arquivo local ausente: $pythonEnvPath. Execute scripts/bootstrap-local-config.ps1 e preencha os placeholders."
}

$pythonEnv = Import-SimpleEnvFile -Path $pythonEnvPath
$pythonEnv.GetEnumerator() | ForEach-Object {
    Set-Item -Path "Env:$($_.Key)" -Value ([string]$_.Value)
}
$internalApiKey = if ($pythonEnv.ContainsKey('TRANSCRIPTION_INTERNAL_API_KEY')) {
    [string]$pythonEnv['TRANSCRIPTION_INTERNAL_API_KEY']
}
else {
    ''
}
if (Test-PlaceholderValue $internalApiKey) {
    throw "backend_python/.env ainda contém placeholder em TRANSCRIPTION_INTERNAL_API_KEY."
}

$ollamaPort = '11435'
if (Test-Path $composeEnvPath) {
    $composeEnv = Import-SimpleEnvFile -Path $composeEnvPath
    if ($composeEnv.ContainsKey('OLLAMA_HOST_PORT')) {
        $ollamaPort = [string]$composeEnv['OLLAMA_HOST_PORT']
    }
}

$env:OLLAMA_BASE_URL = if ($env:OLLAMA_BASE_URL) { $env:OLLAMA_BASE_URL } else { "http://127.0.0.1:$ollamaPort" }

if (-not (Test-Path '.venv')) {
    python -m venv .venv
}

& .\.venv\Scripts\python -m pip install -r requirements.txt
& .\.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8001
