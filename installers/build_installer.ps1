# Script PowerShell para compilação automática do Instalador Windows do SixF Remote
Write-Host "Compilando SixF Remote Setup para Windows..." -ForegroundColor Cyan

$isccPath = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $isccPath)) {
    $isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path $isccPath)) {
    $isccPath = "C:\Program Files\Inno Setup 6\ISCC.exe"
}

if (-not (Test-Path $isccPath)) {
    Write-Host "Inno Setup 6 não encontrado. Instale com: winget install --id JRSoftware.InnoSetup" -ForegroundColor Red
    exit 1
}

$scriptPath = Join-Path $PSScriptRoot "sixf_installer.iss"
& $isccPath $scriptPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "Instalador gerado com sucesso em: build\installer\SixF_Remote_Setup_v0.9.8.exe" -ForegroundColor Green
} else {
    Write-Host "Erro ao gerar instalador." -ForegroundColor Red
}
