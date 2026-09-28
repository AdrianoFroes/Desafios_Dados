# Linhagem Manual — OpenMetadata

| Origem | Destino | Transformação | Ferramenta |
|---|---|---|---|
| silver.interacao | gold.fato_engajamento_dia | Agregação por conteúdo e dia | Apache Hop |
| silver.conteudo | gold.dim_conteudo | Deduplicação e padronização | Apache Hop |
| public.recomendacao | gold.kpi_conversao_recomendacao | Cálculo de conversão | Apache Hop |
| gold.fato_engajamento_dia | gold.kpi_desempenho_categoria | Agregação por categoria | Apache Beam |
