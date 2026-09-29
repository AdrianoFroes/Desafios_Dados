# Fluxo completo do Desafio 2: os scripts dos tres estudantes, na ordem de dependencia.
# Uso:
#   .\scripts\99_tudo.ps1                     roda sobre o ambiente atual
#   .\scripts\99_tudo.ps1 -DoZero             apaga todos os volumes (projeto e OpenMetadata) e recomeca
#   .\scripts\99_tudo.ps1 -SemOpenMetadata -PularSpark -ComFalhas -AguardarAlerta
param(
    [switch]$DoZero, [switch]$SemOpenMetadata, [switch]$PularSpark,
    [switch]$ComFalhas, [switch]$AguardarAlerta, [string]$ExecucaoId = 'carga-completa'
)

$ErrorActionPreference = 'Stop'
$inicio = Get-Date

if ($DoZero) {
    & "$PSScriptRoot\reset.ps1" -Tudo
    if (-not $SemOpenMetadata -and (Test-Path "$PSScriptRoot\..\.env")) {
        & "$PSScriptRoot\01_openmetadata_up.ps1" -Parar -ApagarDados
    }
}

$a1 = @{ ExecucaoId = $ExecucaoId; DoZero = $DoZero; ComFalhas = $ComFalhas }
if (-not $DoZero) { $a1.Reset = $true }
& "$PSScriptRoot\aluno1_hop_bronze_silver.ps1" @a1

& "$PSScriptRoot\aluno2_qualidade_gold_beam.ps1" -ExecucaoId $ExecucaoId -Reset -PularSpark:$PularSpark

& "$PSScriptRoot\aluno3_governanca_superset.ps1" -ExecucaoId $ExecucaoId -Reset:(-not $DoZero) `
    -SemOpenMetadata:$SemOpenMetadata -AguardarAlerta:$AguardarAlerta

Write-Host ""
Write-Host "Fluxo completo concluido em $([int]((Get-Date) - $inicio).TotalMinutes) min (execucao $ExecucaoId)." -ForegroundColor Green
