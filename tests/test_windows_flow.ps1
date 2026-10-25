# Offline behavior tests for Windows PowerShell 5.1; no installer is executed.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$tokens = $null
$errors = $null
$source = Join-Path (Split-Path -Parent $PSScriptRoot) "install-codex.ps1"
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "Installer parse failed." }
$names = @("Confirm-CodexVersion", "Get-StandaloneCodexTarget", "Get-RequestedCodexVersion", "Get-NpmRelease", "Test-SamePath", "Get-NormalizedFullPath")
foreach ($name in $names) {
    $matches = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($matches.Count -ne 1) { throw "Expected one function: $name" }
    . ([scriptblock]::Create($matches[0].Extent.Text))
}

# Substitute only command discovery and native process execution.
function Write-Step { param([string]$Message) }
function Write-Success { param([string]$Message) }
function Get-PreferredCodexCommand { return $script:PreferredTarget }
function Invoke-NativeCommand {
    param([string]$Path, [string[]]$Arguments, [string]$DisplayName)
    return [pscustomobject]@{ ExitCode = $script:VersionExit; Output = $script:VersionOutput }
}
$directory = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-flow-test-" + [guid]::NewGuid().ToString("N"))
$script:ValidatedCodexInstallDir = $directory
$script:PreferredTarget = Join-Path $directory "codex.exe"
try {
    New-Item -ItemType Directory -Path $directory | Out-Null
    New-Item -ItemType File -Path $script:PreferredTarget | Out-Null
    $cases = @(
        @{ Release = "latest"; Output = "codex-cli 0.164.0"; Success = $true },
        @{ Release = "latest"; Output = "warning: PATH notice`r`ncodex-cli 0.164.0`r`n"; Success = $true },
        @{ Release = "0.164.0"; Output = "codex-cli 0.164.0"; Success = $true },
        @{ Release = "rust-v0.164.0"; Output = "codex-cli 0.164.0"; Success = $true },
        @{ Release = "0.164.0-alpha.1"; Output = "codex-cli 0.164.0-alpha.1"; Success = $true },
        @{ Release = "latest"; Output = "not a Codex version"; Success = $false },
        @{ Release = "latest"; Output = "some-other-cli 0.164.0"; Success = $false },
        @{ Release = "latest"; Output = "codex-cli 0.164.0 extra"; Success = $false },
        @{ Release = "latest"; Output = ""; Success = $false },
        @{ Release = "latest"; Output = "codex-cli 0.164.0`ncodex-cli 0.165.0"; Success = $false },
        @{ Release = "0.164.0"; Output = "codex-cli 0.164.0-alpha.1"; Success = $false },
        @{ Release = "0.164.0"; Output = "warning: requested 0.164.0`ncodex-cli 0.163.0"; Success = $false }
    )
    foreach ($case in $cases) {
        $script:VersionOutput = $case.Output
        $script:VersionExit = 0
        $passed = $false
        try {
            $null = Confirm-CodexVersion -Method standalone -RequestedRelease $case.Release
            $passed = $true
        } catch {
            if ($case.Success) { throw }
        }
        if ($passed -ne $case.Success) { throw "Unexpected version result: $($case.Release) / $($case.Output)" }
    }
    $script:VersionOutput = "codex-cli 0.164.0"
    $script:VersionExit = 1
    $failed = $false
    try { $null = Confirm-CodexVersion -Method standalone -RequestedRelease latest } catch { $failed = $true }
    if (-not $failed) { throw "Nonzero version exit was accepted." }
    $script:VersionExit = 0
    $script:PreferredTarget = Join-Path $directory "other-codex.exe"
    $failed = $false
    try { $null = Confirm-CodexVersion -Method standalone -RequestedRelease latest } catch { $failed = $true }
    if (-not $failed) { throw "PATH conflict was accepted." }
    Write-Host "PASS: $($cases.Count + 2) Windows installer version/PATH behavior cases."
} finally {
    Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
}
