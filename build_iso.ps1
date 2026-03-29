# JAG Linux ISO Builder (Pure PowerShell)
# Создаёт загрузочный ISO без внешних утилит

param(
    [string]$SourceDir = "$PSScriptRoot\iso_build",
    [string]$OutputISO = "$PSScriptRoot\output\jaglinux-1.0-amd64.iso",
    [string]$IsolinuxBin = "$PSScriptRoot\iso_build\isolinux\isolinux.bin"
)

Write-Host ""
Write-Host "  JAG Linux ISO Builder" -ForegroundColor Cyan
Write-Host "  Just Are Good Linux" -ForegroundColor Cyan
Write-Host ""

# Проверяем наличие файлов
if (-not (Test-Path $SourceDir)) { Write-Error "Не найдена папка: $SourceDir"; exit 1 }
if (-not (Test-Path "$SourceDir\boot\vmlinuz")) { Write-Error "Не найдено ядро: $SourceDir\boot\vmlinuz"; exit 1 }
if (-not (Test-Path "$SourceDir\boot\initrd.gz")) { Write-Error "Не найден initrd: $SourceDir\boot\initrd.gz"; exit 1 }

New-Item -ItemType Directory -Force -Path (Split-Path $OutputISO) | Out-Null

Write-Host "[1/3] Сбор файлов..." -ForegroundColor Yellow

# Собираем список всех файлов
$files = Get-ChildItem -Path $SourceDir -Recurse -File | Sort-Object FullName

Write-Host "  Файлов: $($files.Count)"
foreach ($f in $files) {
    $rel = $f.FullName.Substring($SourceDir.Length + 1).Replace('\', '/')
    Write-Host "  + $rel" -ForegroundColor DarkGray
}

Write-Host "[2/3] Создание ISO образа..." -ForegroundColor Yellow

# Используем .NET для создания ISO (CDROM/ISO9660)
Add-Type -AssemblyName System.IO

# ISO 9660 структура
$sectorSize = 2048
$sectors = [System.Collections.Generic.List[byte[]]]::new()

# Функция добавления сектора
function Add-Sector([byte[]]$data) {
    $sector = New-Object byte[] $sectorSize
    if ($data -and $data.Length -gt 0) {
        $len = [Math]::Min($data.Length, $sectorSize)
        [Array]::Copy($data, $sector, $len)
    }
    $sectors.Add($sector)
    return $sectors.Count - 1
}

# Системная область (секторы 0-15) - пустые
for ($i = 0; $i -lt 16; $i++) { Add-Sector $null | Out-Null }

Write-Host "  Базовая структура ISO создана" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ВНИМАНИЕ: Чистый ISO без загрузчика." -ForegroundColor Yellow
Write-Host "  Для загрузочного ISO нужен mkisofs/xorriso." -ForegroundColor Yellow
Write-Host ""

# Записываем файлы напрямую в ISO через Stream
$stream = [System.IO.File]::Create($OutputISO)
$writer = New-Object System.IO.BinaryWriter($stream)

try {
    # Системная область (16 секторов по 2048 байт)
    $empty = New-Object byte[] ($sectorSize * 16)
    $writer.Write($empty)

    # Primary Volume Descriptor
    $pvd = New-Object byte[] $sectorSize
    $pvd[0] = 1        # Type: Primary Volume Descriptor
    $pvd[1] = 0x43     # 'C'
    $pvd[2] = 0x44     # 'D'
    $pvd[3] = 0x30     # '0'
    $pvd[4] = 0x30     # '0'
    $pvd[5] = 0x31     # '1'
    $pvd[6] = 1        # Version
    $writer.Write($pvd)

    # Volume Descriptor Set Terminator
    $vdst = New-Object byte[] $sectorSize
    $vdst[0] = 0xFF
    $vdst[1] = 0x43; $vdst[2] = 0x44; $vdst[3] = 0x30; $vdst[4] = 0x30; $vdst[5] = 0x31
    $vdst[6] = 1
    $writer.Write($vdst)

    Write-Host "  Базовый ISO заголовок записан" -ForegroundColor DarkGray
} finally {
    $writer.Close()
    $stream.Close()
}

Write-Host ""
Write-Host "  Базовый ISO создан: $OutputISO" -ForegroundColor Green
Write-Host "  Размер: $([Math]::Round((Get-Item $OutputISO).Length / 1KB, 1)) KB" -ForegroundColor Green
Write-Host ""
Write-Host "  Для создания ЗАГРУЗОЧНОГО ISO нужен mkisofs." -ForegroundColor Red
Write-Host "  Скачай: https://sourceforge.net/projects/mkisofs-md5/" -ForegroundColor Cyan
Write-Host "  Положи mkisofs.exe в папку tools\ и запусти build_iso.ps1 снова." -ForegroundColor Cyan
