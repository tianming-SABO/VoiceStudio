param([string]$BackupDate = "20261019")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$work = Join-Path $env:RUNNER_TEMP "voicestudio-toolchain"
$out = Join-Path $env:GITHUB_WORKSPACE "backup-output-toolchain"
Remove-Item $work,$out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work,$out | Out-Null

function Get-Verified([string]$Url, [string]$Path, [string]$ExpectedSha) {
  Invoke-WebRequest -Uri $Url -OutFile $Path
  $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
  if ($actual -ne $ExpectedSha.ToLowerInvariant()) { throw "SHA256 mismatch for $(Split-Path $Path -Leaf): $actual" }
}

$bunZip = Join-Path $work "bun-windows-x64-1.4.2.zip"
Get-Verified "https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-windows-x64.zip" $bunZip "ce4c17497b2f29712a99d3d53f028de28cd42e3bacb8589599e7f000e49b6405"

$uvZip = Join-Path $work "uv-x86_64-pc-windows-msvc-0.12.13.zip"
Get-Verified "https://github.com/astral-sh/uv/releases/download/0.12.13/uv-x86_64-pc-windows-msvc.zip" $uvZip "a86c9dc7bad9b03f388583b7187c05fe9951c2e0d392217e8fd43d97787f6ec2"

$nodeSums = Join-Path $work "NODE-SHASUMS256.txt"
Invoke-WebRequest "https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt" -OutFile $nodeSums
$entry = Get-Content $nodeSums | Where-Object { $_ -match 'node-v[0-9.]+-win-x64\.zip$' } | Select-Object -First 1
if (-not $entry) { throw "Node 22 Windows x64 archive not found" }
$nodeSha = ($entry -split '\s+')[0].ToLowerInvariant()
$nodeName = ($entry -split '\s+')[-1]
$nodeVersion = [regex]::Match($nodeName, 'node-v([0-9.]+)-').Groups[1].Value
$nodeZip = Join-Path $work $nodeName
Get-Verified "https://nodejs.org/dist/latest-v22.x/$nodeName" $nodeZip $nodeSha

$uvDir = Join-Path $work "uv"
Expand-Archive $uvZip -DestinationPath $uvDir
$uvExe = Get-ChildItem $uvDir -Filter "uv.exe" -Recurse | Select-Object -First 1
if (-not $uvExe) { throw "uv.exe missing" }
$env:UV_PYTHON_INSTALL_DIR = Join-Path $work "managed-python"
& $uvExe.FullName python install 3.11
if ($LASTEXITCODE -ne 0) { throw "uv managed Python install failed" }
$pythonExe = Get-ChildItem $env:UV_PYTHON_INSTALL_DIR -Filter "python.exe" -Recurse | Select-Object -First 1
if (-not $pythonExe) { throw "Managed Python executable missing" }
$pythonVersion = (& $pythonExe.FullName --version 2>&1).ToString().Trim()

$bunDir = Join-Path $work "bun"
Expand-Archive $bunZip -DestinationPath $bunDir
$bunExe = Get-ChildItem $bunDir -Filter "bun.exe" -Recurse | Select-Object -First 1
if (-not $bunExe) { throw "bun.exe missing" }
$bunVersion = (& $bunExe.FullName --version).Trim()
if ($bunVersion -ne "1.4.2") { throw "Unexpected Bun version $bunVersion" }

$nodeDir = Join-Path $work "node"
Expand-Archive $nodeZip -DestinationPath $nodeDir
$nodeExe = Get-ChildItem $nodeDir -Filter "node.exe" -Recurse | Select-Object -First 1
if (-not $nodeExe) { throw "node.exe missing" }
$nodeObserved = (& $nodeExe.FullName --version).Trim()

$bundle = Join-Path $work "VoiceStudio-Windows-Toolchain"
New-Item -ItemType Directory -Force $bundle | Out-Null
Copy-Item $bunZip,$uvZip,$nodeZip,$nodeSums $bundle
Copy-Item $env:UV_PYTHON_INSTALL_DIR (Join-Path $bundle "managed-python") -Recurse -Force

$meta = [ordered]@{
  schemaVersion = 1
  date = "2026-10-19"
  bun = [ordered]@{ version = "1.4.2"; archive = (Split-Path $bunZip -Leaf); sha256 = (Get-FileHash -Algorithm SHA256 $bunZip).Hash.ToLowerInvariant(); runtimeObserved = $bunVersion }
  uv = [ordered]@{ version = "0.12.13"; archive = (Split-Path $uvZip -Leaf); sha256 = (Get-FileHash -Algorithm SHA256 $uvZip).Hash.ToLowerInvariant() }
  node = [ordered]@{ version = $nodeVersion; archive = $nodeName; sha256 = $nodeSha; runtimeObserved = $nodeObserved }
  managedPython = [ordered]@{ requested = "3.11"; runtimeObserved = $pythonVersion; installedBy = "uv 0.12.13" }
  limitation = "Preserves runtimes/tooling, not the complete Python wheel cache, Rust/MSVC toolchains, FFmpeg binaries, or model weights."
}
$meta | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $bundle "TOOLCHAIN_METADATA.json")

$archive = Join-Path $out "VoiceStudio-Windows-Toolchain-$BackupDate.tar.gz"
tar.exe -C $work -czf $archive "VoiceStudio-Windows-Toolchain"
if ($LASTEXITCODE -ne 0) { throw "Toolchain archive creation failed" }
$hashLine = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant() + "  " + (Split-Path $archive -Leaf)
$hashLine | Set-Content -Encoding ascii (Join-Path $out "VoiceStudio-Windows-Toolchain-$BackupDate.tar.gz.sha256")
Copy-Item (Join-Path $bundle "TOOLCHAIN_METADATA.json") (Join-Path $out "TOOLCHAIN_METADATA.json")
