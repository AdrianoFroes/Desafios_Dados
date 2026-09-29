# RF27 - sobe o OpenMetadata 1.3.1 (compose oficial: Postgres, Elasticsearch,
# migracao, servidor e ingestao/Airflow). Precisa de ~6 GB de RAM livres no Docker.
# Uso: .\scripts\01_openmetadata_up.ps1 [-Parar [-ApagarDados]]
#   -ApagarDados  junto com -Parar, remove tambem os volumes (catalogo zerado)
param([switch]$Parar, [switch]$ApagarDados)

. "$PSScriptRoot\_comum.ps1"

$compose = @('compose', '-p', 'openmetadata', '-f', 'docker-compose-openmetadata-oficial.yml', '--env-file', '.env')

if ($Parar) {
    Write-Etapa "Parando o OpenMetadata"
    if ($ApagarDados) { Invoke-Docker @compose down -v } else { Invoke-Docker @compose down }
    return
}

Write-Etapa "Subindo o OpenMetadata (primeira vez baixa ~3 GB de imagens)"
Invoke-Docker @compose up -d

Write-Etapa "Aguardando http://localhost:8585 (ate 10 min)"
if (-not (Wait-Http 'http://localhost:8585/api/v1/system/version' 600)) {
    Invoke-Docker @compose ps
    throw "OpenMetadata nao respondeu. Veja: docker logs openmetadata_server"
}
$versao = Invoke-RestMethod 'http://localhost:8585/api/v1/system/version'
Write-Host "OpenMetadata $($versao.version) no ar: http://localhost:8585 (login $($Cfg.OM_ADMIN_EMAIL))"
Write-Host "Airflow da ingestao: http://localhost:$(if ($Cfg.OM_AIRFLOW_PORT) { $Cfg.OM_AIRFLOW_PORT } else { 8090 })"
