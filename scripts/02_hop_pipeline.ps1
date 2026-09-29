# RF20-RF23 - Apache Hop: workflow completo ou etapas isoladas.
# Uso:
#   .\scripts\02_hop_pipeline.ps1                       workflow orquestrador inteiro
#   .\scripts\02_hop_pipeline.ps1 -Etapa bronze         so os 3 pipelines Bronze
#   .\scripts\02_hop_pipeline.ps1 -Etapa silver         recarga da Silver (le o ultimo lote Bronze)
#   .\scripts\02_hop_pipeline.ps1 -Etapa qualidade      5 testes + gate critico
#   .\scripts\02_hop_pipeline.ps1 -Etapa gold           publica gold.* (recusa se o gate reprovou)
#   .\scripts\02_hop_pipeline.ps1 -Etapa reprocessar    reprocessa a quarentena das 3 fontes
#   .\scripts\02_hop_pipeline.ps1 -Etapa falha-arquivo  simula JSON corrompido
#   .\scripts\02_hop_pipeline.ps1 -Etapa falha-regra    simula nota 9 num comentario
#   .\scripts\02_hop_pipeline.ps1 -Etapa falha-conexao  derruba o Postgres durante o workflow
# -ExecucaoId define o identificador; sem ele o script gera exec-AAAAMMDD-HHMMSS.
param(
    [ValidateSet('tudo', 'bronze', 'silver', 'qualidade', 'gold', 'reprocessar', 'falha-arquivo', 'falha-regra', 'falha-conexao')]
    [string]$Etapa = 'tudo',
    [string]$ExecucaoId = ''
)

. "$PSScriptRoot\_comum.ps1"

if (-not $ExecucaoId) { $ExecucaoId = "exec-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
$Evid = 'hop/evidencias'

function Invoke-Pipelines([string[]]$pipelines) {
    foreach ($p in $pipelines) {
        Write-Host "  pipelines/$p.hpl"
        $codigo = Invoke-Hop "pipelines/$p.hpl" $ExecucaoId "$Evid/$ExecucaoId-$p.log"
        if ($codigo -ne 0) { throw "Pipeline $p falhou (log em $Evid/$ExecucaoId-$p.log)" }
    }
}

function Show-Auditoria {
    Invoke-Psql @"
SELECT etapa,
       to_char(min(instante) FILTER (WHERE evento='inicio'), 'HH24:MI:SS') AS inicio,
       to_char(max(instante) FILTER (WHERE evento='fim'), 'HH24:MI:SS') AS fim,
       round(extract(epoch FROM max(instante) FILTER (WHERE evento='fim') - min(instante) FILTER (WHERE evento='inicio'))::numeric, 2) AS segundos,
       max(resultado) FILTER (WHERE evento='fim') AS resultado
FROM auditoria.etapa WHERE execucao_id = '$ExecucaoId'
GROUP BY etapa ORDER BY min(instante);
"@ -Tabela
}

function Invoke-Silver {
    Invoke-Psql "TRUNCATE TABLE silver.comentario, silver.interacao, silver.conteudo RESTART IDENTITY;" | Out-Null
    Invoke-Pipelines @('silver_conteudo', 'silver_interacao', 'silver_comentario')
}

Wait-Postgres
Write-Etapa "Apache Hop - etapa '$Etapa' - execucao_id=$ExecucaoId"

switch ($Etapa) {
    'tudo' {
        $log = "$Evid/$ExecucaoId-orquestrador.log"
        $codigo = Invoke-Hop 'workflows/orquestrador.hwf' $ExecucaoId $log
        Show-Auditoria
        if ($codigo -ne 0) { throw "Workflow terminou em falha (log em $log)" }
        Write-Host "Log completo: $log"
    }
    'bronze' { Invoke-Pipelines @('bronze_catalogo', 'bronze_interacoes', 'bronze_comentarios') }
    'silver' { Invoke-Silver }
    'qualidade' {
        Invoke-Pipelines @('qualidade', 'qualidade_gate')
        Invoke-Psql "SELECT teste, severidade, valor, operador, limite, aprovado FROM qualidade.resultado WHERE execucao_id = '$ExecucaoId' ORDER BY teste;" -Tabela
    }
    'gold' { Invoke-Pipelines @('gold') }
    'reprocessar' {
        Invoke-Pipelines @('silver_reprocessar')
        Invoke-Psql "SELECT * FROM quarentena.reprocessar_pendentes('$ExecucaoId');" -Tabela
        Invoke-Psql "SELECT origem, status, count(*) FROM quarentena.registro GROUP BY 1, 2 ORDER BY 1, 2;" -Tabela
    }
    'falha-arquivo' {
        $corrompido = 'dados/brutos/_comentario_corrompido.json'
        Set-Content $corrompido '{"usuario_id": 1, "comentario": "isto nao fecha' -Encoding ascii
        try { Invoke-Pipelines @('falha_arquivo_json') } finally { Remove-Item $corrompido -Force }
        Get-ChildItem dados/quarentena -Filter "*$ExecucaoId*" | ForEach-Object { Write-Host "Quarentena de arquivo: $($_.FullName)" }
    }
    'falha-regra' {
        Invoke-Psql @"
INSERT INTO bronze.comentarios (usuario_id, conteudo_id, avaliacao, comentario, tags, data, origem, arquivo_origem, data_hora_ingestao, execucao_id)
SELECT '7777', '58', '9', 'nota fora da faixa (demonstracao)', '[]', '2026-09-01', 'comentarios', 'falha_regra_demo', now(),
       (SELECT execucao_id FROM bronze.comentarios ORDER BY data_hora_ingestao DESC LIMIT 1);
"@ | Out-Null
        try { Invoke-Silver }
        finally { Invoke-Psql "DELETE FROM bronze.comentarios WHERE arquivo_origem = 'falha_regra_demo';" | Out-Null }
        Invoke-Psql "SELECT registro_id, regra_violada, mensagem, execucao_id, status FROM quarentena.registro WHERE execucao_id = '$ExecucaoId' AND regra_violada = 'AVALIACAO_FORA_DA_FAIXA';" -Tabela
    }
    'falha-conexao' {
        $log = "$Evid/hop-cli-falha-conexao.log"
        Write-Host "Parando desafio_postgres para simular banco inacessivel..."
        Invoke-Docker stop desafio_postgres | Out-Null
        try { $codigo = Invoke-Hop 'workflows/orquestrador.hwf' $ExecucaoId $log }
        finally {
            Invoke-Docker start desafio_postgres | Out-Null
            Wait-Postgres
        }
        Write-Host "Codigo de saida do Hop: $codigo (esperado diferente de 0). Log: $log"
        if ($codigo -eq 0) { throw "O workflow deveria ter falhado sem banco." }
    }
}
