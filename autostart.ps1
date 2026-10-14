<#
  dsh-tray-launcher：新建 / 移除开机自启与桌面快捷方式
  ------------------------------------------------------------------
  用法：  powershell -NoProfile -ExecutionPolicy Bypass -File autostart.ps1 install
          powershell -NoProfile -ExecutionPolicy Bypass -File autostart.ps1 uninstall
  也可以直接双击 install-autostart.cmd / uninstall-autostart.cmd。

  为什么开机自启用注册表 Run 键，而不是「启动」文件夹里的 .lnk：
    部分系统上 WScript.Shell 保存/读取“路径含中文”的 .lnk 会直接失败
    （Unable to save shortcut；实测 ASCII 名可以、中文名必失败，连工作区里也失败）。
    注册表是 Unicode 原生，没有这场 ANSI 转换，而且同样会出现在
    任务管理器 →「启动」列表里，可以照常禁用。
  桌面快捷方式仍用 .lnk（文件名纯 ASCII）：它创建失败只影响桌面图标，不影响自启。

  控制台提示一律用 ASCII：cmd.exe 在非中文代码页下无法正确显示中文，
  而且 .cmd 里出现多字节字符会让批处理解析错位。中文详情只写进 autostart.log。
#>
[CmdletBinding()]
param([ValidateSet('install', 'uninstall')][string]$Action = 'install')

$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$vbs     = Join-Path $here 'start-tray.vbs'
$ico     = Join-Path $here 'dsh-tray.ico'
$logPath = Join-Path $here 'autostart.log'
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

$runKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runName  = 'dsh-tray-launcher'
# --at-logon 让托盘知道自己是被开机自启拉起的：那时只驻留图标，不启动 Harness
$runValue = '"' + $wscript + '" "' + $vbs + '" --at-logon'

$startupDir = [Environment]::GetFolderPath('Startup')
$desktopDir = [Environment]::GetFolderPath('Desktop')
# 旧版本（含中文名）可能留下的启动项，安装/卸载时都清掉，避免重复拉起
$legacyLinks = @(
  (Join-Path $startupDir 'DeepSeek Harness 托盘.lnk'),
  (Join-Path $startupDir 'dsh-tray-launcher.lnk')
)
$desktopLink = Join-Path $desktopDir 'dsh-tray-launcher.lnk'

function Write-Log {
  param([string]$Text, [string]$Extra = '')
  $stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $logLine = '[' + $stamp + '] ' + $Text
  if ($Extra) { $logLine = $logLine + '  |  ' + $Extra }
  try { Add-Content -LiteralPath $logPath -Value $logLine -Encoding UTF8 } catch { }
  Write-Host ('[' + $stamp + '] ' + $Text)
}

function Remove-LegacyLinks {
  foreach ($p in $legacyLinks) {
    if (Test-Path -LiteralPath $p) {
      Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      if (-not (Test-Path -LiteralPath $p)) { Write-Log ('Removed legacy startup item: ' + $p) }
    }
  }
}

if ($Action -eq 'install') {
  if (-not (Test-Path -LiteralPath $vbs)) { throw ('start-tray.vbs not found: ' + $vbs) }

  # 1) 开机自启：注册表 Run 键
  if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
  New-ItemProperty -Path $runKey -Name $runName -Value $runValue -PropertyType String -Force | Out-Null
  $check = Get-ItemPropertyValue -Path $runKey -Name $runName
  if ($check -ne $runValue) { throw ('Run key verify failed: ' + $check) }
  Write-Log ('Autostart registered: HKCU\...\Run\' + $runName + ' = ' + $runValue)
  Remove-LegacyLinks

  # 2) 桌面快捷方式（纯 ASCII 文件名）
  try {
    if (Test-Path -LiteralPath $desktopLink) { Remove-Item -LiteralPath $desktopLink -Force }
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($desktopLink)
    $sc.TargetPath       = $wscript
    $sc.Arguments        = '"' + $vbs + '"'
    $sc.WorkingDirectory = $here
    $sc.Description      = 'dsh-tray-launcher'
    if (Test-Path -LiteralPath $ico) { $sc.IconLocation = $ico }
    $sc.Save()
    Write-Log ('Desktop shortcut created: ' + $desktopLink)
  } catch {
    Write-Log ('Desktop shortcut failed (autostart is unaffected): ' + $_.Exception.Message)
  }

  Write-Host ''
  Write-Host 'Done. Autostart is registered under HKCU Run; check Task Manager > Startup.'
  Write-Host ('Log: ' + $logPath)
} else {
  try {
    if (Get-ItemPropertyValue -Path $runKey -Name $runName -ErrorAction SilentlyContinue) {
      Remove-ItemProperty -Path $runKey -Name $runName -Force
      Write-Log ('Autostart removed: ' + $runName)
    } else {
      Write-Log 'No autostart entry in the registry, skipped.'
    }
  } catch {
    Write-Log ('Failed to remove the Run entry: ' + $_.Exception.Message)
  }
  Remove-LegacyLinks
  if (Test-Path -LiteralPath $desktopLink) {
    Remove-Item -LiteralPath $desktopLink -Force
    Write-Log ('Desktop shortcut removed: ' + $desktopLink)
  }
  Write-Host ''
  Write-Host 'Done. Autostart and desktop shortcut removed; logs and settings are kept.'
}
