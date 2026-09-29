# Estudante 1 - Apache Hop, camadas Bronze e Silver, workflows e tratamento de erros.
# RF20 (Bronze), RF21 (Silver), RF22 (orquestracao e auditoria), RF23 (quarentena e falhas).
# Uso:
#   .\scripts\aluno1_hop_bronze_silver.ps1 -DoZero           setup + reset (inclusive Superset) + Bronze + Silver
#   .\scripts\aluno1_hop_bronze_silver.ps1 -Reset            limpa bronze, silver, quarentena e auditoria antes de rodar
#   .\scripts\aluno1_hop_bronze_silver.ps1                   Bronze + Silver + reprocessamento da quarentena
#   .\scripts\aluno1_hop_bronze_silver.ps1 -ComFalhas        inclui as 3 demonstracoes de falha
#   .\scripts\aluno1_hop_bronze_silver.ps1 -Orquestrador     roda o workflow orquestrador.hwf inteiro
#                                                            (Bronze > Silver > Qualidade > Gold > Metadados)
# -ExecucaoId deve ser o mesmo usado pelos scripts dos alunos 2 e 3 (padrao carga-completa).
param([switch]$DoZero, [switch]$Reset, [switch]$ComFalhas, [switch]$Orquestrador, [string]$ExecucaoId = 'carga-completa')

if ($DoZero) { & "$PSScriptRoot\00_setup.ps1" -ComDesafio1 }
. "$PSScriptRoot\_comum.ps1"
$hop = "$PSScriptRoot\02_hop_pipeline.ps1"

if ($DoZero) {
    Invoke-Etapa 'RF15' 'reset das camadas e do Superset' { & "$PSScriptRoot\reset.ps1" -Superset }
}

Wait-Postgres
if ($Reset -and -not $DoZero) {
    Invoke-Etapa 'reset' 'limpeza do Estudante 1' {
        Clear-Esquemas @('bronze', 'silver', 'quarentena', 'auditoria')
        Remove-Gerado @('dados/bronze', 'dados/silver', 'dados/quarentena/registros_quarentena_*.json')
    }
}
Invoke-Etapa 'pre' 'Desafio 1 carregado (public.recomendacao)' {
    Assert-Tem 'public.recomendacao' 'Rode com -DoZero ou python -m src.main.'
}

if ($Orquestrador) {
    Invoke-Etapa 'RF22' 'workflow orquestrador (todas as etapas)' { & $hop -Etapa tudo -ExecucaoId $ExecucaoId }
} else {
    Invoke-Etapa 'RF20' 'Bronze (catalogo, interacoes, comentarios)' { & $hop -Etapa bronze -ExecucaoId $ExecucaoId }
    Invoke-Etapa 'RF21' 'Silver (le o ultimo lote Bronze)' { & $hop -Etapa silver -ExecucaoId $ExecucaoId }
    Invoke-Etapa 'RF23' 'reprocessamento da quarentena' { & $hop -Etapa reprocessar -ExecucaoId $ExecucaoId }
}

if ($ComFalhas) {
    Invoke-Etapa 'RF23' 'falha de arquivo (JSON corrompido)' { & $hop -Etapa falha-arquivo -ExecucaoId "$ExecucaoId-falha-arquivo" }
    Invoke-Etapa 'RF23' 'falha de regra (nota 9)' { & $hop -Etapa falha-regra -ExecucaoId "$ExecucaoId-falha-regra" }
    Invoke-Etapa 'RF22' 'falha de conexao (Postgres parado)' { & $hop -Etapa falha-conexao -ExecucaoId "$ExecucaoId-falha-conexao" }
    # falha-regra recarrega a Silver sem o registro invalido; o resultado final e o mesmo lote.
}

Invoke-Etapa 'RF21' 'contagens Bronze, Silver e quarentena' {
    Invoke-Psql @"
SELECT 'bronze.catalogo' AS tabela, count(*) FROM bronze.catalogo
UNION ALL SELECT 'bronze.interacoes', count(*) FROM bronze.interacoes
UNION ALL SELECT 'bronze.comentarios', count(*) FROM bronze.comentarios
UNION ALL SELECT 'silver.conteudo', count(*) FROM silver.conteudo
UNION ALL SELECT 'silver.interacao', count(*) FROM silver.interacao
UNION ALL SELECT 'silver.comentario', count(*) FROM silver.comentario
UNION ALL SELECT 'quarentena.registro', count(*) FROM quarentena.registro;
"@ -Tabela
}

Show-Resumo "Estudante 1 - execucao $ExecucaoId"
Write-Host "Logs do Hop: hop/evidencias | Hop Web: http://localhost:8086"
Write-Host "Proximo: .\scripts\aluno2_qualidade_gold_beam.ps1 -ExecucaoId $ExecucaoId"
