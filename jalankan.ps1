# Jalankan backend + sambungkan HP + jalankan aplikasi, dalam satu perintah.
# Pemakaian: klik dua kali jalankan.bat, atau  .\jalankan.ps1
# Syarat: HP tersambung USB, Debugging USB aktif, Docker Desktop sudah berjalan.

param([switch]$Build)   # tambahkan -Build hanya bila kode backend berubah

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$adb = "C:\Users\alfin\AppData\Local\Android\sdk\platform-tools\adb.exe"
$flutter = "C:\Users\alfin\flutter\bin\flutter.bat"

function Gagal($pesan) { Write-Host ""; Write-Host "GAGAL: $pesan" -ForegroundColor Red; exit 1 }

# 1. Backend
Write-Host "[1/4] Menyalakan backend (Docker)..." -ForegroundColor Cyan
& docker info *> $null
if ($LASTEXITCODE -ne 0) { Gagal "Docker belum berjalan. Buka Docker Desktop, tunggu siap, lalu ulangi." }
Push-Location "$root\backend"
if ($Build) { & docker compose up -d --build } else { & docker compose up -d }
$kode = $LASTEXITCODE
Pop-Location
if ($kode -ne 0) { Gagal "docker compose gagal (lihat pesan di atas)." }

# 2. Tunggu API siap (port 8001)
Write-Host "[2/4] Menunggu API siap di http://localhost:8001 ..." -ForegroundColor Cyan
$siap = $false
for ($i = 0; $i -lt 30; $i++) {
    try { Invoke-WebRequest "http://localhost:8001/docs" -UseBasicParsing -TimeoutSec 2 | Out-Null; $siap = $true; break }
    catch { Start-Sleep -Seconds 2 }
}
if (-not $siap) { Gagal "API belum merespons. Cek: docker compose logs api  (di folder backend)." }

# 3. Sambungkan HP
Write-Host "[3/4] Menyambungkan HP..." -ForegroundColor Cyan
if (-not (Test-Path $adb)) { Gagal "adb tidak ditemukan di $adb" }
$perangkat = (& $adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match "\sdevice$" }
if (-not $perangkat) { Gagal "HP tidak terdeteksi. Cek kabel, mode Transfer file, dan izinkan Debugging USB di layar HP." }
& $adb reverse tcp:8001 tcp:8001 | Out-Null

# 4. Aplikasi
Write-Host "[4/4] Menjalankan aplikasi di HP..." -ForegroundColor Cyan
Write-Host "Login OTP: ambil kode dari log backend -> docker compose logs api --tail 50 (di folder backend)" -ForegroundColor Yellow
Set-Location $root
$idHp = (@($perangkat)[0] -split "\s+")[0]
& $flutter run -d $idHp
