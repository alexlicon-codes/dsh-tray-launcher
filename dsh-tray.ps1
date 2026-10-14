<#
  dsh-tray-launcher / Tray launcher for Windows
  ------------------------------------------------------------------
  作用：常驻系统托盘，一键启动并打开 DeepSeek Harness，不用再开终端敲命令。
  Usage: keeps a tray icon; starts and opens DeepSeek Harness for you.

  启动 Run : 双击 start-tray.vbs
  自启 Boot: 双击 install-autostart.cmd
  配置 Config: settings.json（语言、仓库路径、端口、启动命令）
  日志 Logs : tray.log（托盘自身）、harness.log（服务输出）

  菜单语言可在托盘右键菜单里切换，选择会写回 settings.json。
  Menu language is switchable from the tray menu; the choice is saved to settings.json.
#>
[CmdletBinding()]
param([switch]$NoAutoOpen, [switch]$AtLogon, [switch]$Open)

# NotifyIcon 必须在 STA 线程上运行 / NotifyIcon needs an STA thread
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
  $relaunchArgs = @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"' + $PSCommandPath + '"'))
  if ($NoAutoOpen) { $relaunchArgs += '-NoAutoOpen' }
  Start-Process -FilePath 'powershell.exe' -ArgumentList $relaunchArgs -WindowStyle Hidden
  exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir    = $PSScriptRoot
$IconPath     = Join-Path $ScriptDir 'dsh-tray.ico'
$LogPath      = Join-Path $ScriptDir 'harness.log'
$TrayLog      = Join-Path $ScriptDir 'tray.log'
$RunnerCmd    = Join-Path $ScriptDir 'run-harness.cmd'
$SettingsPath = Join-Path $ScriptDir 'settings.json'

# ------------- 默认配置 / defaults（可被 settings.json 覆盖） -------------
$Defaults = [ordered]@{
  language        = 'zh'                              # zh | en
  repoRoot        = ''                                # 启动命令的工作目录；留空表示用全局 dsh（setup 会填）
  port            = 3080
  harnessCommand  = 'pnpm dsh web --no-open'          # dsh web 自己会开浏览器，交给托盘决定，加 --no-open
  readyTimeoutSec = 180
  autoOpen        = $true                             # 服务就绪后自动打开浏览器
  startOnLaunch   = $false                            # 开机自启时是否立刻启动 Harness（false = 只驻留托盘，点图标才启动）
  trayAutostart   = $false                            # 托盘工具本身是否开机自启（由设置窗口维护注册表 Run 键）
}
# -------------------------------------------------------------------------

# 单实例：已有托盘在跑就安静退出 / single instance
$script:Mutex = New-Object System.Threading.Mutex -ArgumentList @($false, 'Local\DshTrayLauncher')
if (-not $script:Mutex.WaitOne(0, $false)) {
  # 已经有一份托盘在跑；若本次是「打开」请求（桌面快捷方式），留个请求文件让它代劳
  if ($Open) {
    try { Set-Content -LiteralPath (Join-Path $ScriptDir 'open.request') -Value '1' -Encoding ASCII } catch { }
  }
  exit 0
}

# ------------------------------ 文案表 ------------------------------
$script:Strings = @{
  open           = @{ zh='打开 DeepSeek Harness'; en='Open DeepSeek Harness'; ja='DeepSeek Harness を開く'; ko='DeepSeek Harness 열기'; ru='Открыть DeepSeek Harness' }
  restart        = @{ zh='重新启动 Harness'; en='Restart Harness'; ja='Harness を再起動'; ko='Harness 다시 시작'; ru='Перезапустить Harness' }
  stop           = @{ zh='停止 Harness'; en='Stop Harness'; ja='Harness を停止'; ko='Harness 중지'; ru='Остановить Harness' }
  viewLog        = @{ zh='查看日志'; en='View Log'; ja='ログを表示'; ko='로그 보기'; ru='Посмотреть журнал' }
  language       = @{ zh='语言 / Language'; en='Language / 语言'; ja='言語 / Language'; ko='언어 / Language'; ru='Язык / Language' }
  settings       = @{ zh='设置…'; en='Settings…'; ja='設定…'; ko='설정…'; ru='Настройки…' }
  exitKeep       = @{ zh='退出托盘（Harness 保持运行）'; en='Exit Tray (keep Harness running)'; ja='トレイを終了（Harness は実行継続）'; ko='트레이 종료 (Harness 계속 실행)'; ru='Выйти из трея (Harness продолжит работу)' }
  exitStop       = @{ zh='停止 Harness 并退出'; en='Stop Harness and exit'; ja='Harness を停止して終了'; ko='Harness 중지 후 종료'; ru='Остановить Harness и выйти' }
  stRunning      = @{ zh='运行中（端口 {0}）'; en='Running (port {0})'; ja='実行中（ポート {0}）'; ko='실행 중 (포트 {0})'; ru='Работает (порт {0})' }
  stStarting     = @{ zh='正在启动…'; en='Starting…'; ja='起動中…'; ko='시작 중…'; ru='Запуск…' }
  stStopped      = @{ zh='未运行（双击启动）'; en='Not running (double-click to start)'; ja='未実行（ダブルクリックで起動）'; ko='실행 안 됨 (더블 클릭으로 시작)'; ru='Не запущен (двойной щелчок для запуска)' }
  tipReady       = @{ zh='DeepSeek Harness 已就绪'; en='DeepSeek Harness is ready'; ja='DeepSeek Harness の準備ができました'; ko='DeepSeek Harness 준비됨'; ru='DeepSeek Harness готов' }
  tipTimeout     = @{ zh='启动超时，请点“查看日志”确认'; en='Startup timed out - check "View Log"'; ja='起動がタイムアウトしました。「ログを表示」で確認'; ko='시작 시간 초과 - "로그 보기" 확인'; ru='Время запуска истекло — проверьте «Журнал»' }
  tipStartFail   = @{ zh='启动失败，详见 tray.log'; en='Failed to start - see tray.log'; ja='起動に失敗しました。tray.log を参照'; ko='시작 실패 - tray.log 참조'; ru='Не удалось запустить — см. tray.log' }
  tipNoRepo      = @{ zh='仓库目录不存在，请检查 settings.json 的 repoRoot'; en='Repo folder not found - check repoRoot in settings.json'; ja='リポジトリが見つかりません。settings.json の repoRoot を確認'; ko='저장소 폴더 없음 - settings.json의 repoRoot 확인'; ru='Папка репозитория не найдена — проверьте repoRoot в settings.json' }
  tipNoRunner    = @{ zh='缺少 run-harness.cmd'; en='run-harness.cmd is missing'; ja='run-harness.cmd がありません'; ko='run-harness.cmd 없음'; ru='Отсутствует run-harness.cmd' }
  logTrayStart   = @{ zh='托盘启动'; en='Tray started'; ja='トレイを起動'; ko='트레이 시작됨'; ru='Трей запущен' }
  logLang        = @{ zh='语言切换为 {0}'; en='Language switched to {0}'; ja='言語を {0} に切り替え'; ko='언어를 {0}(으)로 전환'; ru='Язык изменён на {0}' }
  logAlready     = @{ zh='Harness 已在运行，端口 {0}'; en='Harness already running on port {0}'; ja='Harness はポート {0} で実行中'; ko='Harness가 포트 {0}에서 실행 중'; ru='Harness уже работает на порту {0}' }
  logLaunching   = @{ zh='已启动 Harness：PID {0}'; en='Launched Harness: PID {0}'; ja='Harness を起動：PID {0}'; ko='Harness 시작: PID {0}'; ru='Harness запущен: PID {0}' }
  logWaiting     = @{ zh='等待端口就绪…'; en='Waiting for the port to be ready…'; ja='ポートの準備を待っています…'; ko='포트 준비 대기 중…'; ru='Ожидание готовности порта…' }
  logReady       = @{ zh='服务已就绪'; en='Service is ready'; ja='サービス準備完了'; ko='서비스 준비됨'; ru='Служба готова' }
  logTimeout     = @{ zh='等待就绪超时'; en='Timed out waiting for readiness'; ja='準備待ちがタイムアウト'; ko='준비 대기 시간 초과'; ru='Превышено время ожидания готовности' }
  logStopped     = @{ zh='检测到服务已停止'; en='Service stopped'; ja='サービスの停止を検出'; ko='서비스 중지됨'; ru='Служба остановлена' }
  logStopReq     = @{ zh='请求停止 Harness'; en='Stop requested'; ja='停止を要求'; ko='중지 요청됨'; ru='Запрошена остановка' }
  logKilledPort  = @{ zh='已结束端口占用进程：{0} PID={1}'; en='Stopped the listener: {0} PID={1}'; ja='ポート占有プロセスを終了：{0} PID={1}'; ko='포트 점유 프로세스 종료: {0} PID={1}'; ru='Завершён процесс на порту: {0} PID={1}' }
  logForeignPort = @{ zh='端口被其他程序占用，未结束：{0}'; en='Port held by another program, not stopped: {0}'; ja='ポートは他のプログラムが使用中、未終了：{0}'; ko='다른 프로그램이 포트 사용 중, 중지 안 함: {0}'; ru='Порт занят другой программой, не остановлен: {0}' }
  logNoRepo      = @{ zh='仓库目录不存在：{0}'; en='Repo folder not found: {0}'; ja='リポジトリが見つかりません：{0}'; ko='저장소 폴더 없음: {0}'; ru='Папка репозитория не найдена: {0}' }
  logNoRunner    = @{ zh='缺少启动脚本：{0}'; en='Runner script missing: {0}'; ja='起動スクリプトがありません：{0}'; ko='실행 스크립트 없음: {0}'; ru='Сценарий запуска отсутствует: {0}' }
  logStartFail   = @{ zh='启动失败：{0}'; en='Start failed: {0}'; ja='起動に失敗：{0}'; ko='시작 실패: {0}'; ru='Ошибка запуска: {0}' }
  logSettingsBad = @{ zh='settings.json 解析失败，改用默认值：{0}'; en='Failed to parse settings.json, using defaults: {0}'; ja='settings.json の解析に失敗。デフォルトを使用：{0}'; ko='settings.json 구문 오류, 기본값 사용: {0}'; ru='Не удалось разобрать settings.json, используются значения по умолчанию: {0}' }
  logExit        = @{ zh='退出托盘'; en='Tray exiting'; ja='トレイを終了'; ko='트레이 종료'; ru='Выход из трея' }
  autoOpen       = @{ zh='就绪后自动打开浏览器'; en='Open browser when ready'; ja='準備完了後にブラウザを開く'; ko='준비되면 브라우저 열기'; ru='Открывать браузер после готовности' }
  logAutoOpen    = @{ zh='自动打开浏览器：{0}'; en='Auto-open browser: {0}'; ja='ブラウザ自動起動：{0}'; ko='브라우저 자동 열기: {0}'; ru='Автооткрытие браузера: {0}' }
  startOnLaunch  = @{ zh='登录时自动启动 Harness'; en='Start Harness at logon'; ja='ログオン時に Harness を起動'; ko='로그온 시 Harness 시작'; ru='Запускать Harness при входе в систему' }
  logStartLaunch = @{ zh='登录时自动启动 Harness：{0}'; en='Start Harness at logon: {0}'; ja='ログオン時起動：{0}'; ko='로그온 시 시작: {0}'; ru='Запуск при входе: {0}' }
  logLazyStart   = @{ zh='按设置不在登录时启动 Harness（点托盘图标即可启动）'; en='Not starting Harness at logon per settings (click the tray icon to start)'; ja='設定によりログオン時は起動しません（トレイアイコンで起動）'; ko='설정에 따라 로그온 시 시작하지 않음 (트레이 아이콘 클릭으로 시작)'; ru='Harness не запускается при входе (нажмите значок в трее)' }
}

# 语言清单：键 = settings.json 的 language 值；值 = 菜单里显示的原生名称
$script:Languages = [ordered]@{
  zh = '简体中文'
  en = 'English'
  ja = '日本語'
  ko = '한국어'
  ru = 'Русский'
}
$script:LangItems = @{}

$script:Lang = 'en'

function T {
  param([string]$Key)
  if (-not $script:Strings.ContainsKey($Key)) { return $Key }
  $entry = $script:Strings[$Key]
  if ($entry.ContainsKey($script:Lang)) { return $entry[$script:Lang] }
  return $entry['en']
}

function Write-TrayLog {
  param([string]$Message)
  try {
    Add-Content -LiteralPath $TrayLog -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $Message) -Encoding UTF8
  } catch { }
}

function To-Bool {
  # settings.json 里有人手写成 "true"/"1"/"yes" 字符串时也能正确判断
  param($Value)
  if ($Value -is [bool]) { return $Value }
  if ($null -eq $Value) { return $false }
  return (@('1', 'true', 'yes', 'on') -contains ([string]$Value).Trim().ToLower())
}

# ------------------------------ 配置读写 ------------------------------
function Load-Settings {
  $cfg = @{}
  foreach ($k in $Defaults.Keys) { $cfg[$k] = $Defaults[$k] }
  if (Test-Path -LiteralPath $SettingsPath) {
    try {
      $json  = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $names = @($json.PSObject.Properties | ForEach-Object { $_.Name })
      foreach ($k in $Defaults.Keys) {
        if (($names -contains $k) -and ($null -ne $json.$k)) {
          if (($k -eq 'autoOpen') -or ($k -eq 'startOnLaunch') -or ($k -eq 'trayAutostart')) { $cfg[$k] = To-Bool $json.$k }
          else { $cfg[$k] = $json.$k }
        }
      }
    } catch {
      # 文案表此刻可能还没就绪，先记英文
      try { Add-Content -LiteralPath $TrayLog -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + 'Failed to parse settings.json: ' + $_.Exception.Message) -Encoding UTF8 } catch { }
    }
  }
  return $cfg
}

function Save-Settings {
  $obj = [ordered]@{}
  foreach ($k in $Defaults.Keys) { $obj[$k] = $script:Cfg[$k] }
  try {
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
  } catch {
    Write-TrayLog ('settings.json 写入失败 / write failed: ' + $_.Exception.Message)
  }
}

$script:Cfg = Load-Settings
$script:Lang = [string]$script:Cfg.language
if (-not $script:Languages.Contains($script:Lang)) { $script:Lang = 'en' }
$script:Url = 'http://127.0.0.1:' + [string]$script:Cfg.port + '/'
# 首次运行落一份配置，方便用户直接改
if (-not (Test-Path -LiteralPath $SettingsPath)) { Save-Settings }

# ------------------------------ 状态 ------------------------------
$script:State           = 'unknown'
$script:HarnessProc     = $null
$script:AutoOpenPending = $false
$script:StartDeadline   = (Get-Date)
$script:TickCount       = 0

# ------------------------------ 工具函数 ------------------------------
function Test-HarnessUp {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect('127.0.0.1', [int]$script:Cfg.port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(400)) { return $false }
    $client.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    try { $client.Close() } catch { }
  }
}

function Show-Balloon {
  param([string]$Text)
  try {
    if ($script:Tray) {
      $script:Tray.BalloonTipTitle = 'dsh-tray-launcher'
      $script:Tray.BalloonTipText  = $Text
      $script:Tray.ShowBalloonTip(4000)
    }
  } catch { }
}

function Update-Ui {
  try {
    if ($script:State -eq 'running') {
      $script:Tray.Text = 'dsh-tray-launcher - ' + ((T 'stRunning') -f [string]$script:Cfg.port)
    } elseif ($script:State -eq 'starting') {
      $script:Tray.Text = 'dsh-tray-launcher - ' + (T 'stStarting')
    } else {
      $script:Tray.Text = 'dsh-tray-launcher - ' + (T 'stStopped')
    }
    $busy = ($script:State -eq 'running' -or $script:State -eq 'starting')
    $script:Items['stop'].Enabled    = $busy
    $script:Items['restart'].Enabled = $busy
  } catch { }
}

function Rotate-Log {
  try {
    if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt 5MB)) {
      Move-Item -LiteralPath $LogPath -Destination (Join-Path $ScriptDir 'harness.prev.log') -Force
    }
  } catch { }
}

function Ensure-ChildPath {
  $root = [string]$script:Cfg.repoRoot
  $candidates = @(
    (Join-Path $env:ProgramFiles 'nodejs'),
    (Join-Path $env:LOCALAPPDATA 'pnpm\bin')
  )
  if ($root) { $candidates += (Join-Path $root 'node_modules\.bin') }
  $candidates = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
  if ($candidates.Count -gt 0) {
    $env:PATH = ($candidates -join ';') + ';' + $env:PATH
  }
}

function Write-Runner {
  # run-harness.cmd 由 settings.json 生成，保持可单独双击运行
  $root = [string]$script:Cfg.repoRoot
  $cmd  = [string]$script:Cfg.harnessCommand
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('@echo off')
  $lines.Add('rem Generated by dsh-tray.ps1 from settings.json - manual edits are overwritten.')
  $lines.Add('setlocal')
  if ($root) { $lines.Add('cd /d "' + $root + '"') }   # 留空表示用全局 dsh，不切换目录
  $lines.Add('echo. >> "%~dp0harness.log"')
  $lines.Add('echo ===== %DATE% %TIME%  start: ' + $cmd + ' ===== >> "%~dp0harness.log"')
  $lines.Add('call ' + $cmd + ' >> "%~dp0harness.log" 2>&1')
  $lines.Add('echo ===== %DATE% %TIME%  exited with %ERRORLEVEL% ===== >> "%~dp0harness.log"')
  $lines.Add('endlocal')
  Set-Content -LiteralPath $RunnerCmd -Value $lines -Encoding ASCII
}

function Start-HarnessFlow {
  param([bool]$OpenWhenReady)

  # 已经在启动中：只记下“就绪后要打开”，绝不重复拉起第二份
  if ($script:State -eq 'starting') {
    if ($OpenWhenReady) { $script:AutoOpenPending = $true }
    return
  }

  if (Test-HarnessUp) {
    $script:State = 'running'
    Update-Ui
    if ($OpenWhenReady) { Start-Process $script:Url }
    return
  }
  $rootDir = [string]$script:Cfg.repoRoot
  if ($rootDir -and (-not (Test-Path -LiteralPath $rootDir))) {
    Write-TrayLog ((T 'logNoRepo') -f $rootDir)
    Show-Balloon (T 'tipNoRepo')
    return
  }
  # 留空 repoRoot 时用全局 dsh：工作目录退回脚本自身目录
  $workDir = $ScriptDir
  if ($rootDir -and (Test-Path -LiteralPath $rootDir)) { $workDir = $rootDir }

  Rotate-Log
  Ensure-ChildPath
  try {
    Write-Runner
  } catch {
    Write-TrayLog ((T 'logStartFail') -f $_.Exception.Message)
    Show-Balloon (T 'tipNoRunner')
    return
  }

  try {
    $script:HarnessProc = Start-Process -FilePath 'cmd.exe' `
      -ArgumentList @('/d', '/c', ('"' + $RunnerCmd + '"')) `
      -WorkingDirectory $workDir -WindowStyle Hidden -PassThru
    Write-TrayLog ((T 'logLaunching') -f [string]$script:HarnessProc.Id)
  } catch {
    Write-TrayLog ((T 'logStartFail') -f $_.Exception.Message)
    Show-Balloon (T 'tipStartFail')
    return
  }

  $script:State           = 'starting'
  $script:AutoOpenPending = $OpenWhenReady
  $script:StartDeadline   = (Get-Date).AddSeconds([int]$script:Cfg.readyTimeoutSec)
  Update-Ui
  Write-TrayLog (T 'logWaiting')
}

function Stop-Harness {
  Write-TrayLog (T 'logStopReq')
  if ($script:HarnessProc) {
    try {
      if (-not $script:HarnessProc.HasExited) {
        & taskkill.exe /PID $script:HarnessProc.Id /T /F 2>&1 | Out-Null
      }
    } catch { }
    $script:HarnessProc = $null
  }
  # 覆盖“在终端里手动启动”的情况：只结束监听该端口的 node 类进程
  try {
    $listeners = Get-NetTCPConnection -LocalPort ([int]$script:Cfg.port) -State Listen -ErrorAction Stop
    foreach ($l in $listeners) {
      $ownerProc = Get-Process -Id $l.OwningProcess -ErrorAction SilentlyContinue
      if ($ownerProc -and $ownerProc.ProcessName -match 'node|dsh|pnpm') {
        & taskkill.exe /PID $ownerProc.Id /T /F 2>&1 | Out-Null
        Write-TrayLog ((T 'logKilledPort') -f $ownerProc.ProcessName, [string]$ownerProc.Id)
      } else {
        $name = 'unknown'
        if ($ownerProc) { $name = $ownerProc.ProcessName }
        Write-TrayLog ((T 'logForeignPort') -f $name)
      }
    }
  } catch { }
  $script:State = 'stopped'
  Update-Ui
}

function Exit-Tray {
  Write-TrayLog (T 'logExit')
  try {
    $script:Timer.Stop()
    $script:Tray.Visible = $false
    $script:Tray.Dispose()
  } catch { }
  try { $script:Mutex.ReleaseMutex() } catch { }
  [System.Windows.Forms.Application]::Exit()
}

# ------------------------------ 字体 ------------------------------
# 高 DPI 下让文字走原生渲染，避免菜单被位图拉伸变糊
try {
  Add-Type -Namespace DshTray -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -ErrorAction Stop
  [void][DshTray.Dpi]::SetProcessDPIAware()
} catch { }

function New-UiFont {
  # 中英文混排都工整：优先中文 UI 字体，取不到再退回系统菜单字体
  $preferred = @('Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI')
  try {
    $installed = @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
    foreach ($name in $preferred) {
      if ($installed -contains $name) {
        return (New-Object System.Drawing.Font -ArgumentList @($name, [single]9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point))
      }
    }
  } catch { }
  return [System.Drawing.SystemFonts]::MenuItem
}
$script:UiFont = New-UiFont

# ------------------------------ 托盘与菜单 ------------------------------
$script:Tray = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path -LiteralPath $IconPath) {
  $script:Tray.Icon = New-Object System.Drawing.Icon($IconPath)
} else {
  $script:Tray.Icon = [System.Drawing.SystemIcons]::Application
}
$script:Tray.Text = 'dsh-tray-launcher'
$script:Tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Font = $script:UiFont
$menu.ShowImageMargin = $false      # 去掉左侧图标槽，文字左对齐更整齐
$menu.ShowCheckMargin = $false      # 主菜单没有勾选项（语言在子菜单里勾选）
$menu.Padding = New-Object System.Windows.Forms.Padding(2, 4, 2, 4)

$script:Items = @{}

function New-MenuItem {
  param([string]$Key, [scriptblock]$OnClick = $null)
  $mi = New-Object System.Windows.Forms.ToolStripMenuItem
  $mi.Text = T $Key
  $mi.Font = $script:UiFont
  if ($OnClick) { $mi.Add_Click($OnClick) }
  $script:Items[$Key] = $mi
  return $mi
}

function Apply-Language {
  foreach ($key in @($script:Items.Keys)) {
    $script:Items[$key].Text = T $key
  }
  foreach ($code in $script:Languages.Keys) {
    $script:LangItems[$code].Checked = ($script:Lang -eq $code)
  }
}

function Set-Language {
  param([string]$Code)
  if (-not $script:Languages.Contains($Code)) { return }
  if ($Code -eq $script:Lang) { return }
  $script:Lang = $Code
  $script:Cfg.language = $Code
  Save-Settings
  Apply-Language
  Update-Ui
  Write-TrayLog ((T 'logLang') -f $Code)
}

[void]$menu.Items.Add((New-MenuItem 'open' {
  if (Test-HarnessUp) {
    $script:State = 'running'
    Update-Ui
    Start-Process $script:Url
  } else {
    Start-HarnessFlow -OpenWhenReady $true
  }
}))
[void]$menu.Items.Add((New-MenuItem 'restart' {
  Stop-Harness
  Start-Sleep -Milliseconds 800
  Start-HarnessFlow -OpenWhenReady $true
}))
[void]$menu.Items.Add((New-MenuItem 'stop' { Stop-Harness }))
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((New-MenuItem 'viewLog' {
  if (Test-Path -LiteralPath $LogPath) { Start-Process -FilePath $LogPath }
  else { Start-Process -FilePath $TrayLog }
}))

# 设置：打开与 setup 相同的设置窗口（语言 / 路径 / 三个启动选项 / 桌面快捷方式）
[void]$menu.Items.Add((New-MenuItem 'settings' {
  Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $ScriptDir 'setup.ps1'))
}))

# 语言子菜单 / language submenu（5 种语言）
$script:ItemLang = New-MenuItem 'language'
$script:ItemLang.DropDown.ShowImageMargin = $false
$script:ItemLang.DropDown.ShowCheckMargin = $true
$script:ItemLang.DropDown.Font = $script:UiFont

foreach ($langCode in $script:Languages.Keys) {
  $langItem = New-Object System.Windows.Forms.ToolStripMenuItem
  $langItem.Text = $script:Languages[$langCode]
  $langItem.Font = $script:UiFont
  $langItem.CheckOnClick = $false
  $langItem.Tag = $langCode
  $langItem.Add_Click({ Set-Language ([string]$this.Tag) })
  $script:LangItems[$langCode] = $langItem
  [void]$script:ItemLang.DropDownItems.Add($langItem)
}
[void]$menu.Items.Add($script:ItemLang)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add((New-MenuItem 'exitKeep' { Exit-Tray }))
[void]$menu.Items.Add((New-MenuItem 'exitStop' {
  Stop-Harness
  Start-Sleep -Milliseconds 500
  Exit-Tray
}))

$script:Tray.ContextMenuStrip = $menu
$script:Tray.Add_MouseDoubleClick({
  if (Test-HarnessUp) { Start-Process $script:Url } else { Start-HarnessFlow -OpenWhenReady $true }
})

# ------------------------------ 状态心跳 ------------------------------
$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 500
$script:Timer.Add_Tick({
  $script:TickCount++
  # 另一份实例（例如桌面快捷方式带 --open）请求打开时由本实例代劳，保证 Harness 只有一份
  $reqFile = Join-Path $ScriptDir 'open.request'
  if (Test-Path -LiteralPath $reqFile) {
    Remove-Item -LiteralPath $reqFile -Force -ErrorAction SilentlyContinue
    if (Test-HarnessUp) { Start-Process $script:Url } else { Start-HarnessFlow -OpenWhenReady $true }
  }
  if (($script:TickCount % 2) -ne 0) { return }
  $up = Test-HarnessUp
  if ($script:State -eq 'starting') {
    if ($up) {
      $script:State = 'running'
      if ($script:AutoOpenPending) {
        $script:AutoOpenPending = $false
        Start-Process $script:Url
      }
      Update-Ui
      Show-Balloon (T 'tipReady')
      Write-TrayLog (T 'logReady')
    } elseif ((Get-Date) -gt $script:StartDeadline) {
      $script:State = 'stopped'
      $script:AutoOpenPending = $false
      Update-Ui
      Show-Balloon (T 'tipTimeout')
      Write-TrayLog (T 'logTimeout')
    }
  } elseif ($script:State -eq 'running') {
    if (-not $up) {
      $script:State = 'stopped'
      $script:HarnessProc = $null
      Update-Ui
      Write-TrayLog (T 'logStopped')
    }
  } else {
    if ($up) {
      $script:State = 'running'
      Update-Ui
    }
  }
})

# ------------------------------ 启动 ------------------------------
Apply-Language
if ($AtLogon) { Write-TrayLog ((T 'logTrayStart') + ' (logon)') } else { Write-TrayLog (T 'logTrayStart') }
$autoOpen = ((-not $NoAutoOpen) -and (To-Bool $script:Cfg.autoOpen))
if (Test-HarnessUp) {
  $script:State = 'running'
  Update-Ui
  Write-TrayLog ((T 'logAlready') -f [string]$script:Cfg.port)
  if ($autoOpen) { Start-Process $script:Url }
} elseif ($AtLogon -and (-not (To-Bool $script:Cfg.startOnLaunch))) {
  # 登录自启时只把托盘放上去：node/tsx 和浏览器都留到你真正要用那一刻，避免拖慢登录
  Update-Ui
  Write-TrayLog (T 'logLazyStart')
} else {
  Start-HarnessFlow -OpenWhenReady $autoOpen
}
# 桌面快捷方式带 --open：直接打开（必要时先启动 Harness）
if ($Open) {
  if (Test-HarnessUp) { Start-Process $script:Url }
  else { Start-HarnessFlow -OpenWhenReady $true }
}
$script:Timer.Start()
[System.Windows.Forms.Application]::Run()
