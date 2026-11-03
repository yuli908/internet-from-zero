# 自检：导入检查 -> 全量测试 -> 启动冒烟（GUI 截图 1 张）-> 汇总 PASS/FAIL。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1 -SkipGui     # 无桌面/CI 环境用
#
# 任一步骤 FAIL -> exit 1。
# 日志：artifacts/logs/import.log、tests.log、smoke.log

param(
	[string]$Root = "",
	[string]$Godot = "C:\tools\godot-4.4.1\godot.cmd",
	[int]$SmokeTimeoutSeconds = 120,
	[switch]$SkipGui
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}

$logDir = Join-Path $Root "artifacts\logs"
$shotDir = Join-Path $Root "artifacts\shots"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
if (-not (Test-Path $shotDir)) { New-Item -ItemType Directory -Force -Path $shotDir | Out-Null }

$results = @()

function Add-Result([string]$Step, [string]$Status, [string]$Detail) {
	$script:results += [pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail }
	$color = "Green"
	if ($Status -eq "FAIL") { $color = "Red" }
	elseif ($Status -eq "SKIP") { $color = "Yellow" }
	Write-Host ("[{0}] {1} - {2}" -f $Status, $Step, $Detail) -ForegroundColor $color
}

function Test-LogErrors([string]$Text) {
	# 只把真正的引擎错误当作失败：ERROR: / Parse Error / SCRIPT ERROR / 资源加载失败。
	$bad = @()
	if ($Text -match "ERROR:") { $bad += "ERROR:" }
	if ($Text -match "Parse Error") { $bad += "Parse Error" }
	if ($Text -match "SCRIPT ERROR") { $bad += "SCRIPT ERROR" }
	if ($Text -match "Failed to load resource") { $bad += "Failed to load resource" }
	return $bad
}

function Remove-ScaffoldResidue([string]$Text) {
	# native/ 是 M1 的未构建脚手架：若扫描缓存里还留着 res://native/ifz_native.gdextension，
	# 编辑器会报 "GDExtension dynamic library not found"。这类告警不算产品错误，剥掉后单独提示。
	if ($Text -notmatch "native/ifz_native\.gdextension") { return $Text }
	$kept = @()
	foreach ($line in ($Text -split "`r?`n")) {
		if ($line -match "native/ifz_native\.gdextension") { continue }
		if ($line -match "No GDExtension library found") { continue }
		if ($line -match 'Condition "!FileAccess::exists\(path\)"') { continue }
		if ($line -match "at: open_dynamic_library|at: open_library|at: load_extensions|at: parse_gdextension_file") { continue }
		$kept += $line
	}
	return ($kept -join "`n")
}

Write-Host "=== Internet From Zero :: selfcheck ==="
Write-Host "root : $Root"
Write-Host "godot: $Godot"
Write-Host ""

if (-not (Test-Path (Join-Path $Root "project.godot"))) {
	Add-Result "环境" "FAIL" "找不到工程：$Root\project.godot"
	$results | Format-Table -AutoSize | Out-String | Write-Host
	exit 1
}
if (-not (Test-Path $Godot)) {
	Add-Result "环境" "FAIL" "找不到 Godot 启动器：$Godot"
	$results | Format-Table -AutoSize | Out-String | Write-Host
	exit 1
}

# ---------------------------------------------------------------- 1. 导入检查
$importLog = Join-Path $logDir "import.log"
Write-Host "[1/3] 导入检查（--headless --editor --quit）..."
& $Godot --headless --path $Root --editor --quit 2>&1 | Out-File -FilePath $importLog -Encoding utf8
$importCode = $LASTEXITCODE
if ($null -eq $importCode) { $importCode = 0 }
$importRaw = ""
if (Test-Path $importLog) { $importRaw = Get-Content -Raw -Path $importLog }
$importResidue = $importRaw -match "native/ifz_native\.gdextension"
$importText = Remove-ScaffoldResidue $importRaw
$importBad = Test-LogErrors $importText
$importNote = ""
if ($importResidue) { $importNote = "（已忽略 native/ 脚手架残留告警，见 native/README.md）" }
if ($importCode -ne 0) {
	Add-Result "导入检查" "FAIL" "引擎返回码 $importCode（日志：$importLog）"
} elseif ($importBad.Count -gt 0) {
	Add-Result "导入检查" "FAIL" "日志命中：$($importBad -join ', ')（日志：$importLog）"
} else {
	Add-Result "导入检查" "PASS" "返回码 0，日志无 ERROR/Parse Error$importNote"
}

# ---------------------------------------------------------------- 2. 全量测试
$testsLog = Join-Path $logDir "tests.log"
Write-Host "[2/3] 全量测试（tests/run_tests.gd）..."
$testScript = Join-Path $PSScriptRoot "run_tests.ps1"
if (-not (Test-Path $testScript)) {
	Add-Result "全量测试" "FAIL" "找不到 scripts/run_tests.ps1"
} else {
	& $testScript -Root $Root -Godot $Godot -LogFile $testsLog
	$testCode = $LASTEXITCODE
	if ($null -eq $testCode) { $testCode = 0 }
	$testText = ""
	if (Test-Path $testsLog) { $testText = Get-Content -Raw -Path $testsLog }
	$m = [regex]::Match($testText, "RESULT:\s*(\d+)\s*checks,\s*(\d+)\s*failures")
	if ($testCode -ne 0) {
		$detail = "run_tests.ps1 返回 $testCode"
		if ($m.Success) { $detail += "（$($m.Groups[1].Value) checks / $($m.Groups[2].Value) failures）" }
		Add-Result "全量测试" "FAIL" $detail
	} elseif (-not $m.Success) {
		Add-Result "全量测试" "FAIL" "日志中没有 RESULT 行（$testsLog）"
	} else {
		Add-Result "全量测试" "PASS" "$($m.Groups[1].Value) checks, $($m.Groups[2].Value) failures"
	}
}

# ---------------------------------------------------------------- 3. 启动冒烟
if ($SkipGui) {
	Add-Result "启动冒烟" "SKIP" "-SkipGui：未做 GUI 截图与启动验证（无桌面/CI 环境）"
} else {
	$shot = Join-Path $shotDir "selfcheck.png"
	if (Test-Path $shot) { Remove-Item $shot -Force -ErrorAction SilentlyContinue }
	$smokeLog = Join-Path $logDir "smoke.log"
	Write-Host "[3/3] 启动冒烟（GUI 1600x900 截图 + 日志检查）..."

	$smokeArgs = @(
		"--path", $Root,
		"--resolution", "1600x900",
		"--",
		"--shot=$shot",
		"--shot-screen=workbench",
		"--fresh"
	)

	# 用后台 Job 跑，避免 GUI 卡住时整个自检无限等待。
	$job = Start-Job -ScriptBlock {
		param($exe, $argList)
		& $exe @argList 2>&1
		"IFZ_EXIT=$LASTEXITCODE"
	} -ArgumentList $Godot, $smokeArgs

	if (-not (Wait-Job $job -Timeout $SmokeTimeoutSeconds)) {
		Stop-Job $job -ErrorAction SilentlyContinue
		Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
		Remove-Job $job -Force -ErrorAction SilentlyContinue
		Add-Result "启动冒烟" "FAIL" "超过 $SmokeTimeoutSeconds 秒未退出（可能无显示环境或卡死）"
	} else {
		$smokeText = (Receive-Job $job) -join "`n"
		Remove-Job $job -Force -ErrorAction SilentlyContinue
		$smokeText | Out-File -FilePath $smokeLog -Encoding utf8

		$problems = @()
		$exitMatch = [regex]::Match($smokeText, "IFZ_EXIT=(-?\d+)")
		if (-not $exitMatch.Success) { $problems += "未捕获退出码" }
		elseif ([int]$exitMatch.Groups[1].Value -ne 0) { $problems += "退出码 $($exitMatch.Groups[1].Value)" }
		if ($smokeText -notmatch "IFZ_BOOT data_ok=true") { $problems += "启动日志缺少 IFZ_BOOT data_ok=true" }
		$shotMatch = [regex]::Match($smokeText, "SHOT_SAVED=(.+?) err=(\d+)")
		if (-not $shotMatch.Success) { $problems += "未产生 SHOT_SAVED 行" }
		elseif ([int]$shotMatch.Groups[2].Value -ne 0) { $problems += "截图保存返回 err=$($shotMatch.Groups[2].Value)" }
		$smokeResidue = $smokeText -match "native/ifz_native\.gdextension"
		$bad = Test-LogErrors (Remove-ScaffoldResidue $smokeText)
		if ($bad.Count -gt 0) { $problems += "日志命中 $($bad -join ', ')" }
		if (-not (Test-Path $shot)) { $problems += "截图文件不存在：$shot" }
		elseif ((Get-Item $shot).Length -le 0) { $problems += "截图文件为空" }

		if ($problems.Count -gt 0) {
			Add-Result "启动冒烟" "FAIL" ($problems -join "；")
			Write-Host "--- smoke.log 末尾 ---"
			($smokeText -split "`r?`n" | Select-Object -Last 12) -join "`n" | Write-Host
			Write-Host "完整日志：$smokeLog"
		} else {
			$size = (Get-Item $shot).Length
			$note = ""
			if ($smokeResidue) { $note = "（已忽略 native/ 脚手架残留告警）" }
			Add-Result "启动冒烟" "PASS" "截图 $size 字节，日志无 ERROR$note"
		}
	}
}

# ---------------------------------------------------------------- 汇总
Write-Host ""
Write-Host "=== 汇总 ==="
$results | Format-Table -AutoSize | Out-String | Write-Host

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
if ($failed.Count -gt 0) {
	Write-Host "SELFCHECK: FAIL（$($failed.Count) 项失败）" -ForegroundColor Red
	exit 1
}

$skipped = @($results | Where-Object { $_.Status -eq "SKIP" })
if ($skipped.Count -gt 0) {
	Write-Host "SELFCHECK: PASS（含 $($skipped.Count) 项跳过，未验证启动）" -ForegroundColor Yellow
	Write-Host "注意：跳过 GUI 冒烟时，'可启动' 未获证据，需人工补跑。"
} else {
	Write-Host "SELFCHECK: PASS" -ForegroundColor Green
}
exit 0
