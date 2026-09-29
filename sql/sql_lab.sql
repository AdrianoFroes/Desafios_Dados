-- RF17 — consultas do SQL Lab sobre a camada Gold.
-- Todas leem só gold.* e rodam com o usuário leitor_bi do Superset.
-- As consultas 1 e 2 estão salvas como datasets virtuais no Superset
-- (src/setup_superset_internal.py cria com o mesmo SQL). Documentação: sql/sql_lab.md.

-- Consulta 1 — dataset virtual vds_interacoes_dia_categoria
-- Usado pelo gráfico "Evolução Temporal de Interações" e pelo filtro de período.
-- Junção fato x dimensão; SUM(total_interacoes) por data bate com gold.kpi_evolucao_dia.
SELECT
    f.data,
    DATE_TRUNC('month', f.data)::date                        AS mes,
    d.categoria,
    d.tipo,
    SUM(f.total_interacoes)                                  AS total_interacoes,
    SUM(f.conclusoes)                                        AS conclusoes,
    SUM(f.inicios + f.visualizacoes)                         AS inicios_visualizacoes,
    CASE WHEN EXTRACT(ISODOW FROM f.data) IN (6, 7)
         THEN 'fim de semana' ELSE 'dia útil' END             AS tipo_dia
FROM gold.fato_engajamento_dia f
JOIN gold.dim_conteudo d ON d.conteudo_id = f.conteudo_id
GROUP BY f.data, d.categoria, d.tipo;

-- Consulta 2 — dataset virtual vds_conclusao_categoria_mes
-- Usado pelo filtro global de categoria. Taxa mensal e faixa de desempenho.
SELECT
    DATE_TRUNC('month', f.data)::date                        AS mes,
    d.categoria,
    SUM(f.conclusoes)                                        AS conclusoes,
    SUM(f.inicios + f.visualizacoes)                         AS inicios_visualizacoes,
    ROUND(100.0 * SUM(f.conclusoes)
          / NULLIF(SUM(f.inicios + f.visualizacoes), 0), 2)  AS taxa_conclusao_pct,
    CASE
        WHEN 100.0 * SUM(f.conclusoes) / NULLIF(SUM(f.inicios + f.visualizacoes), 0) >= 30 THEN 'alta'
        WHEN 100.0 * SUM(f.conclusoes) / NULLIF(SUM(f.inicios + f.visualizacoes), 0) >= 20 THEN 'média'
        ELSE 'baixa'
    END                                                      AS faixa_conclusao
FROM gold.fato_engajamento_dia f
JOIN gold.dim_conteudo d ON d.conteudo_id = f.conteudo_id
GROUP BY DATE_TRUNC('month', f.data), d.categoria;

-- Consulta 3 — condição do alerta de conversão (RF18)
-- Mesma expressão avaliada pelo alerta "Conversão de recomendação abaixo de 8%".
SELECT
    c.total_recomendacoes,
    c.recomendacoes_com_interacao,
    c.taxa_conversao_pct,
    g.usuarios_ativos,
    CASE WHEN c.taxa_conversao_pct < 8 THEN 'dispara alerta' ELSE 'dentro da meta' END AS situacao,
    TO_CHAR(c.lote_gerado_em, 'YYYY-MM-DD HH24:MI')          AS lote_recomendacao
FROM gold.kpi_conversao_recomendacao c
CROSS JOIN gold.kpi_geral g;

-- Consulta 4 — formatos por retenção (pergunta do storytelling, RF16)
SELECT
    formato,
    qtd_conteudos,
    total_interacoes,
    taxa_conclusao_pct,
    avaliacao_media,
    RANK() OVER (ORDER BY taxa_conclusao_pct DESC)           AS posicao_retencao
FROM gold.kpi_engajamento_formato
ORDER BY taxa_conclusao_pct DESC;
