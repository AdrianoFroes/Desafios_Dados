# Funções compartilhadas pelos scripts de execução. Carregar com:
#   . "$PSScriptRoot\_comum.ps1"

$ErrorActionPreference = 'Stop'
$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location $Raiz
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Read-DotEnv {
    $arquivo = Join-Path $Raiz '.env'
    if (-not (Test-Path $arquivo)) { throw ".env nao encontrado. Rode scripts\00_setup.ps1 primeiro." }
    $valores = @{}
    foreach ($linha in Get-Content $arquivo -Encoding utf8) {
        if ($linha -match '^\s*#' -or $linha -notmatch '=') { continue }
        $chave, $valor = $linha -split '=', 2
        $valores[$chave.Trim()] = $valor.Trim()
    }
    return $valores
}

$Unix = $IsLinux -or $IsMacOS
$Py = Join-Path $Raiz $(if ($Unix) { '.venv/bin/python' } else { '.venv/Scripts/python.exe' })
if (-not (Test-Path $Py)) { $Py = if ($Unix) { 'python3' } else { 'python' } }
$Temp = [System.IO.Path]::GetTempPath()

# No Linux os arquivos gravados pelo Hop em dados/ pertencem ao usuario do container;
# quando o Remove-Item nao tem permissao, a remocao e feita por um container.
function Remove-Gerado([string[]]$caminhos) {
    foreach ($c in $caminhos) {
        $itens = @(Get-Item $c -ErrorAction SilentlyContinue)
        if (-not $itens) { continue }
        try { $itens | Remove-Item -Recurse -Force -ErrorAction Stop }
        catch {
            $rel = $c -replace '\\', '/'
            Invoke-Docker run --rm -v "${Raiz}:/work" -w /work alpine sh -c "rm -rf $rel"
        }
    }
}

$Cfg = Read-DotEnv
$PgUser = if ($Cfg.POSTGRES_USER) { $Cfg.POSTGRES_USER } else { 'postgres' }
$PgDb = if ($Cfg.POSTGRES_DB) { $Cfg.POSTGRES_DB } else { 'plataforma_educacional' }

function Write-Etapa([string]$texto) {
    Write-Host ""
    Write-Host "==> $texto" -ForegroundColor Cyan
}

function Invoke-Docker {
    $ErrorActionPreference = 'Continue'
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "docker $($args -join ' ') falhou (codigo $LASTEXITCODE)" }
}

function Wait-Postgres {
    $ErrorActionPreference = 'Continue'
    for ($i = 1; $i -le 30; $i++) {
        docker exec desafio_postgres pg_isready -U $PgUser -d $PgDb *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    throw "PostgreSQL (desafio_postgres) nao respondeu."
}

# Copia o arquivo para o container antes de executar: pelo pipe do PowerShell a
# acentuação dos domínios ('Vídeo', 'Básico') chega corrompida.
function Invoke-PsqlArquivo([string]$arquivo, [hashtable]$variaveis = @{}) {
    $ErrorActionPreference = 'Continue'
    $nome = Split-Path $arquivo -Leaf
    Invoke-Docker cp $arquivo "desafio_postgres:/tmp/$nome"
    $argumentos = @('exec', '-e', 'PGOPTIONS=-c client_min_messages=warning', 'desafio_postgres', 'psql', '-U', $PgUser, '-d', $PgDb, '-v', 'ON_ERROR_STOP=1', '-q')
    foreach ($k in $variaveis.Keys) { $argumentos += @('-v', "$k=$($variaveis[$k])") }
    $argumentos += @('-f', "/tmp/$nome")
    & docker @argumentos
    $codigo = $LASTEXITCODE
    docker exec desafio_postgres rm -f "/tmp/$nome" *> $null
    if ($codigo -ne 0) { throw "psql falhou em $arquivo" }
}

function Invoke-Psql([string]$sql, [switch]$Tabela) {
    $ErrorActionPreference = 'Continue'
    $formato = if ($Tabela) { @() } else { @('-t', '-A') }
    $saida = & docker exec desafio_postgres psql -U $PgUser -d $PgDb -v ON_ERROR_STOP=1 @formato -c $sql
    if ($LASTEXITCODE -ne 0) { throw "psql falhou: $sql" }
    return $saida
}

function Invoke-Hop([string]$arquivo, [string]$execucaoId, [string]$log) {
    $ErrorActionPreference = 'Continue'
    $cmd = "cd /usr/local/tomcat/webapps/ROOT && HOP_CONFIG_FOLDER=/files/config ./hop-run.sh -e docker-env -r local -j desafio_dados_2 -s DB_USER=`$DB_USER,DB_PASSWORD=`$DB_PASSWORD -f /files/$arquivo -p EXECUCAO_ID=$execucaoId"
    $saida = & docker exec desafio_apache_hop sh -c $cmd 2>&1
    $codigo = $LASTEXITCODE
    if ($log) {
        New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
        $saida | Out-File -Encoding utf8 $log
    }
    $saida | Select-String -Pattern 'RESUMO|resultado=|ERROR|Erro|finished|Finished' | ForEach-Object { Write-Host $_.Line }
    return $codigo
}

$Etapas = [System.Collections.Generic.List[object]]::new()

function Invoke-Etapa([string]$rf, [string]$nome, [scriptblock]$bloco) {
    $t = Get-Date
    try {
        & $bloco
        $Etapas.Add([pscustomobject]@{ RF = $rf; Etapa = $nome; Resultado = 'ok'; Segundos = [int]((Get-Date) - $t).TotalSeconds })
    } catch {
        $Etapas.Add([pscustomobject]@{ RF = $rf; Etapa = $nome; Resultado = "falha: $($_.Exception.Message)"; Segundos = [int]((Get-Date) - $t).TotalSeconds })
        Show-Resumo 'interrompido'
        throw
    }
}

function Show-Resumo([string]$titulo) {
    Write-Host ""
    Write-Host "Resumo - $titulo" -ForegroundColor Green
    $Etapas | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}

function Clear-Esquemas([string[]]$esquemas) {
    $lista = ($esquemas | ForEach-Object { "'$_'" }) -join ','
    Invoke-Psql @"
DO `$`$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ($lista)
  LOOP
    EXECUTE format('TRUNCATE TABLE %I.%I RESTART IDENTITY CASCADE', r.schemaname, r.tablename);
  END LOOP;
END `$`$;
"@ | Out-Null
    Write-Host "  esquemas esvaziados: $($esquemas -join ', ')"
}

function Initialize-SupersetMeta {
    $existe = Invoke-Psql "SELECT 1 FROM pg_database WHERE datname = 'superset_meta';"
    if (-not $existe) { Invoke-Psql "CREATE DATABASE superset_meta;" | Out-Null }
}

# Apaga dashboards, graficos e alertas do Superset; scripts\06_superset.ps1 recria tudo.
function Reset-Superset {
    Invoke-Docker compose rm -sf superset superset_worker superset_beat
    Invoke-Psql "DROP DATABASE IF EXISTS superset_meta WITH (FORCE);" | Out-Null
    Initialize-SupersetMeta
    $volume = docker volume ls -q --filter label=com.docker.compose.volume=superset_home --filter "label=com.docker.compose.project=$((Split-Path $Raiz -Leaf).ToLower())"
    if ($volume) { Invoke-Docker volume rm $volume }
    Invoke-Docker compose up -d superset superset_worker superset_beat
}

function Assert-Tem([string]$tabela, [string]$mensagem) {
    $n = [int](Invoke-Psql "SELECT count(*) FROM $tabela;")
    if ($n -eq 0) { throw "$tabela vazia. $mensagem" }
    Write-Host "  ${tabela}: $n linhas"
}

function Wait-Http([string]$url, [int]$segundos = 300) {
    $limite = (Get-Date).AddSeconds($segundos)
    while ((Get-Date) -lt $limite) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -lt 500) { return $true }
        } catch { }
        Start-Sleep -Seconds 5
    }
    return $false
}
