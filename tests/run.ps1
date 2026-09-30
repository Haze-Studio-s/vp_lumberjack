# tests/run.ps1 — Quality Gate para vp_lumberjack
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$luac = 'luac.exe'
$failures = 0
$luaFiles = Get-ChildItem -Path $base -Recurse -Filter '*.lua' | Where-Object {
    $_.FullName -notmatch '\\tests\\' -and
    $_.FullName -notmatch '\\archive\\' -and
    $_.FullName -notmatch '\\_archive\\'
}
Write-Host ('[vp_lumberjack] Verificando ' + $luaFiles.Count + ' arquivos Lua...')
foreach ($f in $luaFiles) {
    $res = & $luac -p $f.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ('[FAIL] ' + $f.Name + ': ' + $res) -ForegroundColor Red
        $failures++
    }
}
if ($failures -gt 0) {
    Write-Host "[$failures arquivo(s) com erro de sintaxe!]" -ForegroundColor Red
    exit 1
}
Write-Host '[vp_lumberjack] Todos os arquivos Lua OK.' -ForegroundColor Green

$specFile = Join-Path $PSScriptRoot 'lumberjack_banking_spec.lua'
if (Test-Path $specFile) {
    Write-Host '[vp_lumberjack] Executando testes unitarios...'
    $result = & lua54 $specFile 2>&1
    Write-Host $result
    if ($LASTEXITCODE -ne 0) {
        Write-Host '[vp_lumberjack] TESTES FALHARAM' -ForegroundColor Red
        $failures++
    } else {
        Write-Host '[vp_lumberjack] Testes PASS' -ForegroundColor Green
    }
}

if ($failures -gt 0) { exit 1 }
Write-Host '[vp_lumberjack] Quality Gate: PASS' -ForegroundColor Green
