Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$mappings = @(
    @{
        Source = 'infra/.env.compose.example'
        Target = 'infra/.env.compose.local'
    },
    @{
        Source = 'backend_python/.env.example'
        Target = 'backend_python/.env'
    },
    @{
        Source = 'backend_dotnet/src/WebApi/appsettings.Development.local.example.json'
        Target = 'backend_dotnet/src/WebApi/appsettings.Development.local.json'
    }
)

foreach ($mapping in $mappings) {
    $sourcePath = Join-Path $root $mapping.Source
    $targetPath = Join-Path $root $mapping.Target

    if (Test-Path $targetPath) {
        Write-Host "Mantido: $targetPath"
        continue
    }

    Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    Write-Host "Criado: $targetPath"
}

Write-Host ''
Write-Host 'Preencha os placeholders nos arquivos locais antes de iniciar o stack.'
