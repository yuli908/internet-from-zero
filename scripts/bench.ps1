# 性能基准跑批（headless）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1 -Sizes "50,60,70,80" -Frames 400
#
# 场景：
#   gate（默认）：N 个门每 tick 全翻转 + N 级 DFF 每帧一个时钟沿；
#   l3：同上再挂一个 4 位计数器（6 门 + 4 DFF），时钟周期 16 tick，仍 4 tick/帧。
# 输出：控制台表格 + artifacts/logs/bench.log + artifacts/logs/bench.json。
# 只负责跑与留证；"是否超预算"是数据结论，不作为脚本失败条件（未跑完才算失败）。

param(
	[string]$Root = "",
	[string]$Godot = "C:\tools\godot-4.4.1\godot.cmd",
	[string]$LogFile = "",
	[string]$Sizes = "50,100,200,300,400",
	[string]$Scenario = "gate",
	[int]$Frames = 600
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($LogFile)) {
	$LogFile = Join-Path $Root "artifacts\logs\bench.log"
}

if (-not (Test-Path (Join-Path $Root "project.godot"))) {
	Write-Host "[bench] FAIL 找不到工程：$Root\project.godot" -ForegroundColor Red
	exit 1
}
if (-not (Test-Path $Godot)) {
	Write-Host "[bench] FAIL 找不到 Godot 启动器：$Godot" -ForegroundColor Red
	exit 1
}

$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path $logDir)) {
	New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

Write-Host "[bench] root  : $Root"
Write-Host "[bench] scenario: $Scenario  sizes: $Sizes  frames: $Frames"
Write-Host "[bench] log   : $LogFile"

$engineArgs = @("--headless", "--path", $Root, "-s", "res://tests/bench_sim.gd", "--",
	"--scenario=$Scenario", "--sizes=$Sizes", "--frames=$Frames")
& $Godot @engineArgs 2>&1 | Out-File -FilePath $LogFile -Encoding utf8
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }

$text = ""
if (Test-Path $LogFile) {
	$text = Get-Content -Raw -Path $LogFile
}

# 打印表头、数据行与结论
$lines = $text -split "`r?`n"
foreach ($line in $lines) {
	if ($line -match "=== IFZ BENCH" -or $line -match "^size`t" -or $line -match "^godot=" -or
		$line -match "^\d+`t" -or $line -match "BENCH RESULT" -or $line -match "BENCH JSON") {
		Write-Host $line
	}
}

$done = $text -match "=== BENCH DONE ==="
if (-not $done) {
	Write-Host "[bench] FAIL 未看到 ``=== BENCH DONE ===``（基准没跑完）" -ForegroundColor Red
	Write-Host "[bench] 完整日志：$LogFile"
	exit 1
}
if ($code -ne 0) {
	Write-Host "[bench] FAIL 引擎返回码 $code" -ForegroundColor Red
	Write-Host "[bench] 完整日志：$LogFile"
	exit 1
}

Write-Host "[bench] PASS 基准完成（数据见上方表格与 artifacts/logs/bench.json）" -ForegroundColor Green
exit 0
