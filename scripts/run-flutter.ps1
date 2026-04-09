Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'app_flutter')

flutter pub get
flutter run -d windows
