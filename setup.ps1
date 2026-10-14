<#
  dsh-tray-launcher · 设置向导 / Settings wizard
  ------------------------------------------------------------------
  第一次拿到本文件夹时双击 setup.cmd；托盘右键菜单里的「设置」也会打开同一个窗口。
  第一步选择语言（简体中文 / English / 日本語 / 한국어 / Русский），
  第二步选择 Harness 路径（带浏览按钮），下面是三个启动选项和一个快捷方式按钮。
  点「保存」写入 settings.json 并按需维护开机自启。

  Runs as a WinForms (STA) dialog, shared by setup.cmd and the tray's
  "Settings" menu. Labels switch language immediately.
#>
[CmdletBinding()]
param()

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
  Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"' + $PSCommandPath + '"')) `
    -WindowStyle Hidden
  exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir    = $PSScriptRoot
$SettingsPath = Join-Path $ScriptDir 'settings.json'

try {
  Add-Type -Namespace DshTray -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop
  [void][DshTray.Dpi]::SetProcessDPIAware()
} catch { }

function New-UiFont {
  $preferred = @('Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI')
  try {
    $installed = @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
    foreach ($name in $preferred) {
      if ($installed -contains $name) {
        return (New-Object System.Drawing.Font -ArgumentList @($name, [single]9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point))
      }
    }
  } catch { }
  return [System.Drawing.SystemFonts]::MessageBoxFont
}

$script:Languages = [ordered]@{
  zh = '简体中文'
  en = 'English'
  ja = '日本語'
  ko = '한국어'
  ru = 'Русский'
}
$script:LangCodes = @($script:Languages.Keys)

$script:Strings = @{
  title              = @{ zh='dsh-tray-launcher · 设置'; en='dsh-tray-launcher · Settings'; ja='dsh-tray-launcher · 設定'; ko='dsh-tray-launcher · 설정'; ru='dsh-tray-launcher · Настройки' }
  lblLang            = @{ zh='语言 / Language：'; en='Language:'; ja='言語 / Language：'; ko='언어 / Language:'; ru='Язык / Language:' }
  lblPath            = @{ zh='Harness 路径（留空 = 全局 dsh）：'; en='Harness path (empty = global dsh):'; ja='Harness パス（空欄 = グローバル dsh）:'; ko='Harness 경로 (비우면 전역 dsh):'; ru='Путь к Harness (пусто = глобальный dsh):' }
  btnBrowse          = @{ zh='浏览…'; en='Browse…'; ja='参照…'; ko='찾아보기…'; ru='Обзор…' }
  lblCmd             = @{ zh='启动命令：'; en='Launch command:'; ja='起動コマンド：'; ko='시작 명령:'; ru='Команда запуска:' }
  lblPort            = @{ zh='端口：'; en='Port:'; ja='ポート：'; ko='포트:'; ru='Порт:' }
  chkTrayAutostart   = @{ zh='开机自动启动托盘工具'; en='Start the tray tool at logon'; ja='ログオン時にトレイツールを起動'; ko='로그온 시 트레이 도구 시작'; ru='Запускать трей-инструмент при входе' }
  chkStartHarness    = @{ zh='开机自动启动 DeepSeek Harness'; en='Start DeepSeek Harness at logon'; ja='ログオン時に DeepSeek Harness を起動'; ko='로그온 시 DeepSeek Harness 시작'; ru='Запускать DeepSeek Harness при входе' }
  chkOpenBrowser     = @{ zh='开机启动 + 弹出浏览器'; en='Start at logon and open browser'; ja='ログオン時に起動してブラウザを開く'; ko='로그온 시 시작 후 브라우저 열기'; ru='Запуск при входе и открытие браузера' }
  btnDesktopShortcut = @{ zh='创造桌面快捷方式'; en='Create desktop shortcut'; ja='デスクトップショートカットを作成'; ko='바탕화면 바로가기 만들기'; ru='Создать ярлык на рабочем столе' }
  btnSave            = @{ zh='保存'; en='Save'; ja='保存'; ko='저장'; ru='Сохранить' }
  btnCancel          = @{ zh='取消'; en='Cancel'; ja='キャンセル'; ko='취소'; ru='Отмена' }
  hintDetected       = @{ zh='已自动检测到 Harness 仓库：{0}'; en='Detected Harness repo: {0}'; ja='Harness リポジトリを検出：{0}'; ko='Harness 저장소 감지됨: {0}'; ru='Обнаружен репозиторий Harness: {0}' }
  hintGlobal         = @{ zh='已检测到全局 dsh 命令，路径可留空。'; en='A global dsh command was found; the path can stay empty.'; ja='グローバル dsh を検出。パスは空欄で構いません。'; ko='전역 dsh 명령을 찾았습니다. 경로를 비워도 됩니다.'; ru='Найдена глобальная команда dsh; путь можно оставить пустым.' }
  hintNone           = @{ zh='未自动检测到 Harness。请点“浏览”选择仓库根目录（含 pnpm-workspace.yaml 与 apps\cli 的目录）。'; en='Harness not detected. Click "Browse" to pick the repo root (a folder with pnpm-workspace.yaml and apps\cli).'; ja='Harness を検出できません。「参照」でリポジトリルート（pnpm-workspace.yaml と apps\cli を含む）を選択してください。'; ko='Harness를 찾지 못했습니다. "찾아보기"로 저장소 루트(pnpm-workspace.yaml과 apps\cli가 있는 폴더)를 선택하세요.'; ru='Harness не обнаружен. Нажмите «Обзор» и выберите корень репозитория (папку с pnpm-workspace.yaml и apps\cli).' }
  msgPortInvalid     = @{ zh='端口必须是 1-65535 的整数。'; en='Port must be an integer between 1 and 65535.'; ja='ポートは 1-65535 の整数で指定してください。'; ko='포트는 1-65535 사이의 정수여야 합니다.'; ru='Порт должен быть целым числом от 1 до 65535.' }
  msgSaved           = @{ zh='设置已保存到 settings.json。'; en='Settings saved to settings.json.'; ja='settings.json に保存しました。'; ko='settings.json에 저장했습니다.'; ru='Настройки сохранены в settings.json.' }
  msgShortcutCreated = @{ zh='桌面快捷方式已创建。'; en='Desktop shortcut created.'; ja='デスクトップショートカットを作成しました。'; ko='바탕화면 바로가기를 만들었습니다.'; ru='Ярлык на рабочем столе создан.' }
  msgAutostartFailed = @{ zh='设置已保存，但开机自启写入注册表失败：'; en='Settings saved, but writing the autostart registry entry failed: '; ja='設定は保存しましたが、自動起動のレジストリ書き込みに失敗：'; ko='설정은 저장했지만 자동 시작 레지스트리 쓰기에 실패: '; ru='Настройки сохранены, но запись автозапуска в реестр не удалась: ' }
  msgLaunchNow       = @{ zh='现在启动托盘吗？'; en='Start the tray now?'; ja='今すぐトレイを起動しますか？'; ko='지금 트레이를 시작할까요?'; ru='Запустить трей сейчас?' }
  msgErrorTitle      = @{ zh='错误'; en='Error'; ja='エラー'; ko='오류'; ru='Ошибка' }
  msgSaveFailed      = @{ zh='保存失败：'; en='Save failed: '; ja='保存に失敗：'; ko='저장 실패: '; ru='Ошибка сохранения: ' }
  dlgBrowseDesc      = @{ zh='选择 Harness 仓库根目录（含 pnpm-workspace.yaml 与 apps\cli）'; en='Pick the Harness repo root (folder with pnpm-workspace.yaml and apps\cli)'; ja='Harness リポジトリのルートを選択（pnpm-workspace.yaml と apps\cli を含む）'; ko='Harness 저장소 루트 선택 (pnpm-workspace.yaml과 apps\cli 포함)'; ru='Выберите корень репозитория Harness (папка с pnpm-workspace.yaml и apps\cli)' }
}

$script:Lang = 'zh'
$script:HintKind = 'none'
$script:HintArg  = ''

function T {
  param([string]$Key)
  if (-not $script:Strings.ContainsKey($Key)) { return $Key }
  $entry = $script:Strings[$Key]
  if ($entry.ContainsKey($script:Lang)) { return $entry[$script:Lang] }
  return $entry['en']
}

function Find-Harness {
  if (Get-Command dsh -ErrorAction SilentlyContinue) {
    return @{ Command = 'dsh web --no-open'; Root = '' }
  }
  $docs = [Environment]::GetFolderPath('MyDocuments')
  $candidates = @(
    $ScriptDir,
    (Split-Path -Parent $ScriptDir),
    (Join-Path $env:USERPROFILE 'deepseek-harness'),
    (Join-Path $env:USERPROFILE 'Documents\deepseek-harness'),
    (Join-Path $docs 'deepseek-harness')
  )
  foreach ($d in (Get-ChildItem -LiteralPath $docs -Directory -ErrorAction SilentlyContinue)) {
    if ($d.Name -like '*deepseek-harness*') { $candidates += $d.FullName }
  }
  $seen = @{}
  foreach ($c in $candidates) {
    if (-not $c -or $seen.ContainsKey($c)) { continue }
    $seen[$c] = $true
    if ((Test-Path -LiteralPath (Join-Path $c 'pnpm-workspace.yaml')) -and (Test-Path -LiteralPath (Join-Path $c 'apps\cli'))) {
      return @{ Command = 'pnpm dsh web --no-open'; Root = $c }
    }
  }
  return $null
}

function Set-TrayAutostart {
  param([bool]$Enabled)
  $runKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $runName  = 'dsh-tray-launcher'
  $wscript  = Join-Path $env:SystemRoot 'System32\wscript.exe'
  $runValue = '"' + $wscript + '" "' + (Join-Path $ScriptDir 'start-tray.vbs') + '" --at-logon'
  if ($Enabled) {
    if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    New-ItemProperty -Path $runKey -Name $runName -Value $runValue -PropertyType String -Force | Out-Null
  } else {
    Remove-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue
  }
}

function Test-TrayAutostart {
  $runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $runName = 'dsh-tray-launcher'
  return [bool](Get-ItemPropertyValue -Path $runKey -Name $runName -ErrorAction SilentlyContinue)
}

function New-DesktopShortcut {
  $desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'dsh-tray-launcher.lnk'
  $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
  $shell = New-Object -ComObject WScript.Shell
  if (Test-Path -LiteralPath $desktop) { Remove-Item -LiteralPath $desktop -Force }
  $sc = $shell.CreateShortcut($desktop)
  $sc.TargetPath       = $wscript
  $sc.Arguments        = '"' + (Join-Path $ScriptDir 'start-tray.vbs') + '" --open'
  $sc.WorkingDirectory = $ScriptDir
  $sc.Description      = 'dsh-tray-launcher'
  $ico = Join-Path $ScriptDir 'dsh-tray.ico'
  if (Test-Path -LiteralPath $ico) { $sc.IconLocation = $ico }
  $sc.Save()
}

function Save-Setup {
  param([string]$Root, [string]$Command, [int]$Port, [bool]$AutoOpen, [bool]$StartOnLaunch, [bool]$TrayAutostart, [string]$Language)
  $cfg = [ordered]@{
    language        = $Language
    repoRoot        = $Root
    port            = $Port
    harnessCommand  = $Command
    readyTimeoutSec = 180
    autoOpen        = $AutoOpen
    startOnLaunch   = $StartOnLaunch
    trayAutostart   = $TrayAutostart
  }
  $json = $cfg | ConvertTo-Json
  [System.IO.File]::WriteAllText($SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
  # 注册表写入单独兜底：失败不影响 settings.json 已保存的事实
  try {
    Set-TrayAutostart -Enabled $TrayAutostart
    return $null
  } catch {
    return $_.Exception.Message
  }
}

function Launch-Tray {
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') `
    -ArgumentList ('"' + (Join-Path $ScriptDir 'start-tray.vbs') + '"')
}

# ------------------------------ 界面 ------------------------------
$font = New-UiFont
$form = New-Object System.Windows.Forms.Form
$form.Size            = New-Object System.Drawing.Size(580, 510)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.Font            = $font

# 高 DPI（125% / 150%）下整体等比缩放：固定像素坐标不缩放的话，长文案会被窗口裁掉
$form.AutoScaleMode       = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96.0, 96.0)

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $Text
  $l.Location = New-Object System.Drawing.Point($X, $Y)
  $l.Size = New-Object System.Drawing.Size($W, $H)
  $l.AutoSize = $true          # 按文案自适应，别让长句被裁掉
  $form.Controls.Add($l)
  return $l
}

$hint = New-Label '' 20 14 524 42
$hint.AutoSize = $false

# 第一步：语言
$lblLang = New-Label '' 20 64 452 20
$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.DropDownStyle = 'DropDownList'
$cmbLang.Location = New-Object System.Drawing.Point(20, 86)
$cmbLang.Size = New-Object System.Drawing.Size(240, 26)
$cmbLang.Font = $font
foreach ($code in $script:LangCodes) { [void]$cmbLang.Items.Add($script:Languages[$code]) }
$form.Controls.Add($cmbLang)

# Harness 路径
$lblPath = New-Label '' 20 124 452 20
$txtRoot = New-Object System.Windows.Forms.TextBox
$txtRoot.Location = New-Object System.Drawing.Point(20, 146)
$txtRoot.Size = New-Object System.Drawing.Size(404, 24)
$form.Controls.Add($txtRoot)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(432, 145)
$btnBrowse.Size = New-Object System.Drawing.Size(86, 26)
$form.Controls.Add($btnBrowse)

# 启动命令
$lblCmd = New-Label '' 20 180 452 20
$txtCmd = New-Object System.Windows.Forms.TextBox
$txtCmd.Location = New-Object System.Drawing.Point(20, 202)
$txtCmd.Size = New-Object System.Drawing.Size(524, 24)
$form.Controls.Add($txtCmd)

# 端口
$lblPort = New-Label '' 20 236 452 20
$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Text = '3080'
$txtPort.Location = New-Object System.Drawing.Point(20, 258)
$txtPort.Size = New-Object System.Drawing.Size(90, 24)
$form.Controls.Add($txtPort)

# 三个启动勾选
$chkTrayAutostart = New-Object System.Windows.Forms.CheckBox
$chkTrayAutostart.Location = New-Object System.Drawing.Point(20, 292)
$chkTrayAutostart.Size = New-Object System.Drawing.Size(452, 22)
$form.Controls.Add($chkTrayAutostart)

$chkStartHarness = New-Object System.Windows.Forms.CheckBox
$chkStartHarness.Location = New-Object System.Drawing.Point(20, 318)
$chkStartHarness.Size = New-Object System.Drawing.Size(452, 22)
$form.Controls.Add($chkStartHarness)

$chkOpenBrowser = New-Object System.Windows.Forms.CheckBox
$chkOpenBrowser.Location = New-Object System.Drawing.Point(20, 344)
$chkOpenBrowser.Size = New-Object System.Drawing.Size(452, 22)
$form.Controls.Add($chkOpenBrowser)

# 创造桌面快捷方式按钮
$btnDesktopShortcut = New-Object System.Windows.Forms.Button
$btnDesktopShortcut.Location = New-Object System.Drawing.Point(20, 376)
$btnDesktopShortcut.Size = New-Object System.Drawing.Size(452, 30)
$form.Controls.Add($btnDesktopShortcut)

# 保存 / 取消
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Location = New-Object System.Drawing.Point(380, 424)
$btnSave.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnSave)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Location = New-Object System.Drawing.Point(478, 424)
$btnCancel.Size = New-Object System.Drawing.Size(74, 30)
$form.Controls.Add($btnCancel)

$form.AcceptButton = $btnSave
$form.CancelButton = $btnCancel

function Apply-Ui-Language {
  $form.Text         = T 'title'
  $lblLang.Text      = T 'lblLang'
  $lblPath.Text      = T 'lblPath'
  $btnBrowse.Text    = T 'btnBrowse'
  $lblCmd.Text       = T 'lblCmd'
  $lblPort.Text      = T 'lblPort'
  $chkTrayAutostart.Text   = T 'chkTrayAutostart'
  $chkStartHarness.Text    = T 'chkStartHarness'
  $chkOpenBrowser.Text     = T 'chkOpenBrowser'
  $btnDesktopShortcut.Text = T 'btnDesktopShortcut'
  $btnSave.Text      = T 'btnSave'
  $btnCancel.Text    = T 'btnCancel'

  if ($script:HintKind -eq 'detected') {
    $hint.Text = (T 'hintDetected') -f $script:HintArg
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
  } elseif ($script:HintKind -eq 'global') {
    $hint.Text = T 'hintGlobal'
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
  } else {
    $hint.Text = T 'hintNone'
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(190, 70, 0)
  }
}

# ------------------------------ 预填 ------------------------------
$detected = Find-Harness
if ($detected) {
  $txtRoot.Text = $detected.Root
  $txtCmd.Text  = $detected.Command
  if ($detected.Root) { $script:HintKind = 'detected'; $script:HintArg = $detected.Root }
  else { $script:HintKind = 'global' }
} else {
  $script:HintKind = 'none'
}

$existing = $null
if (Test-Path -LiteralPath $SettingsPath) {
  try { $existing = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
if ($existing) {
  if ($existing.language -and $script:Languages.Contains([string]$existing.language)) { $preset = [string]$existing.language } else { $preset = 'zh' }
  $chkStartHarness.Checked = [bool]$existing.startOnLaunch
  $chkOpenBrowser.Checked  = if ($null -ne $existing.autoOpen) { [bool]$existing.autoOpen } else { $true }
  $chkTrayAutostart.Checked = if ($null -ne $existing.trayAutostart) { [bool]$existing.trayAutostart } else { (Test-TrayAutostart) }
} else {
  $preset = 'zh'
  $chkStartHarness.Checked = $false
  $chkOpenBrowser.Checked  = $true
  $chkTrayAutostart.Checked = (Test-TrayAutostart)
}
$cmbLang.SelectedIndex = [array]::IndexOf($script:LangCodes, $preset)
$script:Lang = $preset
Apply-Ui-Language

$cmbLang.Add_SelectedIndexChanged({
  if ($cmbLang.SelectedIndex -ge 0) {
    $script:Lang = $script:LangCodes[$cmbLang.SelectedIndex]
    Apply-Ui-Language
  }
})

# ------------------------------ 事件 ------------------------------
$btnBrowse.Add_Click({
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = T 'dlgBrowseDesc'
  if ($txtRoot.Text -and (Test-Path -LiteralPath $txtRoot.Text)) { $dlg.SelectedPath = $txtRoot.Text }
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $txtRoot.Text = $dlg.SelectedPath
  }
})

$btnDesktopShortcut.Add_Click({
  try {
    New-DesktopShortcut
    [System.Windows.Forms.MessageBox]::Show((T 'msgShortcutCreated'), (T 'title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show((T 'msgSaveFailed') + $_.Exception.Message, (T 'msgErrorTitle'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

$btnSave.Add_Click({
  try {
    $port = 0
    if (-not [int]::TryParse($txtPort.Text, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
      [System.Windows.Forms.MessageBox]::Show((T 'msgPortInvalid'), (T 'title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
      return
    }
    $root = $txtRoot.Text.Trim()
    $cmd  = $txtCmd.Text.Trim()
    if (-not $cmd) { $cmd = 'pnpm dsh web --no-open' }
    $lang = $script:LangCodes[$cmbLang.SelectedIndex]
    $autoErr = Save-Setup -Root $root -Command $cmd -Port $port -AutoOpen $chkOpenBrowser.Checked -StartOnLaunch $chkStartHarness.Checked -TrayAutostart $chkTrayAutostart.Checked -Language $lang

    $msg = T 'msgSaved'
    if ($autoErr) { $msg += "`n" + (T 'msgAutostartFailed') + $autoErr }
    $r = [System.Windows.Forms.MessageBox]::Show($msg + "`n`n" + (T 'msgLaunchNow'), (T 'title'), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { Launch-Tray }
    $form.Close()
  } catch {
    [System.Windows.Forms.MessageBox]::Show((T 'msgSaveFailed') + $_.Exception.Message, (T 'msgErrorTitle'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  }
})

$btnCancel.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
