# RF30 - consolida a entidade mestre CONTEUDO (sql/dados_mestres.sql).
. "$PSScriptRoot\_comum.ps1"

Wait-Postgres
Write-Etapa "Dados mestres de conteudo"
Invoke-PsqlArquivo 'sql/dados_mestres.sql'
Invoke-Psql "CALL mestres.consolidar();" | Out-Null

Invoke-Psql @"
SELECT (SELECT count(*) FROM silver.conteudo) AS registros_origem,
       (SELECT count(*) FROM mestres.conteudo_mestre) AS mestres,
       (SELECT count(*) FROM mestres.conteudo_mestre WHERE qtd_registros > 1) AS grupos_com_conflito;
"@ -Tabela

Write-Host "Exemplo de dois registros conflitantes e o valor que sobreviveu:"
Invoke-Psql @"
SELECT mestre_id, conteudo_id, sobrevivente, nivel_origem, nivel_mestre, carga_origem, carga_mestre, data_origem, data_mestre
FROM mestres.vw_conflitos
WHERE mestre_id = (SELECT mestre_id FROM mestres.vw_conflitos
                   WHERE nivel_origem IS DISTINCT FROM nivel_mestre OR carga_origem IS DISTINCT FROM carga_mestre
                   LIMIT 1);
"@ -Tabela
