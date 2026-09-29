# Estudante 3 - LGPD, SQL Lab, recursos avancados do Superset e OpenMetadata.
# RF32/RF33 (LGPD e papeis), RF17/RF18 (SQL Lab, datasets virtuais, filtros, alerta),
# RF27-RF29 (catalogo, glossario, classificacao, linhagem). Depende da Gold do Estudante 2.
# Uso:
#   .\scripts\aluno3_governanca_superset.ps1                     tudo, inclusive OpenMetadata
#   .\scripts\aluno3_governanca_superset.ps1 -SemOpenMetadata    pula o OpenMetadata (exige ~6 GB de RAM livre)
#   .\scripts\aluno3_governanca_superset.ps1 -AguardarAlerta     espera a 1a avaliacao do alerta (ate 6 min)
#   .\scripts\aluno3_governanca_superset.ps1 -Reset              limpa lgpd, recria o Superset e apaga os dados do OpenMetadata antes de rodar
param([switch]$SemOpenMetadata, [switch]$AguardarAlerta, [switch]$Reset, [string]$ExecucaoId = 'carga-completa')

. "$PSScriptRoot\_comum.ps1"

Wait-Postgres
if ($Reset) {
    Invoke-Etapa 'reset' 'limpeza do Estudante 3' {
        Clear-Esquemas @('lgpd', 'lgpd_restrito')
        Invoke-Psql "TRUNCATE auditoria.metadados RESTART IDENTITY;" | Out-Null
        Reset-Superset
        if (-not $SemOpenMetadata) { & "$PSScriptRoot\01_openmetadata_up.ps1" -Parar -ApagarDados }
    }
}
Invoke-Etapa 'pre' 'Gold do Estudante 2' {
    Assert-Tem 'gold.kpi_geral' 'Rode antes .\scripts\aluno2_qualidade_gold_beam.ps1.'
    Assert-Tem 'gold.fato_engajamento_dia' 'Rode antes .\scripts\aluno2_qualidade_gold_beam.ps1.'
}

if (-not $SemOpenMetadata) {
    Invoke-Etapa 'RF27' 'OpenMetadata no ar' { & "$PSScriptRoot\01_openmetadata_up.ps1" }
}
Invoke-Etapa 'RF32/RF33' 'LGPD (pseudonimo, hash com salt, mascara) e papeis' { & "$PSScriptRoot\05_lgpd.ps1" }
Invoke-Etapa 'RF17' 'consultas do SQL Lab (sql/sql_lab.sql)' { Invoke-PsqlArquivo 'sql/sql_lab.sql' }
Invoke-Etapa 'RF17/RF18' 'Superset (datasets, graficos, filtros, alerta)' {
    if ($AguardarAlerta) { & "$PSScriptRoot\06_superset.ps1" -AguardarAlerta }
    else { & "$PSScriptRoot\06_superset.ps1" }
}
Invoke-Etapa 'RF22' 'publicacao de metadados da execucao' {
    Invoke-Psql "CALL auditoria.publicar_metadados('$ExecucaoId');" | Out-Null
    Invoke-Psql "SELECT esquema, count(*) AS tabelas, sum(linhas) AS linhas FROM auditoria.metadados WHERE execucao_id = '$ExecucaoId' GROUP BY 1 ORDER BY 1;" -Tabela
}
if (-not $SemOpenMetadata) {
    Invoke-Etapa 'RF27-RF29' 'OpenMetadata (ingestao, glossario, tags, linhagem)' { & "$PSScriptRoot\07_openmetadata_catalogo.ps1" }
}

Show-Resumo "Estudante 3 - execucao $ExecucaoId"
Write-Host "Superset: http://localhost:8088 | OpenMetadata: http://localhost:8585 | Mailpit: http://localhost:8025"
