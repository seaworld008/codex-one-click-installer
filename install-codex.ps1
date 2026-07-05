# Codex Windows 一键安装脚本
# 支持：Windows 10 / Windows 11；Windows 8 / 8.1 使用旧版官方依赖的兼容路径
# 用法：双击同目录下的「Windows双击安装Codex.cmd」

param(
    [switch]$SkipGit,
    [switch]$SkipPython,
    [switch]$SkipSkills,
    [switch]$SkipCodexApp,
    [switch]$CheckOnly,
    [switch]$VerifyDownloads,
    [switch]$NoPause,
    [switch]$NonInteractive,
    [switch]$UseLatestDependencies,
    [string]$DownloadMirror = "",
    [string]$TestWindowsVersion = "",
    [string]$TestWindowsCaption = "",
    [string]$TestArch = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ========== 公开官方版本配置 ==========
# 默认走“兼容优先”版本。Codex CLI 当前只要求 Node.js >= 16，
# 因此 Windows 10 专业版/企业版/LTSC 上优先安装更稳的 LTS 依赖。
$ModernGitVersion = "2.55.0.2"
$ModernGitTag = "v2.55.0.windows.2"
$ModernNodeVersion = "22.17.0"
$ModernPythonVersion = "3.12.10"

$LatestNodeVersion = "24.18.0"
$LatestPythonVersion = "3.14.6"

$LegacyGitVersion = "2.46.0"
$LegacyGitTag = "v2.46.0.windows.1"
$LegacyNodeVersion = "16.20.2"
$LegacyPythonWin81Version = "3.12.10"
$LegacyPythonWin8Version = "3.8.10"

# ========== 基础路径 ==========
$ScriptDir = Split-Path -Parent $PSCommandPath
$TempRoot = $env:TEMP
if ([string]::IsNullOrWhiteSpace($TempRoot)) { $TempRoot = [IO.Path]::GetTempPath() }
$WorkDir = Join-Path $TempRoot "codex-installer"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$LogFile = Join-Path $WorkDir ("install-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")
$LocalConfigPath = Join-Path $ScriptDir "downloads.local.json"
$LocalConfig = $null
if (Test-Path $LocalConfigPath) {
    $LocalConfig = Get-Content -Raw -Path $LocalConfigPath | ConvertFrom-Json
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "========== $Message ==========" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor DarkCyan
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    if (-not (Test-Admin)) {
        Write-Host "需要管理员权限，正在弹出 UAC 授权窗口..." -ForegroundColor Yellow
        $powerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
        $sysnativePowerShell = Join-Path $env:WINDIR "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
        if (Test-Path $sysnativePowerShell) { $powerShellExe = $sysnativePowerShell }
        if (-not (Test-Path $powerShellExe)) { $powerShellExe = "powershell.exe" }

        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($SkipGit) { $args += " -SkipGit" }
        if ($SkipPython) { $args += " -SkipPython" }
        if ($SkipSkills) { $args += " -SkipSkills" }
        if ($SkipCodexApp) { $args += " -SkipCodexApp" }
        if ($CheckOnly) { $args += " -CheckOnly" }
        if ($VerifyDownloads) { $args += " -VerifyDownloads" }
        if ($NoPause) { $args += " -NoPause" }
        if ($NonInteractive) { $args += " -NonInteractive" }
        if ($UseLatestDependencies) { $args += " -UseLatestDependencies" }
        if (-not [string]::IsNullOrWhiteSpace($DownloadMirror)) { $args += " -DownloadMirror `"$DownloadMirror`"" }

        try {
            Start-Process -FilePath $powerShellExe -ArgumentList $args -Verb RunAs
        } catch {
            throw "无法获取管理员权限。请右键以管理员身份运行，或联系 IT 放行 UAC。详细错误：$($_.Exception.Message)"
        }
        exit
    }
}

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    } catch {}
}

function Get-ConfigValue {
    param(
        [string]$Name,
        [string]$EnvName,
        [string]$DefaultValue = ""
    )

    $envValue = [Environment]::GetEnvironmentVariable($EnvName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($envValue)) { return $envValue.Trim() }

    if ($LocalConfig -and $LocalConfig.PSObject.Properties[$Name]) {
        $localValue = [string]$LocalConfig.$Name
        if (-not [string]::IsNullOrWhiteSpace($localValue)) { return $localValue.Trim() }
    }

    return $DefaultValue
}

function Get-DownloadMirror {
    if (-not [string]::IsNullOrWhiteSpace($DownloadMirror)) {
        $mirror = $DownloadMirror.Trim().ToLowerInvariant()
    } else {
        $mirror = (Get-ConfigValue -Name "DownloadMirror" -EnvName "CODEX_DOWNLOAD_MIRROR" -DefaultValue "china").ToLowerInvariant()
    }

    if ($mirror -notin @("china", "official")) {
        Write-Warning "未知下载源模式：$mirror。已改用 china。可选值：china / official。"
        return "china"
    }
    return $mirror
}

function Get-UrlOverride {
    param([string]$Name, [string]$EnvName)
    return Get-ConfigValue -Name $Name -EnvName $EnvName -DefaultValue ""
}

function New-UrlCandidates {
    param(
        [string]$OverrideUrl,
        [string]$ChinaUrl,
        [string]$OfficialUrl,
        [string]$Mirror
    )

    if (-not [string]::IsNullOrWhiteSpace($OverrideUrl)) {
        return @($OverrideUrl.Trim())
    }

    if ($Mirror -eq "official") {
        return @($OfficialUrl, $ChinaUrl)
    }

    return @($ChinaUrl, $OfficialUrl)
}

function Get-CommandPath {
    param([string]$Command)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-WindowsInfo {
    if (-not [string]::IsNullOrWhiteSpace($TestWindowsVersion)) {
        $caption = $(if (-not [string]::IsNullOrWhiteSpace($TestWindowsCaption)) { $TestWindowsCaption } else { "Microsoft Windows Test" })
        return [pscustomobject]@{
            Caption = $caption
            Version = [version]$TestWindowsVersion
            Architecture = $(if (-not [string]::IsNullOrWhiteSpace($TestArch)) { $TestArch } else { "x64" })
            ProductType = 1
            OperatingSystemSKU = 0
        }
    }

    $caption = ""
    $versionText = ""
    $architecture = ""
    $productType = $null
    $sku = $null

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $caption = [string]$os.Caption
        $versionText = [string]$os.Version
        $architecture = [string]$os.OSArchitecture
        $productType = $os.ProductType
        $sku = $os.OperatingSystemSKU
    } catch {
        try {
            $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
            $caption = [string]$os.Caption
            $versionText = [string]$os.Version
            $architecture = [string]$os.OSArchitecture
            $productType = $os.ProductType
            $sku = $os.OperatingSystemSKU
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($versionText)) {
        $versionText = [Environment]::OSVersion.Version.ToString()
    }
    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    return [pscustomobject]@{
        Caption = $caption
        Version = [version]$versionText
        Architecture = $architecture
        ProductType = $productType
        OperatingSystemSKU = $sku
    }
}

function Get-NormalizedArch {
    if (-not [string]::IsNullOrWhiteSpace($TestArch)) {
        switch -Regex ($TestArch.Trim()) {
            "^(x64|amd64)$" { return "x64" }
            "^arm64$" { return "arm64" }
            default { return "unsupported" }
        }
    }

    $arch = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($arch)) { $arch = $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($arch) {
        "AMD64" { return "x64" }
        "ARM64" { return "arm64" }
        default { return "unsupported" }
    }
}

function Compare-VersionPart {
    param([version]$Version, [int]$Major, [int]$Minor)
    if ($Version.Major -gt $Major) { return 1 }
    if ($Version.Major -lt $Major) { return -1 }
    if ($Version.Minor -gt $Minor) { return 1 }
    if ($Version.Minor -lt $Minor) { return -1 }
    return 0
}

function Get-InstallMode {
    param([pscustomobject]$OsInfo, [string]$Arch)

    if ($Arch -eq "unsupported") {
        throw "当前脚本只支持 x64 / ARM64。Codex 官方 npm 包未发布 32 位 Windows 版本。"
    }

    $v = $OsInfo.Version
    if ($v.Major -ge 10) {
        return [pscustomobject]@{
            Name = "Modern"
            DisplayName = "Windows 10/11 现代路径"
            IsLegacy = $false
            IsWin8 = $false
            IsWin81 = $false
        }
    }

    if ($v.Major -eq 6 -and $v.Minor -eq 3) {
        if ($Arch -ne "x64") { throw "Windows 8.1 兼容路径只支持 x64。" }
        return [pscustomobject]@{
            Name = "LegacyWin81"
            DisplayName = "Windows 8.1 旧版依赖路径"
            IsLegacy = $true
            IsWin8 = $false
            IsWin81 = $true
        }
    }

    if ($v.Major -eq 6 -and $v.Minor -eq 2) {
        if ($Arch -ne "x64") { throw "Windows 8 兼容路径只支持 x64。" }
        return [pscustomobject]@{
            Name = "LegacyWin8"
            DisplayName = "Windows 8 旧版依赖路径"
            IsLegacy = $true
            IsWin8 = $true
            IsWin81 = $false
        }
    }

    throw "不支持的 Windows 版本：$($OsInfo.Caption) $($OsInfo.Version)。请使用 Windows 8/8.1/10/11。"
}

function New-DownloadPlan {
    param(
        [pscustomobject]$Mode,
        [string]$Arch
    )

    $mirror = Get-DownloadMirror

    if ($Mode.IsLegacy) {
        $gitFile = "Git-$LegacyGitVersion-64-bit.exe"
        $nodeFile = "node-v$LegacyNodeVersion-x64.msi"
        $pythonVersion = $(if ($Mode.IsWin81) { $LegacyPythonWin81Version } else { $LegacyPythonWin8Version })
        $pythonFile = "python-$pythonVersion-amd64.exe"
        $gitOfficialUrl = "https://github.com/git-for-windows/git/releases/download/$LegacyGitTag/$gitFile"
        $nodeOfficialUrl = "https://nodejs.org/dist/v$LegacyNodeVersion/$nodeFile"
        $pythonOfficialUrl = "https://www.python.org/ftp/python/$pythonVersion/$pythonFile"
        $gitChinaUrl = "https://npmmirror.com/mirrors/git-for-windows/$LegacyGitTag/$gitFile"
        $nodeChinaUrl = "https://npmmirror.com/mirrors/node/v$LegacyNodeVersion/$nodeFile"
        $pythonChinaUrl = "https://npmmirror.com/mirrors/python/$pythonVersion/$pythonFile"

        $plan = [ordered]@{
            GitUrls = New-UrlCandidates -OverrideUrl (Get-UrlOverride -Name "GitUrl" -EnvName "CODEX_GIT_URL") -ChinaUrl $gitChinaUrl -OfficialUrl $gitOfficialUrl -Mirror $mirror
            NodeUrls = New-UrlCandidates -OverrideUrl (Get-UrlOverride -Name "NodeUrl" -EnvName "CODEX_NODE_URL") -ChinaUrl $nodeChinaUrl -OfficialUrl $nodeOfficialUrl -Mirror $mirror
            PythonUrls = New-UrlCandidates -OverrideUrl (Get-UrlOverride -Name "PythonUrl" -EnvName "CODEX_PYTHON_URL") -ChinaUrl $pythonChinaUrl -OfficialUrl $pythonOfficialUrl -Mirror $mirror
            GitFile = $gitFile
            NodeFile = $nodeFile
            PythonFile = $pythonFile
            RequiredNodeMajor = 16
            RequiredPython = $pythonVersion
            DownloadMirror = $mirror
        }
    } else {
        $defaultNodeVersion = $(if ($UseLatestDependencies) { $LatestNodeVersion } else { $ModernNodeVersion })
        $defaultPythonVersion = $(if ($UseLatestDependencies) { $LatestPythonVersion } else { $ModernPythonVersion })
        $nodeVersion = Get-ConfigValue -Name "NodeVersion" -EnvName "CODEX_NODE_VERSION" -DefaultValue $defaultNodeVersion
        $pythonVersion = Get-ConfigValue -Name "PythonVersion" -EnvName "CODEX_PYTHON_VERSION" -DefaultValue $defaultPythonVersion

        $gitFile = $(if ($Arch -eq "arm64") { "Git-$ModernGitVersion-arm64.exe" } else { "Git-$ModernGitVersion-64-bit.exe" })
        $nodeFile = "node-v$nodeVersion-$Arch.msi"
        $pythonArch = $(if ($Arch -eq "arm64") { "arm64" } else { "amd64" })
        $pythonFile = "python-$pythonVersion-$pythonArch.exe"
        $gitOfficialUrl = "https://github.com/git-for-windows/git/releases/download/$ModernGitTag/$gitFile"
        $nodeOfficialUrl = "https://nodejs.org/dist/v$nodeVersion/$nodeFile"
        $pythonOfficialUrl = "https://www.python.org/ftp/python/$pythonVersion/$pythonFile"
        $gitChinaUrl = "https://npmmirror.com/mirrors/git-for-windows/$ModernGitTag/$gitFile"
        $nodeChinaUrl = "https://npmmirror.com/mirrors/node/v$nodeVersion/$nodeFile"
        $pythonChinaUrl = "https://npmmirror.com/mirrors/python/$pythonVersion/$pythonFile"

        $plan = [ordered]@{
            GitUrls = New-UrlCandidates -OverrideUrl (Get-UrlOverride -Name "GitUrl" -EnvName "CODEX_GIT_URL") -ChinaUrl $gitChinaUrl -OfficialUrl $gitOfficialUrl -Mirror $mirror
            NodeUrls = New-UrlCandidates -OverrideUrl (Get-UrlOverride -Name "NodeUrl" -EnvName "CODEX_NODE_URL") -ChinaUrl $nodeChinaUrl -OfficialUrl $nodeOfficialUrl -Mirror $mirror
            PythonUrls = New-UrlCandidates -OverrideUrl (Get-UrlOverride -Name "PythonUrl" -EnvName "CODEX_PYTHON_URL") -ChinaUrl $pythonChinaUrl -OfficialUrl $pythonOfficialUrl -Mirror $mirror
            GitFile = $gitFile
            NodeFile = $nodeFile
            PythonFile = $pythonFile
            RequiredNodeMajor = 16
            RequiredPython = $pythonVersion
            DownloadMirror = $mirror
        }
    }

    $plan["GitUrl"] = @($plan["GitUrls"])[0]
    $plan["NodeUrl"] = @($plan["NodeUrls"])[0]
    $plan["PythonUrl"] = @($plan["PythonUrls"])[0]
    $plan["SkillsUrl"] = Get-ConfigValue -Name "SkillsUrl" -EnvName "CODEX_SKILLS_URL" -DefaultValue ""
    $plan["CodexAppUrl"] = Get-ConfigValue -Name "CodexAppUrl" -EnvName "CODEX_APP_INSTALLER_URL" -DefaultValue ""
    $defaultNpmRegistry = $(if ($mirror -eq "china") { "https://registry.npmmirror.com" } else { "" })
    $plan["NpmRegistry"] = Get-ConfigValue -Name "NpmRegistry" -EnvName "CODEX_NPM_REGISTRY" -DefaultValue $defaultNpmRegistry
    $plan["CodexBaseUrl"] = Get-ConfigValue -Name "CodexBaseUrl" -EnvName "CODEX_BASE_URL" -DefaultValue ""
    $plan["CodexModel"] = Get-ConfigValue -Name "CodexModel" -EnvName "CODEX_MODEL" -DefaultValue ""

    return [pscustomobject]$plan
}

function Get-UrlFileName {
    param([string]$Url, [string]$Fallback)
    try {
        $uri = [Uri]$Url
        $name = [Uri]::UnescapeDataString([IO.Path]::GetFileName($uri.AbsolutePath))
        if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }
    } catch {}
    return $Fallback
}

function Write-PlanSummary {
    param([pscustomobject]$Plan)

    Write-Step "安装计划"
    Write-Host "下载源模式：$($Plan.DownloadMirror)" -ForegroundColor White
    Write-Host "Git 安装包：$($Plan.GitFile)" -ForegroundColor White
    foreach ($url in @($Plan.GitUrls)) { Write-Host "  - $url" -ForegroundColor DarkGray }
    Write-Host "Node.js 安装包：$($Plan.NodeFile)" -ForegroundColor White
    foreach ($url in @($Plan.NodeUrls)) { Write-Host "  - $url" -ForegroundColor DarkGray }
    Write-Host "Python 安装包：$($Plan.PythonFile)" -ForegroundColor White
    foreach ($url in @($Plan.PythonUrls)) { Write-Host "  - $url" -ForegroundColor DarkGray }
    if (-not [string]::IsNullOrWhiteSpace($Plan.NpmRegistry)) {
        Write-Host "npm registry：$($Plan.NpmRegistry)" -ForegroundColor White
    }
}

function Test-DownloadUrl {
    param(
        [string]$Name,
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 45 -MaximumRedirection 10
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
            Write-Host "$Name 可访问：$Url" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "$Name 当前不可访问：$Url" -ForegroundColor DarkYellow
        Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
    }
    return $false
}

function Test-DownloadPlan {
    param(
        [pscustomobject]$Plan,
        [bool]$IncludeGit,
        [bool]$IncludePython
    )

    Write-Step "下载源可达性检查"
    $checks = New-Object System.Collections.Generic.List[object]
    if ($IncludeGit) { $checks.Add([pscustomobject]@{ Name = "Git for Windows"; Urls = @($Plan.GitUrls) }) }
    $checks.Add([pscustomobject]@{ Name = "Node.js"; Urls = @($Plan.NodeUrls) })
    if ($IncludePython) { $checks.Add([pscustomobject]@{ Name = "Python"; Urls = @($Plan.PythonUrls) }) }

    foreach ($check in $checks) {
        $ok = $false
        foreach ($url in @($check.Urls)) {
            if (Test-DownloadUrl -Name $check.Name -Url $url) {
                $ok = $true
                break
            }
        }
        if (-not $ok) {
            throw "$($check.Name) 所有下载源都不可访问。请检查网络/代理，或在 downloads.local.json 中配置可访问的下载地址。"
        }
    }
}

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string[]]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile
    )
    Write-Step "下载 $Name"
    if (Test-Path $OutFile) {
        $size = (Get-Item $OutFile).Length
        if ($size -gt 1024KB) {
            Write-Host "已存在，跳过下载：$OutFile" -ForegroundColor DarkYellow
            return
        }
    }

    $lastError = $null
    foreach ($candidateUrl in @($Url)) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "来源：$candidateUrl" -ForegroundColor DarkGray
                if ($attempt -gt 1) { Write-Host "第 $attempt 次重试..." -ForegroundColor DarkYellow }
                Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
                Invoke-WebRequest -Uri $candidateUrl -OutFile $OutFile -UseBasicParsing -TimeoutSec 180 -MaximumRedirection 10

                if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -ge 1024KB)) {
                    Write-Host "下载完成：$OutFile" -ForegroundColor Green
                    return
                }
                throw "下载文件过小，可能是错误页或被代理拦截。"
            } catch {
                $lastError = $_.Exception.Message
                Write-Warning "$Name 下载失败：$lastError"
                Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
                Start-Sleep -Seconds (2 * $attempt)
            }
        }

        Write-Warning "$Name 当前来源不可用，尝试下一个来源。"
    }

    throw "下载失败或文件异常：$Name -> $OutFile。最后错误：$lastError"
}

function Start-Installer {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string]$Arguments
    )
    Write-Step "安装 $Name"
    Write-Host "执行：$FilePath $Arguments"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru
    if ($p.ExitCode -notin @(0, 3010, 1641)) {
        throw "$Name 安装失败，ExitCode=$($p.ExitCode)"
    }
    Write-Host "$Name 安装完成" -ForegroundColor Green
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-InstalledVersion {
    param(
        [string]$Command,
        [string]$Arguments = "--version"
    )
    $cmd = Get-CommandPath $Command
    if (-not $cmd) { return $null }
    try {
        $out = & $cmd $Arguments 2>&1
        $text = ($out -join " ")
        if ($text -match "(\d+)\.(\d+)\.(\d+)") {
            return [version]$matches[0]
        }
    } catch {}
    return $null
}

function Test-NodeReady {
    $ver = Get-InstalledVersion -Command "node" -Arguments "-v"
    if ($ver -and $ver.Major -ge 16) { return $true }
    return $false
}

function Test-PythonReady {
    $ver = Get-InstalledVersion -Command "python" -Arguments "--version"
    if ($ver -and $ver.Major -ge 3) { return $true }
    return $false
}

function Get-MaskedUrl {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return ($Value -replace "://[^/@]+@", "://***@")
}

function Invoke-EnvironmentPreflight {
    param(
        [pscustomobject]$OsInfo,
        [string]$Arch,
        [pscustomobject]$Mode
    )

    Write-Step "系统环境预检"
    Write-Host "PowerShell：$($PSVersionTable.PSVersion)" -ForegroundColor White
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Warning "当前 PowerShell 版本较旧。Windows 10 通常自带 5.1；如果后续出现语法或下载异常，请先升级 Windows PowerShell 5.1。"
    }

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Warning "当前在 32 位 PowerShell 进程中运行。脚本会尽量处理，但建议使用 64 位 PowerShell 运行，避免安装路径和注册表重定向问题。"
    }

    if (-not $CheckOnly) {
        if (Test-Admin) {
            Write-Host "管理员权限：已获取" -ForegroundColor Green
        } else {
            Write-Warning "管理员权限：未获取。安装 Git/Node/Python 通常需要管理员权限。"
        }
    } else {
        Write-Host "管理员权限：CheckOnly 模式不要求" -ForegroundColor DarkGray
    }

    if ($OsInfo.ProductType -and ([int]$OsInfo.ProductType -ne 1)) {
        Write-Warning "当前看起来是 Windows Server。脚本主要面向 Windows 10/11 桌面版；Server runner 可用于 CI 预检，但不能完全等价于 Win10 专业版/企业版。"
    }

    if ($OsInfo.Caption -match "Enterprise|LTSC|LTSB") {
        Write-Warning "检测到企业版/LTSC/LTSB 字样。公司镜像常见限制包括代理、TLS 拦截、UAC、组策略禁止 MSI、npm registry 被拦截；如失败请优先查看日志里的下载源和 ExitCode。"
    }

    if ($OsInfo.Version.Major -eq 10 -and $OsInfo.Version.Build -gt 0 -and $OsInfo.Version.Build -lt 19045) {
        Write-Warning "当前 Windows 10 Build 为 $($OsInfo.Version.Build)，低于 22H2 常见 Build 19045。脚本会继续，但较旧 LTSC/企业镜像可能需要公司 IT 放行 TLS/证书/安装策略。"
    }

    if ($Arch -eq "arm64" -and $OsInfo.Version.Build -gt 0 -and $OsInfo.Version.Build -lt 22000) {
        Write-Warning "Windows ARM64 建议使用 Windows 11。Windows 10 ARM64 自动安装 Git 的兼容性较差。"
    }

    try {
        $probe = Join-Path $WorkDir "write-test.tmp"
        Set-Content -Path $probe -Value "ok" -Encoding ASCII
        Remove-Item -Force $probe -ErrorAction SilentlyContinue
        Write-Host "临时目录：可写，$WorkDir" -ForegroundColor Green
    } catch {
        throw "临时目录不可写：$WorkDir。请清理权限或手动设置 TEMP。详细错误：$($_.Exception.Message)"
    }

    try {
        $drive = New-Object System.IO.DriveInfo([IO.Path]::GetPathRoot($WorkDir))
        $freeGb = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
        Write-Host "临时目录所在磁盘剩余空间：$freeGb GB" -ForegroundColor White
        if ($freeGb -lt 3) {
            Write-Warning "剩余空间偏低。完整下载安装 Git/Node/Python 建议至少预留 3GB。"
        }
    } catch {
        Write-Warning "无法读取磁盘剩余空间：$($_.Exception.Message)"
    }

    $proxyNames = @("HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY")
    foreach ($name in $proxyNames) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            Write-Host "$name：$(Get-MaskedUrl $value)" -ForegroundColor DarkYellow
        }
    }

    Write-Host "兼容路径：$($Mode.DisplayName)" -ForegroundColor White
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Expand-ZipFile {
    param([string]$ZipFile, [string]$Destination)

    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $ZipFile -DestinationPath $Destination -Force
        return
    }

    $shell = New-Object -ComObject Shell.Application
    $zip = $shell.NameSpace($ZipFile)
    $dest = $shell.NameSpace($Destination)
    if (-not $zip -or -not $dest) { throw "无法解压：$ZipFile" }
    $dest.CopyHere($zip.Items(), 0x14)
    Start-Sleep -Seconds 2
}

function Install-Skills {
    param([string]$ZipFile)
    Write-Step "安装 Codex Skills"
    $dest = Join-Path $HOME ".agents\skills"
    $tmp = Join-Path $WorkDir "skills_unzip"
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tmp, $dest | Out-Null

    Expand-ZipFile -ZipFile $ZipFile -Destination $tmp
    $skillDirs = @(Get-ChildItem -Path $tmp -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") })

    if ($skillDirs.Count -gt 0) {
        foreach ($dir in $skillDirs) {
            $target = Join-Path $dest $dir.Name
            Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
            Copy-Item -Path $dir.FullName -Destination $target -Recurse -Force
            Write-Host "已安装 Skill：$($dir.Name)" -ForegroundColor Green
        }
    } else {
        Copy-Item -Path (Join-Path $tmp "*") -Destination $dest -Recurse -Force
        Write-Host "未检测到 SKILL.md，已按普通目录解压到：$dest" -ForegroundColor Yellow
    }
}

function Write-CodexConfig {
    param([pscustomobject]$Plan)

    Write-Step "写入 Codex 配置"
    $codexHome = Join-Path $HOME ".codex"
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
    $configPath = Join-Path $codexHome "config.toml"
    $authPath = Join-Path $codexHome "auth.json"
    $localAuthJson = Join-Path $ScriptDir "codex-auth.json"

    if (Test-Path $configPath) {
        $backup = Join-Path $codexHome ("config.toml.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        Copy-Item -Path $configPath -Destination $backup -Force
        Write-Host "已备份旧配置：$backup" -ForegroundColor DarkYellow
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('disable_response_storage = true')
    $lines.Add('network_access = "enabled"')
    $lines.Add('windows_wsl_setup_acknowledged = true')

    if (-not [string]::IsNullOrWhiteSpace($Plan.CodexModel)) {
        $safeModel = $Plan.CodexModel.Replace('"', '\"')
        $lines.Add(('model = "{0}"' -f $safeModel))
    }

    if (-not [string]::IsNullOrWhiteSpace($Plan.CodexBaseUrl)) {
        $safeUrl = $Plan.CodexBaseUrl.Replace('"', '\"')
        $lines.Add("")
        $lines.Add("[model_providers.OpenAI]")
        $lines.Add('name = "OpenAI"')
        $lines.Add(('base_url = "{0}"' -f $safeUrl))
        $lines.Add('wire_api = "responses"')
        $lines.Add('requires_openai_auth = true')
    }

    Write-Utf8NoBom -Path $configPath -Content (($lines -join "`r`n") + "`r`n")
    Write-Host "已写入：$configPath" -ForegroundColor Green

    if (Test-Path $localAuthJson) {
        Copy-Item -Path $localAuthJson -Destination $authPath -Force
        Write-Host "已从脚本同目录 codex-auth.json 写入认证文件：$authPath" -ForegroundColor Green
    } elseif ($NonInteractive) {
        if (Test-Path $authPath) {
            Write-Host "非交互模式：保留已有认证文件：$authPath" -ForegroundColor DarkYellow
        } else {
            Write-Host "非交互模式：未写入 auth.json。后续首次运行 codex 时需要手动登录或配置密钥。" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host ""
        Write-Host "请输入 OPENAI_API_KEY。直接回车则跳过，不覆盖已有 auth.json。" -ForegroundColor Yellow
        $apiKey = Read-Host "OPENAI_API_KEY"
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
            $auth = @{ OPENAI_API_KEY = $apiKey.Trim() } | ConvertTo-Json -Compress
            Write-Utf8NoBom -Path $authPath -Content $auth
            Write-Host "已写入：$authPath" -ForegroundColor Green
        } elseif (Test-Path $authPath) {
            Write-Host "保留已有认证文件：$authPath" -ForegroundColor DarkYellow
        } else {
            Write-Warning "未写入 auth.json。后续首次运行 codex 时需要手动登录或配置密钥。"
        }
    }
}

function Install-CodexCli {
    param([pscustomobject]$Plan)

    Write-Step "配置 npm 并安装 Codex CLI"
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    } catch {
        Write-Warning "设置 PowerShell ExecutionPolicy 失败，但会继续使用 npm.cmd 安装：$($_.Exception.Message)"
    }

    Refresh-Path
    $npm = Get-CommandPath "npm.cmd"
    if (-not $npm) {
        $candidate = Join-Path ${env:ProgramFiles} "nodejs\npm.cmd"
        if (Test-Path $candidate) { $npm = $candidate }
    }
    if (-not $npm) { throw "未找到 npm.cmd，请确认 Node.js 安装成功。" }

    $registries = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Plan.NpmRegistry)) {
        $registries.Add($Plan.NpmRegistry)
        if ($Plan.NpmRegistry -match "npmmirror") {
            $registries.Add("https://registry.npmjs.org")
        }
    } else {
        $registries.Add("")
    }

    $lastExit = 0
    foreach ($registry in $registries) {
        if (-not [string]::IsNullOrWhiteSpace($registry)) {
            Write-Host "npm registry：$registry" -ForegroundColor White
            & $npm config set registry $registry
        }

        & $npm install -g "@openai/codex@latest"
        $lastExit = $LASTEXITCODE
        if ($lastExit -eq 0) { return }

        Write-Warning "npm install -g @openai/codex@latest 执行失败，ExitCode=$lastExit。"
    }

    throw "npm install -g @openai/codex@latest 执行失败。请检查 npm registry、代理、证书或公司网络策略。ExitCode=$lastExit"
}

function Install-CodexApp {
    param([string]$Installer)
    Write-Step "安装 Codex Windows App"
    Write-Host "先尝试静默安装；如果安装器不支持静默参数，会自动改为普通安装窗口。" -ForegroundColor DarkYellow
    $silentOk = $false
    try {
        $p = Start-Process -FilePath $Installer -ArgumentList "/S" -Wait -PassThru
        if ($p.ExitCode -in @(0, 3010, 1641)) { $silentOk = $true }
    } catch {
        $silentOk = $false
    }
    if (-not $silentOk) {
        Write-Warning "Codex App 静默安装未确认成功，改为打开安装窗口。"
        Start-Process -FilePath $Installer -Wait
    }
}

function Show-Versions {
    Write-Step "版本检查"
    Refresh-Path
    $commands = @(
        @{Name='git'; Args='--version'},
        @{Name='node'; Args='-v'},
        @{Name='npm.cmd'; Args='-v'},
        @{Name='python'; Args='--version'},
        @{Name='codex'; Args='--version'}
    )

    foreach ($item in $commands) {
        $cmd = Get-CommandPath $item.Name
        if ($cmd) {
            try {
                $out = & $cmd $item.Args 2>&1
                Write-Host ($item.Name + " => " + ($out -join " ")) -ForegroundColor Green
            } catch {
                Write-Host ($item.Name + " => 已安装，但版本检查失败：" + $_.Exception.Message) -ForegroundColor Yellow
            }
        } else {
            Write-Host ($item.Name + " => 未找到，请重新打开 PowerShell 后再检查") -ForegroundColor Yellow
        }
    }
}

# ========== 主流程 ==========
if (-not $CheckOnly) {
    Invoke-SelfElevate
}
Enable-Tls12
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    Write-Host "Codex Windows 一键安装开始。日志文件：$LogFile" -ForegroundColor Cyan

    $osInfo = Get-WindowsInfo
    $arch = Get-NormalizedArch
    $mode = Get-InstallMode -OsInfo $osInfo -Arch $arch
    $plan = New-DownloadPlan -Mode $mode -Arch $arch

    Write-Step "系统检查"
    Write-Host "系统：$($osInfo.Caption) $($osInfo.Version)" -ForegroundColor White
    Write-Host "架构：$arch" -ForegroundColor White
    Write-Host "安装路径：$($mode.DisplayName)" -ForegroundColor White
    Invoke-EnvironmentPreflight -OsInfo $osInfo -Arch $arch -Mode $mode
    Write-PlanSummary -Plan $plan

    if ($mode.IsLegacy) {
        Write-Warning "Windows 8/8.1 已经过官方生命周期。脚本会尽量安装仍可获取的旧版官方依赖，但 Codex 最新版本可能不再保证在旧系统完整可用。"
    }

    if ($VerifyDownloads) {
        Test-DownloadPlan -Plan $plan -IncludeGit:(-not $SkipGit) -IncludePython:(-not $SkipPython)
    }

    if ($CheckOnly) {
        Write-Host ""
        Write-Host "CheckOnly 预检完成：未执行安装、未写入 Codex 配置。" -ForegroundColor Green
        exit 0
    }

    if ($arch -eq "arm64" -and $osInfo.Version.Build -lt 22000 -and -not $SkipGit -and -not (Get-CommandPath "git")) {
        throw "Git for Windows ARM64 官方要求 Windows 11。当前系统未检测到 git，无法自动安装。请升级到 Windows 11 ARM64 或先手动安装可用 Git。"
    }

    if (-not $SkipGit) {
        if (Get-CommandPath "git") {
            Write-Info "已检测到 Git，跳过 Git 安装。"
        } else {
            $gitName = Get-UrlFileName -Url $plan.GitUrl -Fallback $plan.GitFile
            $gitFile = Join-Path $WorkDir $gitName
            Download-File -Name "Git for Windows" -Url @($plan.GitUrls) -OutFile $gitFile
            Start-Installer -Name "Git for Windows" -FilePath $gitFile -Arguments "/VERYSILENT /NORESTART /NOCANCEL /SP-"
        }
    }

    if (Test-NodeReady) {
        Write-Info "已检测到 Node.js 16+，跳过 Node.js 安装。"
    } else {
        $nodeName = Get-UrlFileName -Url $plan.NodeUrl -Fallback $plan.NodeFile
        $nodeFile = Join-Path $WorkDir $nodeName
        Download-File -Name "Node.js" -Url @($plan.NodeUrls) -OutFile $nodeFile
        Start-Installer -Name "Node.js" -FilePath "msiexec.exe" -Arguments "/i `"$nodeFile`" /qn /norestart"
    }

    if (-not $SkipPython) {
        if (Test-PythonReady) {
            Write-Info "已检测到 Python 3，跳过 Python 安装。"
        } else {
            $pythonName = Get-UrlFileName -Url $plan.PythonUrl -Fallback $plan.PythonFile
            $pythonFile = Join-Path $WorkDir $pythonName
            Download-File -Name "Python" -Url @($plan.PythonUrls) -OutFile $pythonFile
            Start-Installer -Name "Python" -FilePath $pythonFile -Arguments "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1 AssociateFiles=1 Include_test=0 Shortcuts=0"
        }
    }

    Refresh-Path
    Install-CodexCli -Plan $plan

    if (-not $SkipSkills) {
        $localSkillsZip = Join-Path $ScriptDir "codex-skills.zip"
        if (Test-Path $localSkillsZip) {
            Install-Skills -ZipFile $localSkillsZip
        } elseif (-not [string]::IsNullOrWhiteSpace($plan.SkillsUrl)) {
            $skillsName = Get-UrlFileName -Url $plan.SkillsUrl -Fallback "codex-skills.zip"
            $skillsFile = Join-Path $WorkDir $skillsName
            Download-File -Name "Codex Skills" -Url @($plan.SkillsUrl) -OutFile $skillsFile
            Install-Skills -ZipFile $skillsFile
        } else {
            Write-Info "未配置 Skills 包，跳过 Skills 安装。可使用 CODEX_SKILLS_URL 或同目录 codex-skills.zip 启用。"
        }
    }

    Write-CodexConfig -Plan $plan

    if (-not $SkipCodexApp) {
        $localAppInstaller = Join-Path $ScriptDir "Codex Installer.exe"
        if (Test-Path $localAppInstaller) {
            Install-CodexApp -Installer $localAppInstaller
        } elseif (-not [string]::IsNullOrWhiteSpace($plan.CodexAppUrl)) {
            $appName = Get-UrlFileName -Url $plan.CodexAppUrl -Fallback "Codex Installer.exe"
            $appFile = Join-Path $WorkDir $appName
            Download-File -Name "Codex Windows App" -Url @($plan.CodexAppUrl) -OutFile $appFile
            Install-CodexApp -Installer $appFile
        } else {
            Write-Info "未配置 Codex Windows App 安装器，跳过 App 安装。Codex CLI 已安装即可使用。"
        }
    }

    Show-Versions

    Write-Host ""
    Write-Host "安装完成。建议重新打开一个 PowerShell 窗口，然后执行：" -ForegroundColor Green
    Write-Host "  codex --version" -ForegroundColor White
    Write-Host "  codex" -ForegroundColor White
    Write-Host ""
    Write-Host "日志位置：$LogFile" -ForegroundColor DarkGray
} catch {
    Write-Host ""
    Write-Host "安装失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "日志位置：$LogFile" -ForegroundColor Yellow
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host ""
    if (-not $NoPause -and -not $CheckOnly) {
        Read-Host "按 Enter 键退出"
    }
}
