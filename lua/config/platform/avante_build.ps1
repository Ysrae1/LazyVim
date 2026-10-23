#requires -Version 5.1
<# Build all pinned Avante modules for the Neovim process architecture. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$BuildDirectory
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath($Source)
$buildRoot = [IO.Path]::GetFullPath($BuildDirectory)
if ($buildRoot.StartsWith('\\')) { throw 'Use a local Windows Cargo build directory.' }
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'crates\avante-html2md\Cargo.toml') -PathType Leaf)) {
    throw 'The pinned Avante source with all four native modules is required.'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'Cargo.lock') -PathType Leaf)) {
    throw 'Avante Cargo.lock is required; unlocked dependency resolution is not allowed.'
}
if ($env:VSCMD_ARG_TGT_ARCH -ne $Architecture) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Avante native builds require Visual Studio C++ build tools.' }
    $installation = & $vswhere -latest -products '*' -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Visual Studio C++ build tools were not found.' }
    $dev = Join-Path ([string]$installation) 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $dev)) { throw 'Visual Studio VsDevCmd.bat was not found.' }
    $hostArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
    $environmentLines = & $env:ComSpec /d /s /c ('"' + $dev + '" -no_logo -arch=' + $Architecture + ' -host_arch=' + $hostArchitecture + ' >nul && set')
    if ($LASTEXITCODE -ne 0) { throw ('Cannot initialize the MSVC ' + $Architecture + ' development environment.') }
    foreach ($line in $environmentLines) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
    if ($env:VSCMD_ARG_TGT_ARCH -ne $Architecture) { throw 'MSVC initialized an unexpected target architecture.' }
}
$cargoCommand = Get-Command cargo.exe -ErrorAction SilentlyContinue
$cargo = if ($cargoCommand) { $cargoCommand.Source } else { $null }
if (-not $cargo) {
    foreach ($candidate in @($(if ($env:CARGO_HOME) { Join-Path $env:CARGO_HOME 'bin\cargo.exe' }), (Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'))) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { $cargo = $candidate; break }
    }
}
if (-not $cargo) { throw 'Avante native builds require Rust Cargo on PATH or in CARGO_HOME/bin.' }
$triple = if ($Architecture -eq 'arm64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }
$expectedMachine = if ($Architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
$modules = @('tokenizers', 'templates', 'repo_map', 'html2md')
$null = New-Item -ItemType Directory -Path $buildRoot -Force
$savedTarget = $env:CARGO_TARGET_DIR
$savedPath = $env:PATH
$process = $null
$stdoutFile = $null
$stderrFile = $null
$receiptPath = Join-Path $buildRoot 'avante-native-build.json'
$receipt = [ordered]@{ state = 'running'; architecture = $Architecture; target = $triple;
    source = $sourceRoot; cargo_lock_sha256 = (Get-FileHash (Join-Path $sourceRoot 'Cargo.lock') -Algorithm SHA256).Hash.ToLowerInvariant();
    started_utc = [DateTime]::UtcNow.ToString('o'); pid = $null; exit_code = $null; artifacts = @() }
function Save-Receipt {
    [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
function Get-Machine([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw 'Native output is not a PE file.' }
    $offset = [BitConverter]::ToInt32($bytes, 60)
    if ($offset -lt 0 -or ($offset + 6) -gt $bytes.Length) { throw 'Invalid native PE offset.' }
    return [BitConverter]::ToUInt16($bytes, $offset + 4)
}
try {
    $env:CARGO_TARGET_DIR = $buildRoot
    # Git's POSIX link.exe is not the MSVC linker.
    $env:PATH = (@($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch '(?i)[\\/]Git[\\/]usr[\\/]bin[\\/]?$' }) -join ';')
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $cargo
    $start.Arguments = 'build --release --locked --target ' + $triple + ' --features luajit -p avante-tokenizers -p avante-templates -p avante-repo-map -p avante-html2md -j4'
    $start.WorkingDirectory = $sourceRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $stdoutFile = [IO.File]::Open((Join-Path $buildRoot 'avante-native.stdout.log'), 'Create', 'Write', 'Read')
    $stderrFile = [IO.File]::Open((Join-Path $buildRoot 'avante-native.stderr.log'), 'Create', 'Write', 'Read')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Cannot start Avante Cargo build.' }
    $receipt.pid = $process.Id
    Save-Receipt
    $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
    $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrFile)
    if (-not $process.WaitForExit(2700000)) {
        # Only this helper's Cargo process and its compiler descendants are owned.
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        $null = $process.WaitForExit(5000)
        throw 'Avante build exceeded 45 minutes; see the preserved native build logs.'
    }
    $receipt.exit_code = $process.ExitCode
    $receipt.output_drained = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000)
    if (-not $receipt.output_drained -or $receipt.exit_code -ne 0) { throw 'Avante native build failed; see avante-native.stderr.log.' }
    foreach ($module in $modules) {
        $path = Join-Path $buildRoot ($triple + '\release\avante_' + $module + '.dll')
        if ((Get-Machine $path) -ne $expectedMachine) { throw ('Avante architecture mismatch: ' + $module) }
        $receipt.artifacts += @{ path = $path; sha256 = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = (Get-Item $path).Length }
    }
    # Check every module before changing the plugin's build outputs. Installed
    # user DLLs should be backed up by the caller before invoking this helper.
    $destination = Join-Path $sourceRoot 'build'
    $null = New-Item -ItemType Directory -Path $destination -Force
    foreach ($artifact in $receipt.artifacts) {
        Copy-Item -LiteralPath $artifact.path -Destination $destination -Force
    }
    $receipt.state = 'built'
}
catch {
    $receipt.state = 'failed'
    $receipt.error = $_.ToString()
    throw
}
finally {
    $env:CARGO_TARGET_DIR = $savedTarget
    $env:PATH = $savedPath
    if ($stdoutFile) { $stdoutFile.Dispose() }
    if ($stderrFile) { $stderrFile.Dispose() }
    if ($process) { $process.Dispose() }
    $receipt.completed_utc = [DateTime]::UtcNow.ToString('o')
    Save-Receipt
}
Write-Output $receiptPath
