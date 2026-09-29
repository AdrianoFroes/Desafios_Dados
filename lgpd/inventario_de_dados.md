# Inventário de dados pessoais (RF32)

Todos os dados do projeto são fictícios, gerados para o desafio; nenhum dado pessoal real é usado. O inventário trata os campos como se fossem reais, para aplicar os controles da LGPD.

## 1. Campos com dado pessoal ou identificador

| Campo | Onde aparece | Classificação | Finalidade | Necessidade | Acesso | Retenção proposta | Proteção |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `autor` | `bronze.catalogo`, `silver.conteudo`, `gold.dim_conteudo` | Dado pessoal (nome de pessoa) | Crédito de autoria e deduplicação no cadastro mestre | Necessário na Silver para o match dos dados mestres; **não necessário** no dashboard | Equipe de dados (papel `postgres`); **negado** ao `leitor_bi` (GRANT por coluna na `gold.dim_conteudo`) | Enquanto o conteúdo estiver publicado | Mascaramento (`P*** C*** A*** S***`) e hash sha256 com salt em `lgpd.conteudo_publico` |
| `usuario_id` | `bronze.interacoes`, `bronze.comentarios`, `silver.interacao`, `silver.comentario`, `public.interacao`, `public.recomendacao` | Identificador indireto: associa ações a uma pessoa | Calcular usuários ativos, recomendação e conversão | Necessário para associar interações do mesmo usuário; **não necessário** identificado no consumo | Equipe de dados; o BI só vê o `pseudo_id` | 24 meses após a última interação | Pseudonimização (`pseudo_id` UUID) em `lgpd.vw_interacao_pseudonimizada` |
| `comentario` | `bronze.comentarios`, `silver.comentario`, MongoDB `comentarios` | Texto livre: pode conter dado pessoal digitado pelo usuário | Feedback sobre o conteúdo | Necessário para análise de qualidade; o texto integral não é necessário no dashboard | Equipe de dados; o BI vê só o texto truncado | 12 meses | Mascaramento por truncamento (20 caracteres) em `lgpd.vw_comentario_mascarado` |
| `tags` | `silver.comentario`, MongoDB | Não pessoal (vocabulário do conteúdo) | Classificação do comentário | Sim | Livre | Igual ao comentário | Nenhuma |
| `data_hora` da interação | `silver.interacao` | Não pessoal isoladamente; combinado com `usuario_id`, vira perfil de uso | Série temporal de engajamento | Sim, só agregado por dia na Gold | Livre na Gold (agregado) | 24 meses | Agregação por dia (`gold.kpi_evolucao_dia`) |

Nenhum campo é **dado pessoal sensível** no sentido do art. 5º, II, da LGPD (origem racial, saúde, religião, biometria etc.). O `comentario` é o único ponto de risco, porque é texto livre.

## 2. Minimização na Gold

A camada Gold, que o dashboard consome, não guarda `usuario_id` nem `comentario`:

| Tabela Gold | Dado pessoal? | Como foi minimizado |
| --- | --- | --- |
| `gold.fato_engajamento_dia` | Não | Agregado por conteúdo e dia |
| `gold.kpi_geral`, `gold.kpi_evolucao_dia` | Não | Só `COUNT(DISTINCT usuario_id)`, sem o id |
| `gold.kpi_desempenho_categoria`, `gold.kpi_engajamento_formato` | Não | Agregados por categoria e formato |
| `gold.kpi_conversao_recomendacao` | Não | Contagens do lote |
| `gold.dim_conteudo` | Sim (`autor`) | A coluna existe para a equipe de dados, mas o `leitor_bi` não tem `SELECT` nela |

## 3. Classificação no catálogo

`openmetadata/configurar_catalogo.py` cria a classificação **LGPD** no OpenMetadata e aplica as tags às colunas:

| Tag | Colunas |
| --- | --- |
| `LGPD.DadoPessoal` + `PersonalData.Personal` | `autor` em Bronze, Silver e Gold |
| `LGPD.IdentificadorIndireto` + `PII.Sensitive` | `usuario_id` em Bronze e Silver |
| `PII.Sensitive` | `comentario` em Bronze e Silver |
| `LGPD.Pseudonimizado` + `PII.NonSensitive` | `pseudo_id` em `lgpd.vw_interacao_pseudonimizada` |
| `LGPD.Mascarado` | `comentario_mascarado`, `autor_mascarado` |
| `LGPD.HashComSalt` | `autor_hash` |

## 4. Acesso por papel

| Papel | Usado por | Pode ler | Não pode ler |
| --- | --- | --- | --- |
| `postgres` | Hop, scripts de carga | Tudo | — |
| `leitor_bi` | Superset (dashboard e SQL Lab) | `gold` (sem `autor`), `mestres`, `lgpd` (views protegidas), `qualidade`, views agregadas `public.vw_kpi_*` | `bronze`, `silver`, `quarentena`, `lgpd_restrito`, `gold.dim_conteudo.autor`, views com `usuario_id`, `autor` ou `comentario` |
| `om_catalogo` | Ingestão do OpenMetadata | Estrutura e amostras de todas as camadas | `lgpd_restrito` |

A view `lgpd.vw_verificacao` conta quantas colunas `usuario_id`, `autor` ou `comentario` o `leitor_bi` consegue ler. Na execução `carga-completa` o resultado é **0**. A mesma verificação encontrou e fez corrigir a view `public.vw_kpi_analise_conteudos`, do Desafio 1, que expunha o `autor` e deixou de ser concedida ao BI.
