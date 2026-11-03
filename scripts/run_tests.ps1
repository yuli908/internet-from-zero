# 全量测试（headless）。
#
# 用法：powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1
#
# 解析 `RESULT: N checks, M failures`：
#   - M > 0            -> FAIL，exit 1
#   - 解析不到结果行    -> FAIL，exit 1（防止"测试没跑起来却当作通过"）
#   - 引擎返回码非 0     -> FAIL，exit 1
#
# 输出同时写入 artifacts/logs/tests.log。

param(
	[string]$Root = "",
	[string]$Godot = "C:\tools\godot-4.4.1\godot.cmd",
	[string]$LogFile = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($LogFile)) {
	$LogFile = Join-Path $Root "artifacts\logs\tests.log"
}

if (-not (Test-Path (Join-Path $Root "project.godot"))) {
	Write-Host "[run_tests] FAIL 找不到工程：$Root\project.godot" -ForegroundColor Red
	exit 1
}
if (-not (Test-Path $Godot)) {
	Write-Host "[run_tests] FAIL 找不到 Godot 启动器：$Godot" -ForegroundColor Red
	exit 1
}

$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path $logDir)) {
	New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

Write-Host "[run_tests] root : $Root"
Write-Host "[run_tests] log  : $LogFile"

& $Godot --headless --path $Root -s "res://tests/run_tests.gd" 2>&1 | Out-File -FilePath $LogFile -Encoding utf8
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }

$text = ""
if (Test-Path $LogFile) {
	$text = Get-Content -Raw -Path $LogFile
}

# 打印关键行，便于人工快速读结论
$lines = $text -split "`r?`n"
foreach ($line in $lines) {
	if ($line -match "RESULT:" -or $line -match "=== ALL PASS" -or $line -match "=== FAILED" -or $line -match "FAIL ") {
		Write-Host $line
	}
}

$checks = -1
$failures = -1
$m = [regex]::Match($text, "RESULT:\s*(\d+)\s*checks,\s*(\d+)\s*failures")
if ($m.Success) {
	$checks = [int]$m.Groups[1].Value
	$failures = [int]$m.Groups[2].Value
}

if (-not $m.Success) {
	Write-Host "[run_tests] FAIL 未找到 `RESULT: N checks, M failures`（测试可能没跑起来）" -ForegroundColor Red
	Write-Host "[run_tests] 完整日志：$LogFile"
	exit 1
}

if ($failures -gt 0) {
	Write-Host "[run_tests] FAIL $checks 项检查中有 $failures 项失败" -ForegroundColor Red
	Write-Host "[run_tests] 完整日志：$LogFile"
	exit 1
}

if ($code -ne 0) {
	Write-Host "[run_tests] FAIL 引擎返回码 $code（结果为 0 失败但进程非 0，按失败处理）" -ForegroundColor Red
	exit 1
}

Write-Host "[run_tests] PASS $checks checks, 0 failures" -ForegroundColor Green
exit 0
