# 全量测试（headless）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -ReplayLog <日志>
#
# 退出码（CI 只看这个：0=绿，非 0=红）：
#   0  PASS  终结行「=== ALL PASS ===」、RESULT 0 failures、SUITE_TOTAL expected=actual、引擎返回 0
#   1  FAIL  「RESULT: N checks, M failures」中 M > 0
#   2  FAIL  日志里没有 RESULT 行（测试没跑起来 / 日志被截断）
#   3  FAIL  日志里没有「=== ALL PASS ===」（崩溃、半途中断，或终结行是「=== FAILED ===」）
#   4  FAIL  SUITE_TOTAL expected≠actual（有 check 未执行：套件中途中止或被跳过）
#   5  FAIL  引擎返回码非 0（结果看着绿但进程异常）
#   6  FAIL  工程或 Godot 启动器不存在（环境问题，不跑）
#   7  FAIL  测试进程超过 -TimeoutSec 未退出（退出期自旋/死锁），已强杀（CI 兜底，绝不允许挂死）
#   8  FAIL  总账不闭合（四桶恒等式或逐条账目完整性/与 levels 的 gate 或 segs 声明不符）
#   9  FAIL  总账没跑起来（无 python / 脚本缺失 / 输出里没有 TOTAL 行）
#
# 判定只读 runner 的三条终结行（RESULT / 终结行 / SUITE_TOTAL），
# 不采用「grep 到 FAIL 就 exit 1」的粗口径。
# 测试跑完后还会跑 tools/lab_account.py：总账先于测试终结判定报错（8/9），
# 这样「某 lab 的 gate 数被改坏」时不会被测试红盖住；测试自身的红仍完整写在日志与上方关键行里。
# -ReplayLog 不跑 Godot，用现成日志走同一套判定，专门用来验证红/绿判定本身。
#
# 输出同时写入 artifacts/logs/tests.log；开跑前先删旧日志，禁止读到上一轮的 PASS。

param(
	[string]$Root = "",
	[string]$Godot = "C:\tools\godot-4.4.1\godot.cmd",
	[string]$LogFile = "",
	[string]$ReplayLog = "",
	[int]$TimeoutSec = 240
)

$ErrorActionPreference = "Continue"

# 统一出口：任何红色情形都打印原因、日志路径与退出码，然后 exit。
function Fail-Exit([string]$Reason, [int]$Code) {
	Write-Host "[run_tests] FAIL $Reason" -ForegroundColor Red
	Write-Host "[run_tests] 完整日志：$LogFile"
	Write-Host "[run_tests] exit=$Code" -ForegroundColor Red
	exit $Code
}

$replay = -not [string]::IsNullOrWhiteSpace($ReplayLog)
$engineCode = 0

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}

if ($replay) {
	$LogFile = $ReplayLog
	if (-not (Test-Path $LogFile)) {
		Fail-Exit "回放日志不存在：$LogFile" 2
	}
} else {
	if ([string]::IsNullOrWhiteSpace($LogFile)) {
		$LogFile = Join-Path $Root "artifacts\logs\tests.log"
	}
	if (-not (Test-Path (Join-Path $Root "project.godot"))) {
		Fail-Exit "找不到工程：$Root\project.godot" 6
	}
	if (-not (Test-Path $Godot)) {
		Fail-Exit "找不到 Godot 启动器：$Godot" 6
	}

	$logDir = Split-Path -Parent $LogFile
	if (-not (Test-Path $logDir)) {
		New-Item -ItemType Directory -Force -Path $logDir | Out-Null
	}

	# 先删旧日志：若本轮写入失败（文件被占用等），宁可「没有日志」判红，
	# 也不能让判定读到上一轮留下的 PASS 日志——那是假绿最直接的来源。
	if (Test-Path $LogFile) {
		Remove-Item -Force -Path $LogFile -ErrorAction SilentlyContinue
	}
	if (Test-Path $LogFile) {
		Fail-Exit "旧日志删不掉（被其它进程占用？）：$LogFile" 2
	}

	Write-Host "[run_tests] root : $Root"
	Write-Host "[run_tests] log  : $LogFile"

	# 带超时启动：Godot 走独立进程并落盘 stdout/stderr，避免管道缓冲导致 WaitForExit 假死，
	# 同时给 CI 一个硬上限——测试跑完若进程仍自旋，超时即强杀并判红，绝不让 CI 卡住。
	# 用 ProcessStartInfo 而不是 Start-Process：PS5.1 的 -PassThru 取不到 ExitCode（实测为 null），
	# 会误判成引擎异常。这里经 cmd.exe /c 启动，stdout/stderr 异步收进同一个缓冲区，
	# 既保留 2>&1 的合并口径，又能拿到真实返回码；再加 WaitForExit(超时) 兜底，绝不挂死 CI。
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = "cmd.exe"
	$psi.Arguments = '/c ""' + $Godot + '" --headless --path "' + $Root + '" -s res://tests/run_tests.gd 2>&1"'
	$psi.UseShellExecute = $false
	$psi.CreateNoWindow = $true
	$psi.WorkingDirectory = $Root
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true

	$proc = [System.Diagnostics.Process]::Start($psi)
	$buffer = New-Object System.Text.StringBuilder
	$subs = @()
	$subs += Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -MessageData $buffer -Action {
		[void]$Event.MessageData.AppendLine($EventArgs.Data)
	}
	$subs += Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -MessageData $buffer -Action {
		[void]$Event.MessageData.AppendLine($EventArgs.Data)
	}
	$proc.BeginOutputReadLine()
	$proc.BeginErrorReadLine()

	if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
		& taskkill /PID $proc.Id /T /F 2>&1 | Out-Null
		$partial = $buffer.ToString()
		$partial | Out-File -FilePath $LogFile -Encoding utf8
		foreach ($s in $subs) { Unregister-Event -SubscriptionId $s.Id -ErrorAction SilentlyContinue }
		$tail = $partial
		if ($tail.Length -gt 2000) { $tail = $tail.Substring($tail.Length - 2000) }
		Fail-Exit "测试进程超过 $TimeoutSec 秒未退出（退出期自旋/死锁？），已强杀。日志尾部：`n$tail" 7
	}
	$proc.WaitForExit()  # 等异步读取把最后几行刷完
	foreach ($s in $subs) { Unregister-Event -SubscriptionId $s.Id -ErrorAction SilentlyContinue }

	$engineCode = $proc.ExitCode
	$buffer.ToString() | Out-File -FilePath $LogFile -Encoding utf8
	if ($null -eq $engineCode) { $engineCode = -1 }  # 取不到返回码按异常处理，不当 0
}

$text = ""
if (Test-Path $LogFile) {
	$text = Get-Content -Raw -Path $LogFile
}
if ($null -eq $text) { $text = "" }

# 打印关键行，便于人工快速读结论
$lines = $text -split "`r?`n"
foreach ($line in $lines) {
	if ($line -match "RESULT:" -or $line -match "SUITE_TOTAL" -or $line -match "=== ALL PASS" -or $line -match "=== FAILED" -or $line -match "FAIL ") {
		Write-Host $line
	}
}

# ------------------------------------------------- 总账：一次扫 20 个 labs + 20 个 levels
# 8 = 账不闭合（恒等式、逐条完整性、或与 levels 的 gate 声明不符）
# 9 = 总账没跑起来（无 python / 脚本缺失 / 无 TOTAL 行）；与测试红（1）分开。
$accountScript = Join-Path $Root "tools\lab_account.py"
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) {
	Fail-Exit "总账没跑起来：找不到 python（无法执行 tools/lab_account.py）" 9
}
if (-not (Test-Path $accountScript)) {
	Fail-Exit "总账没跑起来：找不到 $accountScript" 9
}
$accountText = (& python $accountScript 2>&1 | Out-String)
$accountCode = $LASTEXITCODE
foreach ($line in ($accountText -split "`r?`n")) {
	if ($line -match "TOTAL|恒等式|验算|原因=|账目完整性|完整性：|与 levels|levels 声明|无 levels") {
		Write-Host $line
	}
}
if ($accountText -notmatch "TOTAL") {
	Fail-Exit "总账脚本没有输出 TOTAL 行（脚本没跑起来或输出被截断）" 9
}
if ($accountCode -ne 0 -or $accountText -notmatch "验算：闭合") {
	Fail-Exit "账不闭合（恒等式或逐条完整性校验失败；详见上方总账输出）" 8
}
Write-Host "[run_tests] 总账：闭合" -ForegroundColor Green

# ------------------------------------------------- 判定：只读 runner 的三条终结行
$checks = -1
$failures = -1
$m = [regex]::Match($text, "RESULT:\s*(\d+)\s*checks,\s*(\d+)\s*failures")
if (-not $m.Success) {
	Fail-Exit "未找到「RESULT: N checks, M failures」（测试可能没跑起来，或日志被截断）" 2
}
$checks = [int]$m.Groups[1].Value
$failures = [int]$m.Groups[2].Value

if ($failures -gt 0) {
	Fail-Exit "$checks 项检查中有 $failures 项失败" 1
}

# 终结行：取日志里最后一条「=== ALL PASS ===」或「=== FAILED ===」。
# 一条都没有 = 进程崩溃 / 半途中断 / 输出被截断，不能算通过。
$verdicts = [regex]::Matches($text, "=== (ALL PASS|FAILED) ===")
if ($verdicts.Count -eq 0) {
	Fail-Exit "日志里没有「=== ALL PASS ===」（进程崩溃、半途中断或输出被截断）" 3
}
$verdict = $verdicts[$verdicts.Count - 1].Groups[1].Value
if ($verdict -ne "ALL PASS") {
	Fail-Exit "终结行是「=== FAILED ===」" 3
}

# 套件总数：有 check 未执行（套件中途中止 / 被跳过）时 expected≠actual，同样要红。
$totals = [regex]::Matches($text, "SUITE_TOTAL expected=(\d+) actual=(\d+)")
if ($totals.Count -eq 0) {
	Fail-Exit "未找到「SUITE_TOTAL expected=... actual=...」（无法证明所有套件都跑完）" 4
}
$t = $totals[$totals.Count - 1]
$expTotal = [int]$t.Groups[1].Value
$actTotal = [int]$t.Groups[2].Value
if ($expTotal -ne $actTotal) {
	Fail-Exit "SUITE_TOTAL expected=$expTotal actual=$actTotal（有 check 未执行：套件中途中止或被跳过）" 4
}

if ($engineCode -ne 0) {
	Fail-Exit "引擎返回码 $engineCode（结果看着绿但进程非 0，按失败处理）" 5
}

Write-Host "[run_tests] PASS $checks checks, 0 failures (SUITE_TOTAL $expTotal/$actTotal)" -ForegroundColor Green
Write-Host "[run_tests] exit=0" -ForegroundColor Green
exit 0
