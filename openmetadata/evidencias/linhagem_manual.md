# Linhagem registrada manualmente (RF29)

Relações que o OpenMetadata não extrai sozinho: arquivos locais não são catalogados, e as transformações rodam em pipelines do Hop, em funções SQL e no Beam, que o conector do PostgreSQL não interpreta.

A visão completa, com as arestas registradas pela API, está em `documentacao/linhagem.md`.

## 1. Arquivos e Parquet (fora do catálogo)

| Origem | Destino | Transformação | Ferramenta |
| --- | --- | --- | --- |
| `dados/brutos/catalogo.csv` | `bronze.catalogo` | Leitura como texto + colunas de auditoria (`origem`, `arquivo_origem`, `data_hora_ingestao`, `execucao_id`) | Hop `bronze_catalogo.hpl` |
| `dados/brutos/interacoes.json` | `bronze.interacoes` | Idem | Hop `bronze_interacoes.hpl` |
| `dados/brutos/comentarios.json` | `bronze.comentarios` | Idem | Hop `bronze_comentarios.hpl` |
| `silver.interacao` | `dados/gold/parquet/interacao/ano=AAAA/mes=MM` | Exportação particionada por ano e mês | `beam/pipeline.py` |
| Parquet de interação | `dados/gold/parquet/engajamento_dia/direct` e `/spark` | Agregação por conteúdo e dia, nos dois runtimes | Apache Beam (DirectRunner e Spark) |

## 2. Registradas no OpenMetadata pela API (`openmetadata/configurar_catalogo.py`)

| Origem | Destino | Transformação | Ferramenta |
| --- | --- | --- | --- |
| `bronze.catalogo` | `silver.conteudo` | Padroniza tipo, categoria e nível; deduplica por `conteudo_id` | Hop `silver_conteudo` |
| `bronze.interacoes` | `silver.interacao` | Tipagem, faixa do percentual, referência ao conteúdo, deduplicação | Hop `silver_interacao` |
| `bronze.comentarios` | `silver.comentario` | Tags normalizadas, nota de 1 a 5, referência ao conteúdo | Hop `silver_comentario` |
| `bronze.*` | `quarentena.registro` | Registros rejeitados pelas regras da Silver | Hop `silver_*` |
| `silver.conteudo` | `gold.dim_conteudo` | Cópia 1:1 por `conteudo_id` | `gold.publicar` (chamada pelo Hop `gold.hpl`) |
| `silver.interacao` | `gold.fato_engajamento_dia` | `GROUP BY conteudo_id, dia` | `gold.publicar` |
| `silver.interacao` | `gold.kpi_geral`, `gold.kpi_evolucao_dia` | Usuários ativos (linhagem de coluna), conclusões | `gold.publicar` |
| `silver.interacao` + `silver.conteudo` | `gold.kpi_desempenho_categoria`, `gold.kpi_engajamento_formato` | Agregação por categoria/tipo e por formato | `gold.publicar` |
| `public.recomendacao` + `silver.interacao` | `gold.kpi_conversao_recomendacao` | Conversão do último lote | `gold.publicar` |
| `gold.kpi_conversao_recomendacao` | `gold.kpi_geral` | `taxa_conversao_recomendacao_pct` | `gold.publicar` |
| `silver.conteudo` | `mestres.conteudo_mestre`, `mestres.correspondencia_conteudo` | Match e sobrevivência | `mestres.consolidar` |
| `silver.interacao`, `silver.comentario` | `lgpd.vw_interacao_pseudonimizada`, `lgpd.vw_comentario_mascarado` | Pseudônimo e máscara | views de `sql/lgpd.sql` |
| `gold.dim_conteudo` | `lgpd.conteudo_publico` | Máscara e hash com salt do autor | `lgpd.atualizar` |
| `gold.fato_engajamento_dia`, `gold.dim_conteudo` | dataset virtual `vds_interacoes_dia_categoria` | Consulta 1 do SQL Lab | Superset |
| `vds_interacoes_dia_categoria`, `gold.kpi_geral`, `gold.kpi_desempenho_categoria`, `gold.kpi_evolucao_dia` | Dashboard Plataforma Educacional | Gráficos do dashboard | Superset |

Total: 28 arestas na execução `carga-completa`.
