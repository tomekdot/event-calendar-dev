# Verifies the release artifact for basic integrity.
$ErrorActionPreference = 'Stop'

# Set working directory to script location
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path (Join-Path $root '..') 'dist'
$opFiles = Get-ChildItem -Path $distDir -Filter '*.op'

# Check if the artifact exists
if ($opFiles.Count -eq 0) {
    Write-Error "Artifact not found in: $distDir"
    exit 2
}

$opPath = $opFiles[0].FullName

# Check the artifact size (must be at least 1KB)
$size = (Get-Item $opPath).Length
if ($size -lt 1024) {
    Write-Error "Artifact too small (<1KB): $size bytes"
    exit 3
}

# Check if the artifact is a valid ZIP file and list its contents
Add-Type -AssemblyName System.IO.Compression.FileSystem
$entries = [System.IO.Compression.ZipFile]::OpenRead($opPath).Entries | Select-Object -ExpandProperty FullName
Write-Host "Artifact OK: $opPath ($size bytes)"
Write-Host "Contains:"
$entries | ForEach-Object { Write-Host " - $_" }

# All checks passed
exit 0
