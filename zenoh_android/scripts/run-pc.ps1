<#
.SYNOPSIS
    OpenBene PC side for Windows: start zenohd, print the LAN address to type
    into the phone, serve the live preview and open it in the browser.

.DESCRIPTION
    Mirrors zenoh_ios/scripts/run-pc.sh. The receiver itself is the Python
    package from the iOS branch, so point -ReceiverDir at that checkout.

.EXAMPLE
    .\run-pc.ps1 -ReceiverDir C:\work\OpenBene-zenoh\zenoh_ios\pc

.EXAMPLE
    .\run-pc.ps1 -Duration 30 -NoBrowser   # headless smoke test
#>
[CmdletBinding()]
param(
    [string]$Zenohd = $(if ($env:ZENOHD) { $env:ZENOHD } else { Join-Path $env:USERPROFILE 'Tools\zenoh\zenohd.exe' }),
    [string]$ReceiverDir = (Join-Path $PSScriptRoot '..\..\zenoh_ios\pc'),
    [int]$Port = 7447,
    [int]$ViewPort = 8080,
    [string]$RecordDir = '',
    [double]$Duration = 0,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

function Get-LanAddress {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.AddressState -eq 'Preferred'
        }
    $routes = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' }
    $withGateway = $candidates | Where-Object {
        $index = $_.InterfaceIndex
        $null -ne ($routes | Where-Object { $_.InterfaceIndex -eq $index })
    }
    $pick = if ($withGateway) { $withGateway | Select-Object -First 1 } else { $candidates | Select-Object -First 1 }
    if ($pick) { $pick.IPAddress } else { '<电脑IP>' }
}

function Test-TcpPort([int]$TargetPort) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $TargetPort, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(400) -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

$python = Join-Path $ReceiverDir '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
    Write-Host "接收端虚拟环境不存在: $python" -ForegroundColor Yellow
    Write-Host '先在 PC 接收端目录执行一次：'
    Write-Host "  cd $ReceiverDir"
    Write-Host '  python -m venv .venv'
    Write-Host '  .\.venv\Scripts\pip install -e .'
    exit 1
}
if (-not (Test-Path $Zenohd)) {
    Write-Host "找不到 zenohd: $Zenohd" -ForegroundColor Yellow
    Write-Host '下载并解压 zenoh 1.1.0 Windows 版，或用 -Zenohd 指定路径：'
    Write-Host '  curl.exe -L -o $env:TEMP\zenoh.zip https://github.com/eclipse-zenoh/zenoh/releases/download/1.1.0/zenoh-1.1.0-x86_64-pc-windows-msvc-standalone.zip'
    Write-Host "  Expand-Archive $env:TEMP\zenoh.zip -DestinationPath $(Split-Path $Zenohd -Parent) -Force"
    exit 1
}

if (-not $RecordDir) { $RecordDir = Join-Path $ReceiverDir 'runs' }
New-Item -ItemType Directory -Force -Path $RecordDir | Out-Null

$router = $null
if (Test-TcpPort $Port) {
    Write-Host "端口 $Port 已有监听，复用现有 router" -ForegroundColor DarkGray
} else {
    $routerLog = Join-Path $RecordDir 'zenohd.log'
    $router = Start-Process -FilePath $Zenohd -ArgumentList '--listen', "tcp/0.0.0.0:$Port" `
        -RedirectStandardOutput $routerLog -RedirectStandardError "$routerLog.err" -WindowStyle Hidden -PassThru
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if (Test-TcpPort $Port) { $ready = $true; break }
        if ($router.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) {
        Write-Host "zenohd 没能在 $Port 端口监听，日志：$routerLog" -ForegroundColor Red
        if (Test-Path $routerLog) { Get-Content $routerLog -Tail 10 }
        exit 1
    }
}

$lan = Get-LanAddress
$viewUrl = "http://127.0.0.1:$ViewPort/"
Write-Host ''
Write-Host "本机 IP : $lan" -ForegroundColor Green
Write-Host "手机填写: $lan`:$Port    （Robot ID 默认 rtr520）" -ForegroundColor Green
Write-Host "预览页  : $viewUrl"
Write-Host "录制    : 网页里点「开始录制」，文件写到 $RecordDir"
Write-Host '停止    : Ctrl+C'
Write-Host ''
Write-Host '等待手机连接……' -ForegroundColor DarkGray
Write-Host ''

$opener = $null
if (-not $NoBrowser) {
    $opener = Start-Job -ScriptBlock {
        param($Url)
        for ($i = 0; $i -lt 200; $i++) {
            try {
                Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 1 | Out-Null
                Start-Process $Url
                return
            } catch {
                Start-Sleep -Milliseconds 300
            }
        }
    } -ArgumentList $viewUrl
}

$cliArgs = @(
    '-m', 'openbene_receiver.cli',
    '--endpoint', "tcp/127.0.0.1:$Port",
    '--record-dir', $RecordDir,
    '--view', '--view-port', "$ViewPort",
    '--json'
)
if ($Duration -gt 0) { $cliArgs += @('--duration', "$Duration") }

try {
    & $python @cliArgs
} finally {
    if ($opener) { Stop-Job $opener -ErrorAction SilentlyContinue; Remove-Job $opener -Force -ErrorAction SilentlyContinue }
    if ($router -and -not $router.HasExited) {
        Stop-Process -Id $router.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host '已停止 router 与接收端。' -ForegroundColor DarkGray
}
