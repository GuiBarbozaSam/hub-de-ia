Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$profile = if ($args.Length -gt 0 -and $args[0]) { $args[0] } else { 'balanced' }
$includeCompatibility = $false

if ($args.Length -gt 1 -and $args[1] -eq '--include-compatibility') {
    $includeCompatibility = $true
}

docker compose -f infra\docker-compose.yml up -d ollama
if ($includeCompatibility) {
    docker compose -f infra\docker-compose.yml run --rm -e OLLAMA_PULL_PROFILE=$profile ollama-init --include-compatibility
}
else {
    docker compose -f infra\docker-compose.yml run --rm -e OLLAMA_PULL_PROFILE=$profile ollama-init
}
