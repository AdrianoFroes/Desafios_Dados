# RF32 / RF33 - pseudonimizacao, hashing com salt, mascaramento e papeis de acesso.
# O salt (LGPD_SALT) e as senhas dos papeis vem do .env; nada e gravado no repositorio.
. "$PSScriptRoot\_comum.ps1"

foreach ($chave in 'LGPD_SALT', 'BI_PASSWORD', 'OM_CATALOGO_PASSWORD') {
    if (-not $Cfg[$chave]) { throw "$chave ausente no .env. Rode scripts\00_setup.ps1." }
}

Wait-Postgres
Write-Etapa "Aplicando sql/lgpd.sql e dados de consumo protegidos"
Invoke-PsqlArquivo 'sql/lgpd.sql'
Invoke-PsqlArquivo 'sql/dados_mestres.sql'

$tmp = Join-Path $env:TEMP "lgpd_atualizar.sql"
"CALL lgpd.atualizar(:'salt');" | Set-Content $tmp -Encoding ascii
try { Invoke-PsqlArquivo $tmp @{ salt = $Cfg.LGPD_SALT } } finally { Remove-Item $tmp -Force }

Write-Etapa "Papeis leitor_bi (Superset) e om_catalogo (OpenMetadata)"
Invoke-PsqlArquivo 'sql/papeis_acesso.sql' @{ bi_password = $Cfg.BI_PASSWORD; om_password = $Cfg.OM_CATALOGO_PASSWORD }

Write-Etapa "Evidencias"
Invoke-Psql "SELECT conteudo_id, autor_mascarado, left(autor_hash, 16) || '...' AS autor_hash FROM lgpd.conteudo_publico ORDER BY conteudo_id LIMIT 3;" -Tabela
Invoke-Psql "SELECT pseudo_id, conteudo_id, tipo_interacao, data FROM lgpd.vw_interacao_pseudonimizada LIMIT 3;" -Tabela
Invoke-Psql "SELECT * FROM lgpd.vw_verificacao;" -Tabela

$ErrorActionPreference = 'Continue'
Write-Host "Teste de acesso do leitor_bi a tabela de correspondencia (deve ser negado):"
docker exec -e "PGPASSWORD=$($Cfg.BI_PASSWORD)" desafio_postgres psql -h localhost -U leitor_bi -d $PgDb -c "SELECT * FROM lgpd_restrito.correspondencia_usuario LIMIT 1;" 2>&1 | Select-Object -First 2
Write-Host "Teste de acesso do leitor_bi a coluna autor da Gold (deve ser negado):"
docker exec -e "PGPASSWORD=$($Cfg.BI_PASSWORD)" desafio_postgres psql -h localhost -U leitor_bi -d $PgDb -c "SELECT autor FROM gold.dim_conteudo LIMIT 1;" 2>&1 | Select-Object -First 2
