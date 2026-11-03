# 备份：git bundle（若 git 可用）+ robocopy 复制工作区。只增不删。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup.ps1 -SkipShots      # 不复制 artifacts/shots/*.png
#   powershell -ExecutionPolicy Bypass -File .\scripts\backup.ps1 -SkipBundle     # 不生成 git bundle
#
# 产物：
#   <Root>\backups\<ts>.bundle      git bundle（含全部分支，可用于离线恢复）
#   <Root>\backups\<ts>\            工作区文件副本
#
# 安全：robocopy 不带 /MIR、/PURGE，绝不删除源文件，也绝不删除已有备份目录内容。

param(
	[string]$Root = "",
	[string]$OutDir = "",
	[switch]$SkipShots,
	[switch]$SkipBundle
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Root)) {
	$Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path $Root).Path

if (-not (Test-Path (Join-Path $Root "project.godot"))) {
	Write-Host "[backup] FAIL 找不到工程：$Root\project.godot" -ForegroundColor Red
	exit 1
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
	$OutDir = Join-Path $Root "backups"
}
if (-not (Test-Path $OutDir)) {
	New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$bundlePath = Join-Path $OutDir "$ts.bundle"
$copyDir = Join-Path $OutDir $ts

Write-Host "=== 备份 ==="
Write-Host "root : $Root"
Write-Host "out  : $OutDir"
Write-Host "ts   : $ts"

$warnings = @()

# ---------------------------------------------------------------- 1. git bundle
if ($SkipBundle) {
	Write-Host "[1/2] git bundle：跳过（-SkipBundle）" -ForegroundColor Yellow
} elseif (-not (Test-Path (Join-Path $Root ".git"))) {
	Write-Host "[1/2] git bundle：跳过（不是 git 仓库）" -ForegroundColor Yellow
} else {
	$gitCmd = Get-Command git -ErrorAction SilentlyContinue
	if ($null -eq $gitCmd) {
		Write-Host "[1/2] git bundle：跳过（PATH 中找不到 git）" -ForegroundColor Yellow
	} else {
		Write-Host "[1/2] git bundle：$bundlePath"
		& git -C $Root bundle create $bundlePath --all 2>&1 | Out-Null
		$gitCode = $LASTEXITCODE
		if ($gitCode -ne 0 -or -not (Test-Path $bundlePath)) {
			Write-Host "[1/2] 警告：git bundle 失败（返回码 $gitCode），继续文件备份" -ForegroundColor Yellow
			$warnings += "git bundle 失败（返回码 $gitCode）"
		} else {
			$bundleSize = (Get-Item $bundlePath).Length
			Write-Host "[1/2] git bundle 完成：$([math]::Round($bundleSize / 1MB, 2)) MB" -ForegroundColor Green
		}
	}
}

# ---------------------------------------------------------------- 2. robocopy
Write-Host "[2/2] robocopy 复制工作区 -> $copyDir"
$roboArgs = @(
	$Root,
	$copyDir,
	"/E",
	"/R:1",
	"/W:1",
	"/NFL", "/NDL", "/NJH", "/NJS", "/NP",
	"/XD", ".godot", "backups", "native\build", "native\bin",
	"/XF", "*.tmp", "*.tmp.*"
)
if ($SkipShots) {
	$roboArgs += @("/XD", "artifacts\shots")
	Write-Host "        （-SkipShots：不复制 artifacts/shots）"
}

& robocopy @roboArgs | Out-Null
$roboCode = $LASTEXITCODE
if ($null -eq $roboCode) { $roboCode = 0 }

# robocopy 语义：0-7 为成功（0=无变化，1=有复制，2/3=目标侧多余文件），>=8 为失败。
if ($roboCode -ge 8) {
	Write-Host "[2/2] FAIL robocopy 返回码 $roboCode（>=8 视为失败；源文件未被修改）" -ForegroundColor Red
	exit 1
}
$files = @(Get-ChildItem -Path $copyDir -Recurse -File -ErrorAction SilentlyContinue)
$totalMB = 0
foreach ($f in $files) { $totalMB += $f.Length }
Write-Host "[2/2] 完成：$($files.Count) 个文件，$([math]::Round($totalMB / 1MB, 2)) MB（robocopy 返回码 $roboCode）" -ForegroundColor Green

Write-Host ""
Write-Host "=== 备份路径 ==="
if (Test-Path $bundlePath) { Write-Host "bundle : $bundlePath" }
Write-Host "files  : $copyDir"
if ($warnings.Count -gt 0) {
	Write-Host "警告：$($warnings -join '；')" -ForegroundColor Yellow
}
Write-Host "提示：恢复文件用 robocopy 反向复制；恢复 git 历史用 'git clone <bundle>'。"
exit 0
