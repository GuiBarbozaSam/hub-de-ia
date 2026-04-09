Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$gitleaksConfig = Join-Path $root '.gitleaks.toml'
$reportPath = Join-Path $root '.tmp/gitleaks-report.json'
$localToolRoot = Join-Path $root '.tmp/tools/gitleaks'
$localGitleaks = Join-Path $localToolRoot 'gitleaks.exe'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null
$commonArgs = @(
    'detect',
    '--source', $root,
    '--no-git',
    '--redact',
    '--report-format', 'json',
    '--report-path', $reportPath
)

if (Test-Path $gitleaksConfig) {
    $commonArgs += @('--config', $gitleaksConfig)
}

if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    & gitleaks @commonArgs
    exit $LASTEXITCODE
}

if (Test-Path $localGitleaks) {
    & $localGitleaks @commonArgs
    exit $LASTEXITCODE
}

try {
    $ProgressPreference = 'SilentlyContinue'
    New-Item -ItemType Directory -Force -Path $localToolRoot | Out-Null
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/gitleaks/gitleaks/releases/latest'
    $asset = $release.assets | Where-Object { $_.name -match 'windows_x64\.zip$' } | Select-Object -First 1
    if (-not $asset) {
        throw 'Asset windows_x64.zip não encontrado.'
    }

    $zipPath = Join-Path $localToolRoot $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $localToolRoot -Force
    & $localGitleaks @commonArgs
    exit $LASTEXITCODE
}
catch {
    Write-Warning "Falha ao baixar/executar gitleaks localmente. Tentando fallback via Docker. Detalhe: $($_.Exception.Message)"
}

$dockerArgs = @(
    'run',
    '--rm',
    '-v', "${root}:/repo",
    '-w', '/repo',
    'zricethezav/gitleaks:latest',
    'detect',
    '--source', '/repo',
    '--no-git',
    '--redact',
    '--report-format', 'json',
    '--report-path', '/repo/.tmp/gitleaks-report.json'
)

if (Test-Path $gitleaksConfig) {
    $dockerArgs += @('--config', '/repo/.gitleaks.toml')
}

& docker @dockerArgs
exit $LASTEXITCODE
