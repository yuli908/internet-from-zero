# 启动游戏（GUI）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\scripts\run_game.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\run_game.ps1 --shot=D:\ai lm\internet_from_zero\artifacts\shots\workbench.png --shot-screen=workbench --fresh
#
# 说明：`--` 之后的参数原样透传给游戏（--shot / --shot-screen / --shot-lab / --fresh 等）。
#       脚本自身只认 -Root / -Godot / -Resolution。

param(
	[string]$Root = "",
	[string]$Godot = "C:\tools\godot-4.4.1\godot.cmd",
	[string]$Resolution = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}

if (-not (Test-Path (Join-Path $Root "project.godot"))) {
	Write-Host "[run_game] FAIL 找不到工程：$Root\project.godot" -ForegroundColor Red
	exit 1
}

if (-not (Test-Path $Godot)) {
	Write-Host "[run_game] FAIL 找不到 Godot 启动器：$Godot" -ForegroundColor Red
	Write-Host "[run_game] 可用 -Godot 指定，例如 -Godot 'C:\tools\godot-4.4.1\godot.cmd'"
	exit 1
}

$engineArgs = @("--path", $Root)
if (-not [string]::IsNullOrWhiteSpace($Resolution)) {
	$engineArgs += @("--resolution", $Resolution)
}

# 若用户给了 --shot=<路径>，先把输出目录建好，避免截图静默失败。
foreach ($a in $args) {
	if ($a -like "--shot=*") {
		$shotPath = $a.Substring("--shot=".Length).Trim('"')
		$dir = Split-Path -Parent $shotPath
		if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
			New-Item -ItemType Directory -Force -Path $dir | Out-Null
			Write-Host "[run_game] 已创建截图目录：$dir"
		}
	}
}

if ($args.Count -gt 0) {
	$engineArgs += "--"
	$engineArgs += $args
}

Write-Host "[run_game] root : $Root"
Write-Host "[run_game] godot: $Godot"
Write-Host "[run_game] args : $($engineArgs -join ' ')"

& $Godot @engineArgs
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }

if ($code -ne 0) {
	Write-Host "[run_game] 引擎返回码 $code（非 0）" -ForegroundColor Red
	exit 1
}

Write-Host "[run_game] 正常退出" -ForegroundColor Green
exit 0
