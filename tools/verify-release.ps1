$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$opPath = Join-Path $root '..' 'event-calendar-dev.op'

if (-not (Test-Path $opPath)) {
    Write-Error "Artifact not found: $opPath"
    exit 2
}

$size = (Get-Item $opPath).Length
if ($size -lt 1024) {
    Write-Error "Artifact too small (<1KB): $size bytes"
    exit 3
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$entries = [System.IO.Compression.ZipFile]::OpenRead($opPath).Entries | Select-Object -ExpandProperty FullName
Write-Host "Artifact OK: $opPath ($size bytes)"
Write-Host "Contains:"
$entries | ForEach-Object { Write-Host " - $_" }

exit 0
