# RF15 - prepara o ambiente: .env, containers e esquemas do banco.
# Uso: .\scripts\00_setup.ps1 [-ComDesafio1]
#   -ComDesafio1  roda tambem o pipeline Python do Desafio 1 (python -m src.main),
#                 que popula public.* (inclusive public.recomendacao usada pela Gold).
param([switch]$ComDesafio1)

$ErrorActionPreference = 'Stop'
$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location $Raiz

function Novo-Segredo([int]$tamanho = 32) {
    $chars = [char[]]'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $bytes = New-Object byte[] $tamanho
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

# 1. .env: cria a partir do .env.example e completa chaves que faltarem.
# Gravado em UTF-8 sem BOM: com BOM o docker compose ignora a primeira variavel.
$exemplo = Get-Content .env.example -Encoding utf8
$atual = if (Test-Path .env) { @(Get-Content .env -Encoding utf8) } else { Write-Host "Criando .env a partir de .env.example"; @() }
$atual = $atual | ForEach-Object { $_.TrimStart([char]0xFEFF) }
if (-not $atual) { $atual = $exemplo }
$chavesAtuais = $atual | Where-Object { $_ -match '^\s*[A-Z_]+=' } | ForEach-Object { ($_ -split '=', 2)[0].Trim() }
$novas = foreach ($linha in $exemplo) {
    if ($linha -match '^\s*([A-Z_]+)=' -and $chavesAtuais -notcontains $Matches[1]) { $linha }
}
if ($novas) {
    Write-Host "Acrescentando ao .env: $((($novas | ForEach-Object { ($_ -split '=')[0] }) -join ', '))"
    $atual = @($atual) + @($novas)
}
$conteudo = $atual | ForEach-Object {
    if ($_ -match '^([A-Z_]+)=__gerar__$') { "$($Matches[1])=$(Novo-Segredo)" } else { $_ }
}
[System.IO.File]::WriteAllLines((Join-Path $Raiz '.env'), [string[]]$conteudo, (New-Object System.Text.UTF8Encoding($false)))

. "$PSScriptRoot\_comum.ps1"

# 2. Containers do projeto
Write-Etapa "Subindo containers (docker compose up -d)"
Invoke-Docker compose up -d
Wait-Postgres
Initialize-SupersetMeta

# 3. Esquemas, na ordem de dependencia. Todos sao idempotentes.
Write-Etapa "Aplicando esquemas SQL"
$ordem = @(
    'sql/criar_tabelas.sql',            # Desafio 1 (public.*); embeddings sao criados por src/embeddings.py
    'sql/criar_views_kpi.sql',
    'sql/criar_kpis_extras.sql',
    'sql/criar_esquema_bronze.sql',     # RF20
    'sql/criar_esquema_silver.sql',     # RF21 + quarentena
    'sql/criar_esquema_auditoria.sql',  # RF22
    'sql/qualidade.sql',                # RF31
    'sql/camada_gold.sql',              # RF26
    'sql/reprocessar_quarentena.sql',   # RF23
    'sql/dados_mestres.sql',            # RF30
    'sql/lgpd.sql'                      # RF33
)
foreach ($arquivo in $ordem) {
    Write-Host "  $arquivo"
    Invoke-PsqlArquivo $arquivo
}

if ($ComDesafio1) {
    Write-Etapa "Pipeline do Desafio 1 (python -m src.main)"
    $ErrorActionPreference = 'Continue'
    & $Py -m src.main
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw "python -m src.main falhou" }
}

Write-Etapa "Setup concluido"
Write-Host "Postgres em localhost:$($Cfg.POSTGRES_PORT) | Hop Web http://localhost:8086 | Superset http://localhost:8088 | Mailpit http://localhost:8025"
