# Codex Windows 一键安装/更新脚本 v2
# 官方入口：https://chatgpt.com/codex/install.ps1
# 实际固定入口：https://releases.openai.com/codex/install.ps1

[CmdletBinding()]
param(
    [switch]$Update,
    [ValidateSet("standalone", "npm")]
    [string]$CliMethod = "standalone",
    [ValidateSet("auto", "official", "github")]
    [string]$NetworkMode = "auto",
    [string]$Release = "latest",
    [switch]$InstallDesktopApp,
    [switch]$RequireDesktopApp,
    [switch]$InstallDevTools,
    [switch]$CheckOnly,
    [switch]$VerifyDownloads,
    [switch]$NonInteractive,
    [switch]$NoPause,
    [string]$NpmRegistry = "",
    [Alias("ExpectedBootstrapSha256")]
    [string]$BootstrapSha256 = $env:CODEX_BOOTSTRAP_SHA256,
    [string]$TestWindowsVersion = "",
    [string]$TestWindowsCaption = "",
    [string]$TestArch = "",
    [Nullable[int]]$TestProductType = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$OfficialBootstrapUrl = "https://releases.openai.com/codex/install.ps1"
$OfficialLatestChannelUrl = "https://releases.openai.com/codex/channels/latest"
$GithubBootstrapLatestUrl = "https://github.com/openai/codex/releases/latest/download/install.ps1"
$DesktopStoreId = "9PLM9XGG6VKS"
$DesktopMsixX64Url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix"
$DesktopMsixArm64Url = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-arm64.msix"
$DesktopMinimumOsBuild = 19041
$ActionName = $(if ($Update) { "更新" } else { "安装" })

$script:LogFile = $null
$script:WorkDir = $null
$script:BootstrapPath = $null
$script:DesktopMsixPath = $null
$script:NpmExecutable = $null
$script:ValidatedCodexInstallDir = $null
$script:BootstrapSource = $null

try {
    [Console]::OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
} catch {}

function Protect-LogText {
    param([AllowEmptyString()][string]$Text)

    if ($null -eq $Text) { return "" }

    # 日志和屏幕输出都去掉 URL query/fragment，避免代理签名或临时令牌泄露。
    $urlPattern = '(?i)(https?://[^\s?#"''<>]+)(?:\?[^\s#"''<>]*)?(?:#[^\s"''<>]*)?'
    return [regex]::Replace([string]$Text, $urlPattern, '$1')
}

function Write-LogRecord {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($script:LogFile)) { return }
    try {
        Add-Content -LiteralPath $script:LogFile -Value (Protect-LogText $Message) -Encoding UTF8
    } catch {}
}

function Write-Line {
    param(
        [string]$Message = "",
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    $safeMessage = Protect-LogText $Message
    Write-Host $safeMessage -ForegroundColor $Color
    Write-LogRecord $safeMessage
}

function Write-Step {
    param([string]$Message)

    Write-Line ""
    Write-Line "========== $Message ==========" Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Line $Message DarkCyan
}

function Write-Success {
    param([string]$Message)
    Write-Line $Message Green
}

function Write-Warn {
    param([string]$Message)

    $safeMessage = Protect-LogText $Message
    Write-Warning $safeMessage
    Write-LogRecord "警告：$safeMessage"
}

function Get-SafeUrl {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    try {
        $uri = New-Object -TypeName System.Uri -ArgumentList @($Value)
        return $uri.GetLeftPart([System.UriPartial]::Path)
    } catch {
        return "<无效 URL>"
    }
}

function Assert-ReleaseValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "-Release 不能为空。请使用 latest 或明确版本号。"
    }

    $candidate = $Value.Trim()
    if ($candidate -cnotmatch '^(?:latest|(?:rust-v|v)?[0-9]+\.[0-9]+\.[0-9]+(?:-alpha(?:\.[0-9]+){0,2}|-beta(?:\.[0-9]+)?)?)$') {
        throw "无效的 -Release：$candidate。请使用 latest 或 x.y.z[-alpha...|-beta...]。"
    }
}

function Assert-BootstrapSha256 {
    param([string]$Value)

    if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim() -cnotmatch '^[0-9a-fA-F]{64}$') {
        throw "-BootstrapSha256 必须是 64 位十六进制 SHA-256。"
    }
}

function Assert-NpmRegistry {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return }

    try {
        $uri = New-Object -TypeName System.Uri -ArgumentList @($Value.Trim())
    } catch {
        throw "-NpmRegistry 必须是有效的 HTTPS 绝对 URL。"
    }

    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne "https") {
        throw "-NpmRegistry 仅允许 HTTPS 绝对 URL。"
    }
    if ([string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "-NpmRegistry 必须包含有效主机名。"
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        throw "-NpmRegistry 不允许在 URL 中嵌入用户名或密码。"
    }
    if (-not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw "-NpmRegistry 不允许携带 query 或 fragment，以免令牌或签名参数进入安装流程或子进程环境。"
    }
}

function Resolve-CodexInstallDirectory {
    param([Parameter(Mandatory=$true)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "CODEX_INSTALL_DIR 不能为空白值。"
    }

    $candidate = $Value.Trim()
    $isDriveAbsolute = $candidate -match '^[A-Za-z]:[\\/]'
    $isUncAbsolute = $candidate -match '^[\\/]{2}[^\\/:*?"<>|]+[\\/][^\\/:*?"<>|]+(?:[\\/]|$)'
    if (-not $isDriveAbsolute -and -not $isUncAbsolute) {
        throw "CODEX_INSTALL_DIR 必须是 Windows 绝对路径（例如 C:\Tools\Codex 或 \\server\share\Codex）。"
    }
    if ($candidate -match '^[\\/]{2}[?.][\\/]') {
        throw "CODEX_INSTALL_DIR 不允许使用设备路径或扩展路径前缀。"
    }
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        throw "CODEX_INSTALL_DIR 必须是 rooted/absolute 路径，不能使用驱动器相对路径。"
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($candidate)
        $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    } catch {
        throw "CODEX_INSTALL_DIR 无法规范化为有效 Windows 路径。"
    }
    if ([string]::IsNullOrWhiteSpace($rootPath)) {
        throw "CODEX_INSTALL_DIR 无法确定文件系统根。"
    }

    $directorySeparators = [char[]]@("\", "/")
    $normalizedPath = $fullPath.TrimEnd($directorySeparators)
    $normalizedRoot = $rootPath.TrimEnd($directorySeparators)
    if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "CODEX_INSTALL_DIR 不得解析为驱动器根或 UNC 共享根。"
    }
    return $normalizedPath
}

function Assert-TestOverridesAreCheckOnly {
    $hasTestOverride = (
        -not [string]::IsNullOrEmpty($TestWindowsVersion) -or
        -not [string]::IsNullOrEmpty($TestWindowsCaption) -or
        -not [string]::IsNullOrEmpty($TestArch) -or
        $null -ne $TestProductType
    )

    if ($hasTestOverride -and -not $CheckOnly) {
        throw "-TestWindowsVersion、-TestWindowsCaption、-TestArch 和 -TestProductType 仅允许与 -CheckOnly 一起使用。"
    }
}

function Get-WindowsRegistryFallback {
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    try {
        $currentVersion = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
    } catch {
        return $null
    }

    $installationProperty = $currentVersion.PSObject.Properties["InstallationType"]
    $productNameProperty = $currentVersion.PSObject.Properties["ProductName"]
    $buildProperty = $currentVersion.PSObject.Properties["CurrentBuildNumber"]
    $majorProperty = $currentVersion.PSObject.Properties["CurrentMajorVersionNumber"]
    $minorProperty = $currentVersion.PSObject.Properties["CurrentMinorVersionNumber"]

    $installationType = $(if ($null -eq $installationProperty) { "" } else { [string]$installationProperty.Value })
    $productName = $(if ($null -eq $productNameProperty) { "" } else { [string]$productNameProperty.Value })
    $productType = $null

    if ($productName -match '(?i)\bWindows\s+Server\b') {
        $productType = 3
    } elseif ($installationType.Equals("Client", [System.StringComparison]::OrdinalIgnoreCase)) {
        $productType = 1
    } elseif ($installationType -match '(?i)^Server(?:\s|$)|^Nano\s+Server$') {
        $productType = 3
    }

    $versionText = ""
    $buildNumber = $(if ($null -eq $buildProperty) { "" } else { [string]$buildProperty.Value })
    [int]$parsedBuild = 0
    if ([int]::TryParse($buildNumber, [ref]$parsedBuild) -and $parsedBuild -gt 0) {
        [int]$majorVersion = 10
        [int]$minorVersion = 0
        [int]$parsedComponent = 0
        if ($null -ne $majorProperty -and [int]::TryParse([string]$majorProperty.Value, [ref]$parsedComponent)) {
            $majorVersion = $parsedComponent
        }
        $parsedComponent = 0
        if ($null -ne $minorProperty -and [int]::TryParse([string]$minorProperty.Value, [ref]$parsedComponent)) {
            $minorVersion = $parsedComponent
        }
        $versionText = "$majorVersion.$minorVersion.$parsedBuild"
    }

    return [pscustomobject]@{
        Caption = $productName
        VersionText = $versionText
        ProductType = $productType
        InstallationType = $installationType
    }
}

function Get-WindowsInfo {
    if (-not [string]::IsNullOrWhiteSpace($TestWindowsVersion)) {
        try {
            $version = New-Object -TypeName System.Version -ArgumentList @($TestWindowsVersion.Trim())
        } catch {
            throw "-TestWindowsVersion 不是有效版本号：$TestWindowsVersion"
        }

        return [pscustomobject]@{
            Caption = $(if ([string]::IsNullOrWhiteSpace($TestWindowsCaption)) { "Microsoft Windows Test" } else { $TestWindowsCaption.Trim() })
            Version = $version
            Architecture = $(if ([string]::IsNullOrWhiteSpace($TestArch)) { "x64" } else { $TestArch.Trim() })
            ProductType = $(if ($null -eq $TestProductType) { 1 } else { [int]$TestProductType })
        }
    }

    if ([Environment]::GetEnvironmentVariable("OS") -ne "Windows_NT") {
        throw "install-codex.ps1 仅支持 Windows。CI 可通过 -TestWindowsVersion/-TestWindowsCaption/-TestArch 执行预检。"
    }

    $caption = ""
    $versionText = ""
    $architecture = ""
    $productType = $null

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $caption = [string]$os.Caption
        $versionText = [string]$os.Version
        $architecture = [string]$os.OSArchitecture
        $productType = $os.ProductType
    } catch {
        try {
            $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
            $caption = [string]$os.Caption
            $versionText = [string]$os.Version
            $architecture = [string]$os.OSArchitecture
            $productType = $os.ProductType
        } catch {
            $registryInfo = Get-WindowsRegistryFallback
            if ($null -ne $registryInfo) {
                $caption = [string]$registryInfo.Caption
                $versionText = [string]$registryInfo.VersionText
                $productType = $registryInfo.ProductType
            }
            if ([string]::IsNullOrWhiteSpace($versionText)) {
                $versionText = [Environment]::OSVersion.Version.ToString()
            }
            $architecture = [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
        }
    }

    if ([string]::IsNullOrWhiteSpace($caption)) { $caption = "Microsoft Windows" }
    if ([string]::IsNullOrWhiteSpace($versionText)) {
        throw "无法可靠识别 Windows 版本，已安全停止。"
    }

    return [pscustomobject]@{
        Caption = $caption
        Version = (New-Object -TypeName System.Version -ArgumentList @($versionText))
        Architecture = $architecture
        ProductType = $productType
    }
}

function Get-NormalizedArchitecture {
    param([string]$ReportedArchitecture)

    $raw = $TestArch
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITEW6432")
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = [Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $raw = $ReportedArchitecture
    }

    switch -Regex ($raw.Trim()) {
        '^(?i:x64|amd64|x86_64|64-bit)$' { return "x64" }
        '^(?i:arm64|aarch64|arm64-based pc)$' { return "arm64" }
        default { return "unsupported" }
    }
}

function Assert-SupportedEnvironment {
    param(
        [pscustomobject]$OsInfo,
        [string]$Architecture
    )

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "需要 Windows PowerShell 5.1 或更高版本。"
    }
    if ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1) {
        throw "需要 Windows PowerShell 5.1 或更高版本。"
    }
    if ($null -eq $OsInfo.ProductType) {
        throw "无法通过 CIM、WMI 或 Windows 注册表可靠确认客户端 ProductType，已安全停止。"
    }
    try {
        $productTypeValue = [int]$OsInfo.ProductType
    } catch {
        throw "无法可靠解析 Windows ProductType，已安全停止。"
    }
    if ($productTypeValue -in @(2, 3)) {
        throw "当前仅支持 Windows 10/11 客户端；Windows Server 尚未支持。"
    }
    if ($productTypeValue -ne 1) {
        throw "无法确认受支持的客户端 ProductType（实际：$productTypeValue），已安全停止。"
    }
    if ($Architecture -notin @("x64", "arm64")) {
        throw "仅支持 64 位 Windows x64/ARM64；32 位系统已安全停止。"
    }

    $version = $OsInfo.Version
    if ($version.Major -lt 10 -or ($version.Major -eq 10 -and $version.Build -lt 17763)) {
        throw "不支持 $($OsInfo.Caption) $version。最低为 Windows 10 build 17763；Windows 8/8.1 不再支持。"
    }
    if ($version.Major -gt 10) {
        throw "尚未识别的 Windows 主版本：$version。为避免不安全安装，已安全停止。"
    }

    if ($version.Build -ge 22000) {
        Write-Success "系统支持：Windows 11 或更高版本（推荐）。"
    } else {
        Write-Warn "Windows 10 build $($version.Build) 仅提供 best-effort 支持；建议升级到 Windows 11。"
    }
}

function Show-Plan {
    param(
        [pscustomobject]$OsInfo,
        [string]$Architecture,
        [bool]$DesktopRequested
    )

    Write-Step "系统与执行计划"
    Write-Line "系统：$($OsInfo.Caption) $($OsInfo.Version)" White
    Write-Line "架构：$Architecture" White
    Write-Line "操作：Codex CLI $ActionName" White
    Write-Line "CLI 安装方式：$CliMethod" White
    Write-Line "网络模式：$NetworkMode" White
    Write-Line "CLI 版本：$($Release.Trim())" White
    if ($CliMethod -eq "standalone") {
        if ($NetworkMode -eq "auto") {
            Write-Line "官方 bootstrap：优先 OpenAI CDN；短时不可用时自动切换 OpenAI GitHub Release" White
        } elseif ($NetworkMode -eq "github") {
            Write-Line "官方 bootstrap：OpenAI GitHub Release" White
        } else {
            Write-Line "官方 bootstrap：$(Get-SafeUrl $OfficialBootstrapUrl)" White
        }
        Write-Line "官方发布通道：$(Get-SafeUrl $OfficialLatestChannelUrl)" DarkGray
    } elseif (-not [string]::IsNullOrWhiteSpace($NpmRegistry)) {
        Write-Line "npm registry（仅本次 npm 子进程环境，不写 .npmrc）：$(Get-SafeUrl $NpmRegistry)" White
    } else {
        Write-Line "npm registry：npm 当前默认值（不会永久修改）" White
    }
    Write-Line "开发工具补缺：$(if ($InstallDevTools) { '是' } else { '否' })" White
    Write-Line "ChatGPT desktop app：$(if ($DesktopRequested) { '安装/更新' } else { '跳过' })" White
    if ($RequireDesktopApp) {
        Write-Line "ChatGPT desktop app：失败将使整体失败" DarkYellow
    }
    if ($CheckOnly) {
        Write-Line "CheckOnly：不会安装、不会修改用户配置或用户目录。" Green
        if ($VerifyDownloads) {
            Write-Line "VerifyDownloads：将仅在随机私有临时目录下载并验证官方 bootstrap，然后清理下载文件。" DarkYellow
        } else {
            Write-Line "下载：跳过。" Green
        }
    }
}

function New-PrivateWorkDirectory {
    $tempRoot = [System.IO.Path]::GetTempPath()
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        throw "无法确定系统临时目录。"
    }

    $path = Join-Path $tempRoot ("codex-installer-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null

    if ([Environment]::GetEnvironmentVariable("OS") -eq "Windows_NT") {
        try {
            $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            if ($null -eq $currentSid) { throw "无法识别当前用户 SID。" }

            $acl = Get-Acl -LiteralPath $path
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($existingRule in @($acl.Access)) {
                $acl.RemoveAccessRuleSpecific($existingRule)
            }
            $acl.SetOwner($currentSid)

            $systemSid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList @("S-1-5-18")
            $administratorsSid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList @("S-1-5-32-544")
            foreach ($sid in @($currentSid, $systemSid, $administratorsSid)) {
                $ruleArguments = @(
                    $sid,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $ruleArguments
                $acl.AddAccessRule($accessRule)
            }
            Set-Acl -LiteralPath $path -AclObject $acl
        } catch {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            throw "无法为临时目录设置私有 ACL，已安全停止：$($_.Exception.Message)"
        }
    }

    return $path
}

function Initialize-PrivateLog {
    param([string]$Directory)

    $script:LogFile = Join-Path $Directory "install.log"
    Set-Content -LiteralPath $script:LogFile -Value "" -Encoding UTF8
}

function Enable-Tls12 {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
}

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [long]$MinimumBytes = 1,
        [Parameter(Mandatory=$true)][long]$MaximumBytes,
        [int]$TimeoutMilliseconds = 300000
    )

    Write-Step "下载 $Name"
    Write-Line "来源：$(Get-SafeUrl $Url)" DarkGray

    if ($MinimumBytes -lt 1 -or $MaximumBytes -lt $MinimumBytes) {
        throw "$Name 下载大小边界无效。"
    }

    try {
        $sourceUri = New-Object -TypeName System.Uri -ArgumentList @($Url)
    } catch {
        throw "$Name 下载地址无效。"
    }
    if (-not $sourceUri.IsAbsoluteUri -or $sourceUri.Scheme -cne "https") {
        throw "$Name 仅允许从 HTTPS 绝对 URL 下载。"
    }

    $request = $null
    $response = $null
    $inputStream = $null
    $outputStream = $null
    $downloadError = $null
    [long]$totalBytes = 0
    $downloadTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # HttpWebRequest 在 Windows PowerShell 5.1 可用，并沿用 Windows 的系统代理、
        # 证书存储与 TLS 校验。逐块写入可在响应未提供 Content-Length 时仍强制上限。
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($sourceUri)
        $request.Method = "GET"
        $request.AllowAutoRedirect = $true
        $request.MaximumAutomaticRedirections = 10
        $request.Timeout = $TimeoutMilliseconds
        $request.ReadWriteTimeout = $TimeoutMilliseconds
        $request.UserAgent = "codex-one-click-installer/2.0"
        $request.AutomaticDecompression = (
            [System.Net.DecompressionMethods]::GZip -bor
            [System.Net.DecompressionMethods]::Deflate
        )

        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $finalUri = $response.ResponseUri
        if ($null -eq $finalUri -or -not $finalUri.IsAbsoluteUri -or $finalUri.Scheme -cne "https") {
            throw "$Name 最终响应地址不是 HTTPS，已拒绝保存。"
        }

        $statusCode = [int]$response.StatusCode
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            throw "$Name 下载返回 HTTP $statusCode。"
        }
        if ($response.ContentLength -gt $MaximumBytes) {
            throw "$Name 声明大小超过上限 $MaximumBytes 字节。"
        }

        $inputStream = $response.GetResponseStream()
        if ($null -eq $inputStream) {
            throw "$Name 下载响应没有可读取的数据流。"
        }
        $outputStream = [System.IO.File]::Open(
            $OutFile,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $buffer = New-Object byte[] 65536
        while ($true) {
            [long]$remainingMilliseconds = (
                [long]$TimeoutMilliseconds - $downloadTimer.ElapsedMilliseconds
            )
            if ($remainingMilliseconds -le 0) {
                $request.Abort()
                throw "$Name 下载超过总耗时上限 $TimeoutMilliseconds 毫秒。"
            }

            # 用整个下载的剩余预算等待异步读取，避免代理持续滴流时每次 Read
            # 都在单次 ReadWriteTimeout 内完成，却让快速探测无限延长。
            $asyncRead = $inputStream.BeginRead($buffer, 0, $buffer.Length, $null, $null)
            try {
                if (-not $asyncRead.AsyncWaitHandle.WaitOne([int]$remainingMilliseconds)) {
                    $request.Abort()
                    throw "$Name 下载超过总耗时上限 $TimeoutMilliseconds 毫秒。"
                }
                $bytesRead = $inputStream.EndRead($asyncRead)
            } finally {
                $asyncRead.AsyncWaitHandle.Close()
            }
            if ($downloadTimer.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
                $request.Abort()
                throw "$Name 下载超过总耗时上限 $TimeoutMilliseconds 毫秒。"
            }
            if ($bytesRead -le 0) { break }
            if ($totalBytes + [long]$bytesRead -gt $MaximumBytes) {
                throw "$Name 实际大小超过上限 $MaximumBytes 字节。"
            }
            $outputStream.Write($buffer, 0, $bytesRead)
            $totalBytes += [long]$bytesRead
        }
        $outputStream.Flush()
    } catch {
        $downloadError = $_.Exception
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $downloadTimer.Stop()
    }

    if ($null -ne $downloadError) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "$Name 下载失败：$(Protect-LogText $downloadError.Message)"
    }

    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) {
        throw "$Name 下载后文件不存在。"
    }
    $length = (Get-Item -LiteralPath $OutFile).Length
    if ($length -lt $MinimumBytes -or $length -gt $MaximumBytes) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "$Name 下载大小超出允许范围（实际 $length 字节；允许 $MinimumBytes..$MaximumBytes 字节）。"
    }
    Write-Success "$Name 下载完成（$length 字节）。"
}

function Get-GithubBootstrapUrl {
    # bootstrap 始终取最新官方 installer；CLI 目标版本仍由 -Release 独立控制。
    return $GithubBootstrapLatestUrl
}

function Download-AndValidateOfficialBootstrap {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [int]$TimeoutMilliseconds = 300000
    )

    try {
        Download-File `
            -Name "OpenAI 官方 Codex bootstrap" `
            -Url $Url `
            -OutFile $OutFile `
            -MinimumBytes 4096 `
            -MaximumBytes 2097152 `
            -TimeoutMilliseconds $TimeoutMilliseconds
        $null = Test-OfficialBootstrap -Path $OutFile -ExpectedSha256 $BootstrapSha256
    } catch {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Download-OfficialBootstrap {
    param([Parameter(Mandatory=$true)][string]$OutFile)

    if ($NetworkMode -eq "official") {
        Download-AndValidateOfficialBootstrap -Url $OfficialBootstrapUrl -OutFile $OutFile
        $script:BootstrapSource = "releases"
        return
    }
    if ($NetworkMode -eq "github") {
        Download-AndValidateOfficialBootstrap -Url (Get-GithubBootstrapUrl) -OutFile $OutFile -TimeoutMilliseconds 180000
        $script:BootstrapSource = "github"
        return
    }

    try {
        Download-AndValidateOfficialBootstrap -Url $OfficialBootstrapUrl -OutFile $OutFile -TimeoutMilliseconds 15000
        $script:BootstrapSource = "releases"
        return
    } catch {
        Write-Warn "OpenAI CDN 快速探测未通过，自动切换 OpenAI GitHub Release，避免等待长超时：$(Protect-LogText $_.Exception.Message)"
    }

    try {
        Download-AndValidateOfficialBootstrap -Url (Get-GithubBootstrapUrl) -OutFile $OutFile -TimeoutMilliseconds 120000
        $script:BootstrapSource = "github"
        return
    } catch {
        Write-Warn "OpenAI GitHub Release 也未快速完成，最后重试 OpenAI CDN：$(Protect-LogText $_.Exception.Message)"
    }

    Download-AndValidateOfficialBootstrap -Url $OfficialBootstrapUrl -OutFile $OutFile
    $script:BootstrapSource = "releases"
}

function Test-OfficialBootstrap {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$ExpectedSha256
    )

    Write-Step "验证官方 bootstrap"
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 4096 -or $item.Length -gt 2097152) {
        throw "官方 bootstrap 大小异常：$($item.Length) 字节。"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -match '(?i)<!doctype\s+html|<html(?:\s|>)') {
        throw "官方 bootstrap 下载结果疑似 HTML 错误页。"
    }

    $requiredMarkers = @(
        "[CmdletBinding()]",
        '$Release',
        "Get-FileHash",
        "SHA256",
        "Invoke-WithInstallLock",
        "releases.openai.com/codex"
    )
    foreach ($marker in $requiredMarkers) {
        if (-not $content.Contains($marker)) {
            throw "官方 bootstrap 缺少预期安全标记：$marker"
        }
    }

    $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        $expected = $ExpectedSha256.Trim().ToLowerInvariant()
        if ($actualSha256 -cne $expected) {
            throw "官方 bootstrap SHA-256 不匹配。Expected=$expected Actual=$actualSha256"
        }
        Write-Success "官方 bootstrap SHA-256 与指定值一致：$actualSha256"
    } else {
        Write-Success "官方 bootstrap 内容检查通过；SHA-256：$actualSha256"
        Write-Info "未固定 bootstrap 摘要；传入 -BootstrapSha256 可进行精确摘要校验。"
    }

    return $actualSha256
}

function Get-CommandPath {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Path
        }
    }
    return $null
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $currentPath = $env:Path
    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($pathValue in @($machinePath, $userPath, $currentPath)) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
        foreach ($segment in $pathValue.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $trimmed = $segment.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and $segments -notcontains $trimmed) {
                $segments.Add($trimmed)
            }
        }
    }
    if ($segments.Count -gt 0) {
        $env:Path = $segments -join ";"
    }
}

function Test-CommandSucceeds {
    param(
        [string[]]$Candidates,
        [string[]]$Arguments
    )

    $path = Get-CommandPath -Candidates $Candidates
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $global:LASTEXITCODE = 0
        $null = & $path @Arguments 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory=$true)][string]$DisplayName
    )

    Write-Info "执行：$DisplayName"
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $global:LASTEXITCODE = 0
        $output = @(& $Path @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    foreach ($line in @($output)) {
        $text = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-Line $text DarkGray
        }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($output | ForEach-Object { Protect-LogText ([string]$_) }) -join "`n")
    }
}

function Get-ChildPowerShell {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $PSHOME "powershell.exe"))
    $candidates.Add((Join-Path $PSHOME "pwsh.exe"))
    try {
        $processPath = (Get-Process -Id $PID -ErrorAction Stop).Path
        if (-not [string]::IsNullOrWhiteSpace($processPath)) { $candidates.Add($processPath) }
    } catch {}

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    $fallback = Get-CommandPath -Candidates @("powershell.exe", "pwsh.exe")
    if ([string]::IsNullOrWhiteSpace($fallback)) {
        throw "无法定位用于执行官方 bootstrap 的 PowerShell。"
    }
    return $fallback
}

function Invoke-StandaloneInstall {
    param(
        [string]$BootstrapPath,
        [string]$RequestedRelease
    )

    Write-Step "通过官方 standalone bootstrap $ActionName Codex CLI"
    $powerShell = Get-ChildPowerShell
    $arguments = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $BootstrapPath,
        "-Release",
        $RequestedRelease.Trim()
    )

    $oldNonInteractive = [Environment]::GetEnvironmentVariable("CODEX_NON_INTERACTIVE", "Process")
    $oldInstallDirectory = [Environment]::GetEnvironmentVariable("CODEX_INSTALL_DIR", "Process")
    $oldReleasePreference = [Environment]::GetEnvironmentVariable("CODEX_INSTALLER_USE_RELEASES_OPENAI_COM", "Process")
    try {
        if ($NonInteractive) {
            [Environment]::SetEnvironmentVariable("CODEX_NON_INTERACTIVE", "1", "Process")
        }
        if (-not [string]::IsNullOrWhiteSpace($script:ValidatedCodexInstallDir)) {
            [Environment]::SetEnvironmentVariable(
                "CODEX_INSTALL_DIR",
                $script:ValidatedCodexInstallDir,
                "Process"
            )
        }
        if ($script:BootstrapSource -eq "github") {
            [Environment]::SetEnvironmentVariable(
                "CODEX_INSTALLER_USE_RELEASES_OPENAI_COM",
                "false",
                "Process"
            )
            Write-Info "已根据网络探测直接使用 OpenAI GitHub Release 资产，跳过不可用 CDN 的等待。"
        } elseif ($script:BootstrapSource -eq "releases") {
            [Environment]::SetEnvironmentVariable(
                "CODEX_INSTALLER_USE_RELEASES_OPENAI_COM",
                "true",
                "Process"
            )
            Write-Info "已根据网络模式固定使用 OpenAI CDN，不继承外部 GitHub Release 偏好。"
        }
        $result = Invoke-NativeCommand -Path $powerShell -Arguments $arguments -DisplayName "官方 install.ps1 -Release $($RequestedRelease.Trim())"
    } finally {
        [Environment]::SetEnvironmentVariable("CODEX_NON_INTERACTIVE", $oldNonInteractive, "Process")
        [Environment]::SetEnvironmentVariable("CODEX_INSTALL_DIR", $oldInstallDirectory, "Process")
        [Environment]::SetEnvironmentVariable("CODEX_INSTALLER_USE_RELEASES_OPENAI_COM", $oldReleasePreference, "Process")
    }

    if ($result.ExitCode -ne 0) {
        throw "官方 standalone bootstrap 执行失败，ExitCode=$($result.ExitCode)。"
    }
}

function Get-NpmRelease {
    param([string]$RequestedRelease)

    $value = $RequestedRelease.Trim()
    if ($value.StartsWith("rust-v", [System.StringComparison]::Ordinal)) {
        return $value.Substring(6)
    }
    if ($value.StartsWith("v", [System.StringComparison]::Ordinal)) {
        return $value.Substring(1)
    }
    return $value
}

function Install-CliWithNpm {
    Write-Step "通过 npm 兼容路径 $ActionName Codex CLI"
    Refresh-ProcessPath
    $npm = Get-CommandPath -Candidates @("npm.cmd", "npm.exe", "npm")
    if ([string]::IsNullOrWhiteSpace($npm)) {
        throw "未找到 npm。可改用默认 -CliMethod standalone，或显式添加 -InstallDevTools 后重试。"
    }
    $script:NpmExecutable = $npm

    $packageSpec = "@openai/codex@$(Get-NpmRelease $Release)"
    $arguments = @("install", "--global", $packageSpec, "--no-audit", "--no-fund")
    $oldRegistry = [Environment]::GetEnvironmentVariable("npm_config_registry", "Process")
    try {
        if (-not [string]::IsNullOrWhiteSpace($NpmRegistry)) {
            [Environment]::SetEnvironmentVariable("npm_config_registry", $NpmRegistry.Trim(), "Process")
            Write-Info "npm registry 仅通过本次进程环境变量使用：$(Get-SafeUrl $NpmRegistry)"
        }
        $result = Invoke-NativeCommand -Path $npm -Arguments $arguments -DisplayName "npm install --global $packageSpec"
    } finally {
        [Environment]::SetEnvironmentVariable("npm_config_registry", $oldRegistry, "Process")
    }
    if ($result.ExitCode -ne 0) {
        throw "npm 兼容安装失败，ExitCode=$($result.ExitCode)。"
    }
}

function Test-DevToolPresent {
    param([string]$Name)

    switch ($Name) {
        "Git" {
            return (Test-CommandSucceeds -Candidates @("git.exe", "git") -Arguments @("--version"))
        }
        "Node.js" {
            $nodeOk = Test-CommandSucceeds -Candidates @("node.exe", "node") -Arguments @("--version")
            $npmOk = Test-CommandSucceeds -Candidates @("npm.cmd", "npm.exe", "npm") -Arguments @("--version")
            return ($nodeOk -and $npmOk)
        }
        "Python 3" {
            $pythonCandidates = @(
                [pscustomobject]@{ Names = @("python.exe", "python"); Arguments = @("--version") },
                [pscustomobject]@{ Names = @("py.exe", "py"); Arguments = @("-3", "--version") }
            )
            foreach ($candidate in $pythonCandidates) {
                $path = Get-CommandPath -Candidates $candidate.Names
                if ([string]::IsNullOrWhiteSpace($path)) { continue }

                $oldPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = "Continue"
                    $global:LASTEXITCODE = 0
                    [string[]]$pythonArguments = @($candidate.Arguments)
                    $output = @(& $path @pythonArguments 2>&1)
                    if ($LASTEXITCODE -eq 0 -and (($output -join "`n") -match '(?im)\bPython\s+3(?:\.[0-9]+)+\b')) {
                        return $true
                    }
                } catch {
                    # 继续探测 py -3；python 命令可能是商店别名或 Python 2。
                } finally {
                    $ErrorActionPreference = $oldPreference
                }
            }
            return $false
        }
        "GitHub CLI" {
            return (Test-CommandSucceeds -Candidates @("gh.exe", "gh") -Arguments @("--version"))
        }
        default {
            throw "未知开发工具：$Name"
        }
    }
}

function Test-WingetNoActionSuccess {
    param([string]$Output)

    $patterns = @(
        "already installed",
        "no available upgrade",
        "no applicable update",
        "no newer package versions",
        "已安装",
        "没有可用的升级",
        "没有适用的更新",
        "无需更新"
    )
    foreach ($pattern in $patterns) {
        if ($Output.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Invoke-Winget {
    param(
        [string]$Winget,
        [string[]]$Arguments
    )

    return Invoke-NativeCommand -Path $Winget -Arguments $Arguments -DisplayName ("winget " + ($Arguments -join " "))
}

function Install-MissingDevTools {
    Write-Step "按需补齐开发工具"
    $tools = @(
        [pscustomobject]@{ Name = "Git"; Id = "Git.Git" },
        [pscustomobject]@{ Name = "Node.js"; Id = "OpenJS.NodeJS.LTS" },
        [pscustomobject]@{ Name = "Python 3"; Id = "Python.Python.3.14" },
        [pscustomobject]@{ Name = "GitHub CLI"; Id = "GitHub.cli" }
    )

    $missing = New-Object System.Collections.Generic.List[object]
    foreach ($tool in $tools) {
        if (Test-DevToolPresent -Name $tool.Name) {
            Write-Success "$($tool.Name)：已存在，保留当前版本。"
        } else {
            $missing.Add($tool)
            Write-Line "$($tool.Name)：缺失，将通过 winget 安装 $($tool.Id)。" Yellow
        }
    }

    if ($missing.Count -eq 0) {
        Write-Success "开发工具均已可用；未执行升级或降级。"
        return
    }

    $winget = Get-CommandPath -Candidates @("winget.exe", "winget")
    if ([string]::IsNullOrWhiteSpace($winget)) {
        throw "请求了 -InstallDevTools，但未找到 winget，无法补齐：$((@($missing) | ForEach-Object { $_.Name }) -join '、')。"
    }

    foreach ($tool in @($missing)) {
        $arguments = @(
            "install",
            "--id", $tool.Id,
            "--exact",
            "--source", "winget",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--disable-interactivity",
            "--silent"
        )
        $result = Invoke-Winget -Winget $winget -Arguments $arguments
        Refresh-ProcessPath

        if ($result.ExitCode -ne 0 -and -not (Test-WingetNoActionSuccess -Output $result.Output)) {
            throw "$($tool.Name) 安装失败，winget ExitCode=$($result.ExitCode)。"
        }
        if (-not (Test-DevToolPresent -Name $tool.Name)) {
            throw "$($tool.Name) 安装后仍无法执行。请重新打开终端检查 PATH，然后重试。"
        }
        Write-Success "$($tool.Name) 已可用。"
    }
}

function Test-DesktopAppInstalled {
    param(
        [string]$Winget
    )

    $arguments = @(
        "list",
        "--id", $DesktopStoreId,
        "--exact",
        "-s", "msstore",
        "--accept-source-agreements",
        "--disable-interactivity"
    )
    $result = Invoke-Winget -Winget $Winget -Arguments $arguments
    return ($result.ExitCode -eq 0 -and $result.Output.IndexOf($DesktopStoreId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Install-DesktopAppFromWinget {
    param([string]$Winget)

    $verb = "install"
    if ($Update -and (Test-DesktopAppInstalled -Winget $Winget)) {
        $verb = "upgrade"
    }

    $arguments = @(
        $verb,
        "--id", $DesktopStoreId,
        "--exact",
        "-s", "msstore",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )
    $result = Invoke-Winget -Winget $Winget -Arguments $arguments
    if ($result.ExitCode -eq 0 -or (Test-WingetNoActionSuccess -Output $result.Output)) {
        if (Test-DesktopAppInstalled -Winget $Winget) {
            Write-Success "ChatGPT desktop app 的 Microsoft Store 路径已完成并通过二次确认。"
            return
        }
        throw "winget 报告成功或无需操作，但未能确认 Store ID $DesktopStoreId 已安装。"
    }

    throw "Microsoft Store 安装/更新失败，winget ExitCode=$($result.ExitCode)。"
}

function Assert-DesktopMsixIdentity {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Architecture
    )

    $expectedName = "OpenAI.Codex"
    $expectedPublisher = "CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B"
    $archive = $null
    $manifestStream = $null
    $xmlReader = $null

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $manifestEntries = @(
            $archive.Entries |
                Where-Object { $_.FullName -ieq "AppxManifest.xml" }
        )
        if ($manifestEntries.Count -ne 1) {
            throw "MSIX 必须且只能包含一个根目录 AppxManifest.xml。"
        }
        if ($manifestEntries[0].Length -lt 1 -or $manifestEntries[0].Length -gt 4194304) {
            throw "MSIX AppxManifest.xml 大小异常。"
        }

        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $manifestStream = $manifestEntries[0].Open()
        $xmlReader = [System.Xml.XmlReader]::Create($manifestStream, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($xmlReader)
        $identity = $document.SelectSingleNode(
            "/*[local-name()='Package']/*[local-name()='Identity']"
        )
        if ($null -eq $identity) {
            throw "MSIX AppxManifest.xml 缺少 Package/Identity。"
        }

        $actualName = [string]$identity.GetAttribute("Name")
        $actualPublisher = [string]$identity.GetAttribute("Publisher")
        $actualArchitecture = [string]$identity.GetAttribute("ProcessorArchitecture")
        if ($actualName -cne $expectedName) {
            throw "MSIX Identity Name 不匹配（实际：$actualName）。"
        }
        if ($actualPublisher -cne $expectedPublisher) {
            throw "MSIX Identity Publisher 不匹配（实际：$actualPublisher）。"
        }
        if (-not $actualArchitecture.Equals($Architecture, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "MSIX ProcessorArchitecture 不匹配（期望：$Architecture；实际：$actualArchitecture）。"
        }
    } catch {
        throw "ChatGPT desktop app MSIX 清单校验失败：$(Protect-LogText $_.Exception.Message)"
    } finally {
        if ($null -ne $xmlReader) { $xmlReader.Dispose() }
        if ($null -ne $manifestStream) { $manifestStream.Dispose() }
        if ($null -ne $archive) { $archive.Dispose() }
    }

    Write-Success "ChatGPT desktop app MSIX 身份、发布者与 $Architecture 架构检查通过。"
}

function Install-DesktopAppFromMsix {
    param([string]$Architecture)

    $url = $(if ($Architecture -eq "arm64") { $DesktopMsixArm64Url } else { $DesktopMsixX64Url })
    $fileName = $(if ($Architecture -eq "arm64") { "ChatGPT-arm64.msix" } else { "ChatGPT-x64.msix" })
    $script:DesktopMsixPath = Join-Path $script:WorkDir $fileName
    Download-File `
        -Name "ChatGPT desktop app MSIX ($Architecture)" `
        -Url $url `
        -OutFile $script:DesktopMsixPath `
        -MinimumBytes 1048576 `
        -MaximumBytes 1073741824 `
        -TimeoutMilliseconds 3600000

    Assert-DesktopMsixIdentity -Path $script:DesktopMsixPath -Architecture $Architecture

    $signature = Get-AuthenticodeSignature -LiteralPath $script:DesktopMsixPath
    if ($null -eq $signature -or $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        $statusText = $(if ($null -eq $signature) { "Unknown" } else { [string]$signature.Status })
        throw "ChatGPT desktop app MSIX 签名无效（Status=$statusText），已拒绝安装。"
    }
    if ($null -eq $signature.SignerCertificate) {
        throw "ChatGPT desktop app MSIX 缺少签名证书，已拒绝安装。"
    }
    Write-Success "ChatGPT desktop app MSIX Authenticode 签名有效。"

    $addAppxPackage = Get-Command Add-AppxPackage -CommandType Cmdlet -ErrorAction SilentlyContinue
    if ($null -eq $addAppxPackage) {
        throw "当前系统缺少 Add-AppxPackage，无法安装并由 Windows 验证 MSIX 签名。"
    }

    # Add-AppxPackage 会再次执行 Windows 包签名/信任链校验；失败会抛错。
    Add-AppxPackage -Path $script:DesktopMsixPath -ErrorAction Stop
    Write-Success "ChatGPT desktop app MSIX 已由 Add-AppxPackage 验证并安装。"
}

function Install-DesktopApp {
    param([string]$Architecture)

    Write-Step "安装/更新 ChatGPT desktop app"
    $wingetError = $null
    $winget = Get-CommandPath -Candidates @("winget.exe", "winget")
    if (-not [string]::IsNullOrWhiteSpace($winget)) {
        try {
            Install-DesktopAppFromWinget -Winget $winget
            return
        } catch {
            $wingetError = Protect-LogText $_.Exception.Message
            Write-Warn "Microsoft Store / winget 路径未完成：$wingetError"
        }
    } else {
        $wingetError = "未找到 winget"
        Write-Warn "未找到 winget，将使用官方固定架构 MSIX。"
    }

    try {
        Write-Info "回退到 OpenAI 官方固定架构 MSIX，并验证 Authenticode 签名。"
        Install-DesktopAppFromMsix -Architecture $Architecture
    } catch {
        throw "ChatGPT desktop app 安装失败。winget：$wingetError；MSIX：$(Protect-LogText $_.Exception.Message)"
    }
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory=$true)][string]$Path)

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
    } catch {
        throw "无法规范化安装目标路径：$Path"
    }
}

function Test-SamePath {
    param(
        [Parameter(Mandatory=$true)][string]$Left,
        [Parameter(Mandatory=$true)][string]$Right
    )

    $leftPath = Get-NormalizedFullPath -Path $Left
    $rightPath = Get-NormalizedFullPath -Path $Right
    return $leftPath.Equals($rightPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PreferredCodexCommand {
    Refresh-ProcessPath
    $command = Get-Command -Name "codex" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) { return $null }
    return $command.Path
}

function Get-StandaloneCodexTarget {
    $visibleBinDir = $script:ValidatedCodexInstallDir
    if ([string]::IsNullOrWhiteSpace($visibleBinDir) -and -not [string]::IsNullOrWhiteSpace($env:CODEX_INSTALL_DIR)) {
        $visibleBinDir = Resolve-CodexInstallDirectory -Value $env:CODEX_INSTALL_DIR
    }
    if ([string]::IsNullOrWhiteSpace($visibleBinDir)) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw "无法确定 standalone 默认目录：LOCALAPPDATA 为空。"
        }
        $visibleBinDir = Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex\bin"
    }
    return (Join-Path $visibleBinDir "codex.exe")
}

function Get-NpmCodexTargets {
    $npm = $script:NpmExecutable
    if ([string]::IsNullOrWhiteSpace($npm)) {
        Refresh-ProcessPath
        $npm = Get-CommandPath -Candidates @("npm.cmd", "npm.exe", "npm")
    }
    if ([string]::IsNullOrWhiteSpace($npm)) {
        throw "无法定位用于本次安装的 npm，不能验收全局 Codex 目标。"
    }

    $prefixResult = Invoke-NativeCommand `
        -Path $npm `
        -Arguments @("prefix", "--global") `
        -DisplayName "npm prefix --global"
    if ($prefixResult.ExitCode -ne 0) {
        throw "npm prefix --global 失败，ExitCode=$($prefixResult.ExitCode)。"
    }

    $prefix = $null
    foreach ($line in @($prefixResult.Output -split "`r?`n")) {
        $candidate = ([string]$line).Trim().Trim('"')
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            $prefix = $candidate
        }
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        throw "npm prefix --global 未返回可用的全局目录。"
    }

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($name in @("codex.cmd", "codex.exe")) {
        $candidate = Join-Path $prefix $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $targets.Add($candidate)
        }
    }
    if ($targets.Count -eq 0) {
        throw "npm 全局目录中不存在 codex.cmd/codex.exe：$prefix"
    }
    return @($targets)
}

function Get-RequestedCodexVersion {
    param([string]$RequestedRelease)

    $value = $RequestedRelease.Trim()
    if ($value -ceq "latest") { return $null }
    return (Get-NpmRelease -RequestedRelease $value)
}

function Confirm-CodexVersion {
    param(
        [ValidateSet("standalone", "npm")][string]$Method,
        [string]$RequestedRelease
    )

    Write-Step "验证 Codex CLI"
    if ($Method -eq "standalone") {
        $expectedTargets = @(Get-StandaloneCodexTarget)
    } else {
        $expectedTargets = @(Get-NpmCodexTargets)
    }

    foreach ($target in $expectedTargets) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "$Method 安装目标不存在：$target"
        }
    }

    $codex = Get-PreferredCodexCommand
    if ([string]::IsNullOrWhiteSpace($codex)) {
        throw "PATH 中未找到本次 $Method 安装后的 codex 命令。"
    }
    $pathMatchesTarget = $false
    foreach ($target in $expectedTargets) {
        if (Test-SamePath -Left $codex -Right $target) {
            $pathMatchesTarget = $true
            break
        }
    }
    if (-not $pathMatchesTarget) {
        throw "PATH 首选 codex 不是本次 $Method 安装目标。首选：$codex；目标：$($expectedTargets -join ' 或 ')"
    }

    $result = Invoke-NativeCommand -Path $codex -Arguments @("--version") -DisplayName "codex --version"
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        throw "codex --version 验证失败，ExitCode=$($result.ExitCode)。"
    }

    $expectedVersion = Get-RequestedCodexVersion -RequestedRelease $RequestedRelease
    if (-not [string]::IsNullOrWhiteSpace($expectedVersion)) {
        $versionMatch = [regex]::Match(
            $result.Output,
            '(?<![0-9A-Za-z])v?([0-9]+\.[0-9]+\.[0-9]+(?:-alpha(?:\.[0-9]+){0,2}|-beta(?:\.[0-9]+)?)?)(?![0-9A-Za-z.+-])'
        )
        if (-not $versionMatch.Success) {
            throw "codex --version 未返回可识别的版本号。"
        }
        $actualVersion = $versionMatch.Groups[1].Value
        if ($actualVersion -cne $expectedVersion) {
            throw "Codex CLI 版本不匹配。期望：$expectedVersion；实际：$actualVersion"
        }
        Write-Success "Codex CLI 与显式请求版本 $expectedVersion 一致。"
    }

    Write-Success "Codex CLI 验证通过：$($result.Output.Trim())"
    return $codex
}

function Invoke-CodexDoctorAdvisory {
    param([string]$Codex)

    Write-Step "Codex doctor（建议性检查）"
    try {
        $result = Invoke-NativeCommand -Path $Codex -Arguments @("doctor", "--summary", "--no-color", "--ascii") -DisplayName "codex doctor --summary --no-color --ascii"
        if ($result.ExitCode -eq 0) {
            Write-Success "codex doctor 建议性检查通过。"
        } else {
            Write-Warn "codex doctor 返回 ExitCode=$($result.ExitCode)。这可能与终端能力或尚未登录有关，不影响 CLI 安装成功判定。"
        }
    } catch {
        Write-Warn "codex doctor 无法完成：$(Protect-LogText $_.Exception.Message)。这是建议性检查，不影响 CLI 安装成功判定。"
    }
}

function Show-PostInstallGuide {
    Write-Step "后续配置参考（安装器不会自动改配置）"
    Write-Line '个人配置：$HOME\.codex\config.toml' White
    Write-Line '项目配置：项目目录\.codex\config.toml（仅信任项目后加载）' White
    Write-Line "" White
    Write-Line "打开并备份个人配置：" White
    Write-Line '  New-Item -ItemType Directory -Force "$HOME\.codex" | Out-Null' DarkGray
    Write-Line '  if (Test-Path "$HOME\.codex\config.toml") { Copy-Item "$HOME\.codex\config.toml" "$HOME\.codex\config.toml.bak" }' DarkGray
    Write-Line '  notepad "$HOME\.codex\config.toml"' DarkGray
    Write-Line "" White
    Write-Line "安全起点示例：" White
    Write-Line '  model = "gpt-5.6"' DarkGray
    Write-Line '  model_reasoning_effort = "medium"' DarkGray
    Write-Line '  approval_policy = "on-request"' DarkGray
    Write-Line '  sandbox_mode = "workspace-write"' DarkGray
    Write-Line "" White
    Write-Line "修改后验证：" White
    Write-Line "  codex --strict-config --version" DarkGray
    Write-Line "  codex doctor --summary" DarkGray
    Write-Line "完整案例：docs/configuration.md" White
    Write-Line "官方参考：https://learn.chatgpt.com/docs/config-file/config-basic" White
}

function Remove-DownloadedArtifacts {
    foreach ($path in @($script:BootstrapPath, $script:DesktopMsixPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

$desktopRequested = ([bool]$InstallDesktopApp -or [bool]$RequireDesktopApp)
$desktopUnsupportedReason = $null
$osInfo = $null
$architecture = $null

try {
    Assert-TestOverridesAreCheckOnly
    Assert-ReleaseValue -Value $Release
    Assert-BootstrapSha256 -Value $BootstrapSha256
    Assert-NpmRegistry -Value $NpmRegistry
    if ($CliMethod -eq "standalone" -and -not [string]::IsNullOrWhiteSpace($env:CODEX_INSTALL_DIR)) {
        $script:ValidatedCodexInstallDir = Resolve-CodexInstallDirectory -Value $env:CODEX_INSTALL_DIR
    }
    $osInfo = Get-WindowsInfo
    $architecture = Get-NormalizedArchitecture -ReportedArchitecture $osInfo.Architecture
    Assert-SupportedEnvironment -OsInfo $osInfo -Architecture $architecture
    if ($desktopRequested -and $osInfo.Version.Build -lt $DesktopMinimumOsBuild) {
        $desktopUnsupportedReason = "ChatGPT desktop app 最低需要 Windows 10 build 19041；当前为 $($osInfo.Version)，将跳过 Store/MSIX。"
        if ($RequireDesktopApp) {
            throw "-RequireDesktopApp 已启用，但 $desktopUnsupportedReason"
        }
    }
    Show-Plan -OsInfo $osInfo -Architecture $architecture -DesktopRequested:$desktopRequested
    if (-not [string]::IsNullOrWhiteSpace($desktopUnsupportedReason)) {
        Write-Warn "可选桌面应用不满足系统版本门槛：$desktopUnsupportedReason"
    }
} catch {
    Write-Host ""
    Write-Host "$ActionName 预检失败：$(Protect-LogText $_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($CheckOnly -and -not $VerifyDownloads) {
    Write-Host ""
    Write-Host "CheckOnly 完成：未下载、未安装、未修改用户目录。" -ForegroundColor Green
    exit 0
}

$exitCode = 0
$partialFailures = New-Object System.Collections.Generic.List[string]

try {
    Enable-Tls12
    $script:WorkDir = New-PrivateWorkDirectory
    Initialize-PrivateLog -Directory $script:WorkDir
    Write-Line "Codex Windows 一键${ActionName}开始。" Cyan
    if ($CheckOnly) {
        Write-Line "临时验证目录将在完成时自动清理。" DarkGray
    } else {
        Write-Line "日志目录：$script:WorkDir" DarkGray
    }

    if ($CliMethod -eq "standalone" -or $VerifyDownloads) {
        $script:BootstrapPath = Join-Path $script:WorkDir ("official-bootstrap-" + [guid]::NewGuid().ToString("N") + ".ps1")
        Download-OfficialBootstrap -OutFile $script:BootstrapPath
        Write-Success "bootstrap 来源：$(if ($script:BootstrapSource -eq 'github') { 'OpenAI GitHub Release' } else { 'OpenAI CDN' })"
    }

    if ($CheckOnly) {
        Write-Success "CheckOnly + VerifyDownloads 完成：官方 bootstrap 已下载并验证，但未执行任何安装。"
    } else {
        if ($InstallDevTools) {
            try {
                Install-MissingDevTools
            } catch {
                $devToolsError = Protect-LogText $_.Exception.Message
                $partialFailures.Add("开发工具补缺：$devToolsError")
                Write-Warn "可选开发工具未全部补齐；主 CLI 安装路径仍将继续尝试。详细信息：$devToolsError"
            }
        }

        if ($CliMethod -eq "standalone") {
            Invoke-StandaloneInstall -BootstrapPath $script:BootstrapPath -RequestedRelease $Release
        } else {
            Install-CliWithNpm
        }

        $codexCommand = Confirm-CodexVersion -Method $CliMethod -RequestedRelease $Release

        if ($desktopRequested -and -not [string]::IsNullOrWhiteSpace($desktopUnsupportedReason)) {
            $partialFailures.Add("ChatGPT desktop app：$desktopUnsupportedReason")
            Write-Warn "PARTIAL：$desktopUnsupportedReason"
        } elseif ($desktopRequested) {
            try {
                Install-DesktopApp -Architecture $architecture
            } catch {
                $desktopError = Protect-LogText $_.Exception.Message
                if ($RequireDesktopApp) {
                    throw "RequireDesktopApp 已启用：$desktopError"
                }
                $partialFailures.Add("ChatGPT desktop app：$desktopError")
                Write-Warn "ChatGPT desktop app 未完成；CLI 仍继续验收。详细信息：$desktopError"
            }
        }

        Invoke-CodexDoctorAdvisory -Codex $codexCommand
        Show-PostInstallGuide

        Write-Line ""
        if ($partialFailures.Count -gt 0) {
            Write-Line "${ActionName}完成（部分成功）：Codex CLI 已通过验证，但部分可选组件未完成。" Yellow
            foreach ($failure in $partialFailures) {
                Write-Line "  - $(Protect-LogText $failure)" Yellow
            }
        } else {
            Write-Success "${ActionName}完成：Codex CLI 已通过强制版本验证。"
        }
        Write-Line "请运行 codex，并按提示使用 ChatGPT 账号登录。" White
        Write-Line "首次登录也可运行：codex login" White
    }
} catch {
    $exitCode = 1
    Write-Line ""
    Write-Line "$ActionName 失败：$(Protect-LogText $_.Exception.Message)" Red
} finally {
    if ($CheckOnly) {
        if (-not [string]::IsNullOrWhiteSpace($script:WorkDir)) {
            Remove-Item -LiteralPath $script:WorkDir -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $script:WorkDir) {
                $exitCode = 1
                Write-Host "CheckOnly 临时目录清理失败；已将本次检查标记为失败。" -ForegroundColor Red
            }
        }
        $script:BootstrapPath = $null
        $script:DesktopMsixPath = $null
        $script:LogFile = $null
        $script:WorkDir = $null
    } else {
        Remove-DownloadedArtifacts
        if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
            Write-Line "日志位置：$script:LogFile" DarkGray
        }
    }
    if (-not $CheckOnly -and -not $NonInteractive -and -not $NoPause) {
        try {
            $null = Read-Host "按 Enter 键退出"
        } catch {}
    }
}

exit $exitCode
