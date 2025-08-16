
param(
	[switch]$IncludeTests
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Try to read name/version from info.toml; fall back to folder name / 0.0.0
$tomlPath = Join-Path $root 'info.toml'
if (-not (Test-Path $tomlPath)) {
	$name = Split-Path $root -Leaf
	$version = '0.0.0'
} else {
	$toml = Get-Content $tomlPath | Out-String
	$name = ($toml | Select-String -Pattern 'name\s*=\s*"(.*?)"').Matches.Groups[1].Value
	if (-not $name) { $name = Split-Path $root -Leaf }
	$version = ($toml | Select-String -Pattern 'version\s*=\s*"(.*?)"').Matches.Groups[1].Value
	if (-not $version) { $version = '0.0.0' }
}

# Sanitize name for filename and get folder name
$safeName = $name.ToLower() -replace '\s+', '-'
$folderName = Split-Path $root -Leaf

# Output filenames
$versionedOutput = "$safeName-v$version.op"
$simpleOutput = "$folderName.op"

# Files / folders to include if present
$items = @(
	'Main.as',
	'UI.as',
	'MainUI.as',
	'info.toml',
	'assets',
	'README.md',
	'CHANGELOG.md'
)
if ($IncludeTests) { $items += 'tests' }

$stage = Join-Path $root '.stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

foreach ($item in $items) {
	$src = Join-Path $root $item
	if (Test-Path $src) {
		Copy-Item $src -Destination $stage -Recurse -Force
	}
}

# Create .op (zip) inside plugin folder (simple name) and also a versioned copy in parent
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipPathSimple = Join-Path $root $simpleOutput
if (Test-Path $zipPathSimple) { Remove-Item $zipPathSimple -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPathSimple)

$zipPathVersioned = Join-Path $root '..' $versionedOutput
if (Test-Path $zipPathVersioned) { Remove-Item $zipPathVersioned -Force }
Copy-Item $zipPathSimple -Destination $zipPathVersioned

Remove-Item $stage -Recurse -Force
Write-Host "Created $zipPathSimple and $zipPathVersioned"
