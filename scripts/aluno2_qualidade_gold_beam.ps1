# Estudante 2 - testes de qualidade, camada Gold, Parquet, Apache Beam e runtime distribuido.
# RF31 (qualidade), RF26 (Gold), RF24 (Parquet), RF25 (Beam DirectRunner + Spark), RF30 (dados mestres).
# Depende da Silver do Estudante 1.
# Uso:
#   .\scripts\aluno2_qualidade_gold_beam.ps1                  qualidade + Gold + mestres + Beam com Spark
#   .\scripts\aluno2_qualidade_gold_beam.ps1 -PularSpark      Beam so com DirectRunner (mantem a evidencia Spark anterior)
#   .\scripts\aluno2_qualidade_gold_beam.ps1 -Reset           limpa qualidade, gold e mestres antes de rodar
param([switch]$PularSpark, [switch]$Reset, [string]$ExecucaoId = 'carga-completa')

. "$PSScriptRoot\_comum.ps1"
$hop = "$PSScriptRoot\02_hop_pipeline.ps1"

Wait-Postgres
if ($Reset) {
    Invoke-Etapa 'reset' 'limpeza do Estudante 2' { Clear-Esquemas @('qualidade', 'gold', 'mestres') }
}
Invoke-Etapa 'pre' 'Silver do Estudante 1' {
    Assert-Tem 'silver.conteudo' 'Rode antes .\scripts\aluno1_hop_bronze_silver.ps1.'
    Assert-Tem 'silver.interacao' 'Rode antes .\scripts\aluno1_hop_bronze_silver.ps1.'
}

Invoke-Etapa 'RF31' 'testes de qualidade + gate critico' { & $hop -Etapa qualidade -ExecucaoId $ExecucaoId }
Invoke-Etapa 'RF26' 'publicacao da Gold' { & $hop -Etapa gold -ExecucaoId $ExecucaoId }
Invoke-Etapa 'RF26' 'contagens da Gold' {
    Invoke-Psql @"
SELECT 'gold.dim_conteudo' AS tabela, count(*) FROM gold.dim_conteudo
UNION ALL SELECT 'gold.fato_engajamento_dia', count(*) FROM gold.fato_engajamento_dia
UNION ALL SELECT 'gold.kpi_geral', count(*) FROM gold.kpi_geral
UNION ALL SELECT 'gold.kpi_evolucao_dia', count(*) FROM gold.kpi_evolucao_dia
UNION ALL SELECT 'gold.kpi_desempenho_categoria', count(*) FROM gold.kpi_desempenho_categoria
UNION ALL SELECT 'gold.kpi_engajamento_formato', count(*) FROM gold.kpi_engajamento_formato
UNION ALL SELECT 'gold.kpi_conversao_recomendacao', count(*) FROM gold.kpi_conversao_recomendacao;
"@ -Tabela
}
Invoke-Etapa 'RF30' 'dados mestres de conteudo' { & "$PSScriptRoot\04_dados_mestres.ps1" }
Invoke-Etapa 'RF24/RF25' 'Parquet particionado e Beam' {
    if ($PularSpark) { & "$PSScriptRoot\03_beam.ps1" -ExecucaoId $ExecucaoId -PularSpark }
    else { & "$PSScriptRoot\03_beam.ps1" -ExecucaoId $ExecucaoId }
}

Show-Resumo "Estudante 2 - execucao $ExecucaoId"
Write-Host "Evidencias: qualidade/resultados, dados/gold/parquet, beam/evidencias/medicoes.json"
Write-Host "Proximo: .\scripts\aluno3_governanca_superset.ps1 -ExecucaoId $ExecucaoId"
