<#
    make_snapshot.ps1 - 실험용 데이터 스냅샷 고정 (실험계획서 5.2)
    ================================================================
    GitHub Actions 가 매일 02:00 KST 에 unipass_all_2b.json / 2c.json 을 갱신·커밋한다.
    실험 도중 ETL 을 다시 돌리면 표본이 바뀌어 E1~E13 의 수치가 서로 어긋난다.
    따라서 실험 시작 시점의 데이터를 이 스크립트로 고정한 뒤 실험을 시작한다.

    수행 내용
      1. unipass_all_2b.json / 2c.json (+ unipass_image.json) 복사
      2. 현재 커밋 해시·수집 일자 기록
      3. MySQL 덤프 (mysqldump 가 있으면 사용, 없으면 Python CSV 백업으로 대체)
      4. SNAPSHOT_INFO.md 작성

    실행:
      powershell -ExecutionPolicy Bypass -File Additional_Experiment\snapshot\make_snapshot.ps1
      powershell -ExecutionPolicy Bypass -File Additional_Experiment\snapshot\make_snapshot.ps1 -SkipDbDump
#>

param(
    [string]$Tag = (Get-Date -Format "yyyyMMdd"),
    [string]$MysqlDumpPath = $env:MYSQLDUMP,
    [switch]$SkipDbDump
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpRoot   = Split-Path -Parent $ScriptDir
$RepoRoot  = Split-Path -Parent $ExpRoot
$SnapDir   = Join-Path $ScriptDir "eval_snapshot_$Tag"

Write-Host "=== 실험 데이터 스냅샷 고정 ===" -ForegroundColor Cyan
Write-Host "저장소   : $RepoRoot"
Write-Host "스냅샷   : $SnapDir"

if (-not (Test-Path $SnapDir)) { New-Item -ItemType Directory -Path $SnapDir | Out-Null }

# ── 1) JSON 복사 ────────────────────────────────────────────
$targets = @("unipass_all_2b.json", "unipass_all_2c.json", "unipass_image.json")
$copied = @()
foreach ($f in $targets) {
    $src = Join-Path $RepoRoot $f
    if (Test-Path $src) {
        Copy-Item $src -Destination $SnapDir -Force
        $hash = (Get-FileHash $src -Algorithm SHA256).Hash.Substring(0, 16)
        $size = [math]::Round((Get-Item $src).Length / 1KB, 1)
        $copied += [pscustomobject]@{ File = $f; SizeKB = $size; Sha256 = $hash }
        Write-Host "  [복사] $f  ($size KB, sha256:$hash...)"
    } else {
        Write-Host "  [없음] $f" -ForegroundColor DarkYellow
    }
}

# ── 2) 커밋 정보 ────────────────────────────────────────────
Push-Location $RepoRoot
$commit = (git rev-parse HEAD).Trim()
$commitDate = (git log -1 --format=%cI).Trim()
$commitSubject = (git log -1 --format=%s).Trim()
$dirty = (git status --porcelain)
Pop-Location

$commit | Out-File -FilePath (Join-Path $SnapDir "COMMIT.txt") -Encoding utf8
Write-Host "  [커밋] $commit ($commitDate)"
if ($dirty) {
    Write-Host "  [경고] 커밋되지 않은 변경이 있습니다. 스냅샷 재현성이 떨어집니다." -ForegroundColor Yellow
}

# ── 3) DB 덤프 ──────────────────────────────────────────────
$dumpResult = "생략(-SkipDbDump)"
if (-not $SkipDbDump) {
    if (-not $MysqlDumpPath) {
        $cmd = Get-Command mysqldump -ErrorAction SilentlyContinue
        if ($cmd) {
            $MysqlDumpPath = $cmd.Source
        } else {
            $candidates = Get-ChildItem "C:\Program Files\MySQL\MySQL Server *\bin\mysqldump.exe" -ErrorAction SilentlyContinue
            if ($candidates) { $MysqlDumpPath = $candidates[0].FullName }
        }
    }

    if ($MysqlDumpPath -and (Test-Path $MysqlDumpPath)) {
        Write-Host "  [덤프] mysqldump: $MysqlDumpPath"
        $dbUser = if ($env:DB_USER) { $env:DB_USER } else { "root" }
        $dbName = if ($env:DB_NAME) { $env:DB_NAME } else { "customs_auction" }
        $dbHost = if ($env:DB_HOST) { $env:DB_HOST } else { "127.0.0.1" }
        $dumpFile = Join-Path $SnapDir "db_before.sql"
        Write-Host "        대상: $dbUser@$dbHost/$dbName -> db_before.sql"
        Write-Host "        비밀번호를 물으면 입력하세요 (명령행에 비밀번호를 남기지 않습니다)."
        & $MysqlDumpPath "-h" $dbHost "-u" $dbUser "-p" "--databases" $dbName "--result-file=$dumpFile"
        if ($LASTEXITCODE -eq 0) {
            $dumpResult = "db_before.sql ($([math]::Round((Get-Item $dumpFile).Length/1MB,2)) MB)"
            Write-Host "  [완료] $dumpResult" -ForegroundColor Green
        } else {
            $dumpResult = "mysqldump 실패(exit=$LASTEXITCODE)"
            Write-Host "  [실패] $dumpResult" -ForegroundColor Red
        }
    } else {
        Write-Host "  [대체] mysqldump 를 찾지 못했습니다. Python CSV 백업으로 대체합니다." -ForegroundColor Yellow
        $py = Join-Path $ScriptDir "snapshot_db.py"
        & python $py --out (Join-Path $SnapDir "db_before_csv")
        if ($LASTEXITCODE -eq 0) {
            $dumpResult = "db_before_csv/ (테이블별 CSV 백업)"
        } else {
            $dumpResult = "CSV 백업 실패"
        }
    }
}

# ── 4) 정보 파일 ────────────────────────────────────────────
$info = @()
$info += "# 실험 데이터 스냅샷 ($Tag)"
$info += ""
$info += "실험계획서 5.2 '데이터 스냅샷 고정' 에 따라 생성됨."
$info += ""
$info += "| 항목 | 값 |"
$info += "|---|---|"
$info += "| 생성 시각 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |"
$info += "| 커밋 해시 | $commit |"
$info += "| 커밋 일시 | $commitDate |"
$info += "| 커밋 제목 | $commitSubject |"
$info += "| 작업트리 상태 | $(if ($dirty) { '변경 있음(주의)' } else { 'clean' }) |"
$info += "| DB 백업 | $dumpResult |"
$info += ""
$info += "## 고정된 입력 파일"
$info += ""
$info += "| 파일 | 크기(KB) | SHA256(앞 16) |"
$info += "|---|---|---|"
foreach ($c in $copied) { $info += "| $($c.File) | $($c.SizeKB) | $($c.Sha256) |" }
$info += ""
$info += "## 규칙"
$info += ""
$info += "- 모든 실험은 이 스냅샷 기준 DB 에서만 수행한다."
$info += "- 실험 기간 중에는 ETL 을 재실행하지 않는다(E11 제외, E11 은 동일 스냅샷 재적재)."
$info += "- 논문 4.1절에 '수집 기준일: $($commitDate.Substring(0,10)), 물품 N건' 을 명시한다."

$info -join "`n" | Out-File -FilePath (Join-Path $SnapDir "SNAPSHOT_INFO.md") -Encoding utf8

Write-Host ""
Write-Host "완료: $SnapDir" -ForegroundColor Green
Write-Host "다음 단계: python Additional_Experiment\scripts\e00_preflight.py"
