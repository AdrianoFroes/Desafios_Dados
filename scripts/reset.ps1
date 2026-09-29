# Limpa as camadas para recomecar do zero.
# Uso: .\scripts\reset.ps1 [-Superset] [-Tudo]
#   (sem opcao)  esvazia bronze, silver, quarentena, auditoria, qualidade, gold,
#                mestres e lgpd, e apaga dados/bronze, dados/silver e os JSON de quarentena.
#                Os dados do Desafio 1 (public.*) sao mantidos.
#   -Superset    recria tambem o banco superset_meta (dashboards e alertas sao
#                recriados pelo scripts\06_superset.ps1). Necessario se a
#                SUPERSET_SECRET_KEY mudar.
#   -Tudo        docker compose down -v: remove todos os volumes do projeto.
param([switch]$Superset, [switch]$Tudo)

. "$PSScriptRoot\_comum.ps1"

if ($Tudo) {
    Write-Etapa "Removendo containers e volumes do projeto"
    Invoke-Docker compose down -v
    return
}

Wait-Postgres
Write-Etapa "Esvaziando as camadas no PostgreSQL"
$sql = @"
DO `$`$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT schemaname, tablename FROM pg_tables
           WHERE schemaname IN ('bronze','silver','quarentena','auditoria','qualidade','gold','mestres','lgpd','lgpd_restrito')
  LOOP
    EXECUTE format('TRUNCATE TABLE %I.%I RESTART IDENTITY CASCADE', r.schemaname, r.tablename);
  END LOOP;
END `$`$;
"@
Invoke-Psql $sql | Out-Null

Write-Etapa "Apagando arquivos gerados"
foreach ($pasta in 'dados/bronze', 'dados/silver') {
    if (Test-Path $pasta) { Remove-Item -Recurse -Force $pasta }
}
Get-ChildItem dados/quarentena -Filter 'registros_quarentena_*.json' -ErrorAction SilentlyContinue | Remove-Item -Force

if ($Superset) {
    Write-Etapa "Recriando o volume de metadados do Superset"
    Reset-Superset
}

Write-Host "Reset concluido. Proximo passo: .\scripts\02_hop_pipeline.ps1"
