-- Consulta 1: Desempenho por Categoria
SELECT categoria, tipo, taxa_conclusao_pct, avaliacao_media
FROM gold.kpi_desempenho_categoria
ORDER BY taxa_conclusao_pct DESC;

-- Consulta 2: Evolução Temporal
SELECT data, total_interacoes, usuarios_ativos, conclusoes
FROM gold.kpi_evolucao_dia
WHERE data >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6 months'
ORDER BY data;

-- Consulta 3: Conversão de Recomendação
SELECT total_recomendacoes, recomendacoes_com_interacao, taxa_conversao_pct
FROM gold.kpi_conversao_recomendacao;
