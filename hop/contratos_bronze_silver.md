# Contratos Bronze / Silver / Quarentena (RF20, RF21, RF23)

Documento de bloqueio da Etapa 2 (Estudante 1). Define os esquemas de entrada e saída das camadas Bronze e Silver **antes** de construir os pipelines no Apache Hop, para que o Estudante 2 (Gold/Parquet/Beam) e o Estudante 3 (OpenMetadata/LGPD) comecem em paralelo com dados fictícios de teste, sem esperar o pipeline real terminar.

Convenções usadas neste projeto (ver `hop/environments/docker-env.json` e `docker-compose.yml`):

| Variável         | Valor                                              | Uso                                                         |
| ---------------- | -------------------------------------------------- | ----------------------------------------------------------- |
| `DIR_BRUTOS`     | `/dados/brutos`                                    | fontes do Desafio 1 (não alterar)                           |
| `DIR_BRONZE`     | `/dados/bronze`                                    | saída em arquivo da camada Bronze                           |
| `DIR_SILVER`     | `/dados/silver`                                    | saída em arquivo da camada Silver                           |
| `DIR_QUARENTENA` | `/dados/quarentena`                                | saída em arquivo dos registros rejeitados                   |
| `pg_desafio`     | conexão RDBMS (`${DB_HOST}:${DB_PORT}/${DB_NAME}`) | destino em banco (RF20 exige ao menos 1 banco como destino) |

No PostgreSQL, Bronze e Silver ficam em **schemas próprios**, sem tocar nas tabelas `public.*` do Desafio 1 (que devem continuar íntegras para comparação/reprocessamento, conforme seção 1 do enunciado):

- `bronze.*` — cópia auditável, sem transformação destrutiva.
- `silver.*` — dados padronizados e validados.
- `quarentena.*` — registros rejeitados de qualquer fonte.

Cada pipeline grava nos dois destinos (arquivo **e** schema) para dar evidência em `dados/*` (RF34) e ao mesmo tempo cumprir "banco de dados como destino" (RF20).

---

## 1. Schema Bronze por fonte

Regra geral: **mesmas colunas da origem, mesmos tipos brutos (sem cast, sem canonicalização), mais as colunas de auditoria.** Nenhuma linha é descartada aqui — validação e quarentena só existem a partir do Silver (RF21/RF23).

Colunas de auditoria, iguais nas três tabelas/arquivos:

| Coluna               | Tipo                              | Descrição                                                       |
| -------------------- | --------------------------------- | --------------------------------------------------------------- |
| `origem`             | string                            | nome da fonte: `catalogo`, `interacoes` ou `comentarios`        |
| `arquivo_origem`     | string                            | nome do arquivo lido, ex. `catalogo.csv`                        |
| `data_hora_ingestao` | timestamp (`YYYY-MM-DDTHH:MM:SS`) | momento em que o Hop leu a linha                                |
| `execucao_id`        | string (UUID)                     | identificador da execução do workflow (RF22), correlaciona logs |

### 1.1 `bronze.catalogo` / `dados/bronze/catalogo_bronze.csv`

| Coluna                             | Tipo bruto                       | Origem         |
| ---------------------------------- | -------------------------------- | -------------- |
| `conteudo_id`                      | string/number (como veio do CSV) | `catalogo.csv` |
| `titulo`                           | string                           | idem           |
| `tipo`                             | string                           | idem           |
| `categoria`                        | string                           | idem           |
| `nivel`                            | string                           | idem           |
| `carga_horaria_min`                | string/number                    | idem           |
| `data_publicacao`                  | string                           | idem           |
| `descricao`                        | string                           | idem           |
| `autor`                            | string                           | idem           |
| _(+ 4 colunas de auditoria acima)_ |                                  |                |

### 1.2 `bronze.interacoes` / `dados/bronze/interacoes_bronze.json`

| Coluna                       | Tipo bruto         | Origem            |
| ---------------------------- | ------------------ | ----------------- |
| `usuario_id`                 | string/number      | `interacoes.json` |
| `conteudo_id`                | string/number      | idem              |
| `tipo_interacao`             | string             | idem              |
| `data_hora`                  | string             | idem              |
| `tempo_consumido`            | string/number      | idem              |
| `percentual_conclusao`       | string/number      | idem              |
| `avaliacao_atribuida`        | string/number/null | idem              |
| _(+ 4 colunas de auditoria)_ |                    |                   |

### 1.3 `bronze.comentarios` / `dados/bronze/comentarios_bronze.json`

| Coluna                       | Tipo bruto                  | Origem             |
| ---------------------------- | --------------------------- | ------------------ |
| `usuario_id`                 | string/number               | `comentarios.json` |
| `conteudo_id`                | string/number               | idem               |
| `avaliacao`                  | string/number/null          | idem               |
| `comentario`                 | string                      | idem               |
| `tags`                       | array de string (como veio) | idem               |
| `data`                       | string                      | idem               |
| _(+ 4 colunas de auditoria)_ |                             |                    |

---

## 2. Schema Silver por entidade

Reaproveita, sem reinventar, as regras já documentadas no Desafio 1 em `documentacao/decisoes_tratamento.md`. A diferença para o RF04 original: aqui, quem **não passa** na regra vai para a quarentena (seção 3) em vez de só ser registrado no log.

Todas as tabelas Silver preservam as colunas de auditoria vindas do Bronze (`origem`, `arquivo_origem`, `data_hora_ingestao`, `execucao_id`) e adicionam:

| Coluna                   | Tipo      | Descrição                         |
| ------------------------ | --------- | --------------------------------- |
| `data_hora_padronizacao` | timestamp | quando a linha passou pelo Silver |

### 2.1 `silver.conteudo` / `dados/silver/conteudo_silver.csv`

Chave de negócio: `conteudo_id` (dedupe: mantém a 1ª ocorrência).

| Coluna              | Tipo padronizado                                  | Regra (origem: decisoes_tratamento.md)        |
| ------------------- | ------------------------------------------------- | --------------------------------------------- |
| `conteudo_id`       | integer                                           | obrigatório, único                            |
| `titulo`            | string                                            | `strip()`, sem imputação                      |
| `tipo`              | enum `Artigo` \| `Curso` \| `Podcast` \| `Vídeo`  | canonicalização case-insensitive              |
| `categoria`         | enum (8 categorias oficiais, ver §3 do documento) | canonicalização case-insensitive              |
| `nivel`             | enum `Básico` \| `Intermediário` \| `Avançado`    | canonicalização case-insensitive              |
| `carga_horaria_min` | integer anulável, `>= 0`                          | ilegível → nulo, nunca `0`                    |
| `data_publicacao`   | date `YYYY-MM-DD`                                 | `to_datetime(errors=coerce)`, ilegível → nulo |
| `descricao`         | text anulável                                     | `strip()`, sem imputação                      |
| `autor`             | string anulável                                   | `strip()`, sem imputação                      |

### 2.2 `silver.interacao` / `dados/silver/interacao_silver.json`

Chave de negócio: `(usuario_id, conteudo_id, data_hora)` (dedupe: mantém a 1ª ocorrência).

| Coluna                 | Tipo padronizado                                                                                   | Regra                                                           |
| ---------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `usuario_id`           | integer                                                                                            | deve existir referência válida (ver RF21 "validar referências") |
| `conteudo_id`          | integer                                                                                            | idem — sem correspondência em `silver.conteudo` → quarentena    |
| `tipo_interacao`       | enum minúsculo (`avaliação`, `compartilhamento`, `conclusão`, `curtida`, `início`, `visualização`) | canonicalização                                                 |
| `data_hora`            | timestamp `YYYY-MM-DDTHH:MM:SS`                                                                    | ilegível → nulo/quarentena                                      |
| `tempo_consumido`      | integer anulável, `>= 0`                                                                           | ilegível → nulo                                                 |
| `percentual_conclusao` | numeric(5,2), faixa `0–100`                                                                        | arredondado a 2 casas                                           |
| `avaliacao_atribuida`  | integer anulável, `1–5`                                                                            | nulo é valor de negócio válido (nem toda interação tem nota)    |

### 2.3 `silver.comentario` / `dados/silver/comentario_silver.json`

Chave de negócio: `(usuario_id, conteudo_id, data)` (dedupe: mantém a 1ª ocorrência).

| Coluna        | Tipo padronizado                                             | Regra                                                |
| ------------- | ------------------------------------------------------------ | ---------------------------------------------------- |
| `usuario_id`  | integer                                                      | referência válida                                    |
| `conteudo_id` | integer                                                      | referência válida — sem correspondência → quarentena |
| `avaliacao`   | integer anulável, `1–5`                                      | ilegível/fora da faixa → quarentena                  |
| `comentario`  | text anulável                                                | `strip()`                                            |
| `tags`        | array de string, minúsculas, sem duplicata, ordem alfabética | idem ao RF04; não-lista → `[]`                       |
| `data`        | date `YYYY-MM-DD`                                            | ilegível → quarentena                                |

---

## 3. Schema da quarentena (RF23)

Tabela/arquivo único para as três fontes: `quarentena.registro` / `dados/quarentena/registros_quarentena.json`.

Campos exigidos literalmente pelo RF23:

| Coluna          | Tipo                            | Descrição                                                                                                                                        |
| --------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `registro_id`   | string                          | identificador do registro rejeitado (chave de negócio serializada, ex. `interacoes:usuario_id=104,conteudo_id=28,data_hora=2026-08-20T10:00:00`) |
| `origem`        | string                          | `catalogo` \| `interacoes` \| `comentarios`                                                                                                      |
| `regra_violada` | string                          | código da regra, ex. `TIPO_FORA_DO_DOMINIO`, `DATA_INVALIDA`, `REFERENCIA_INEXISTENTE`, `DUPLICADO`, `AVALIACAO_FORA_DA_FAIXA`                   |
| `data`          | timestamp `YYYY-MM-DDTHH:MM:SS` | momento em que a violação foi detectada (não confundir com a data de negócio do registro)                                                        |
| `mensagem`      | string                          | descrição legível do problema, para quem for corrigir e reprocessar                                                                              |

Campos adicionais (não exigidos pelo texto literal do RF23, mas necessários para o fluxo de reprocessamento também pedido no RF23):

| Coluna             | Tipo                                              | Descrição                                                                                                     |
| ------------------ | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `execucao_id`      | string                                            | correlaciona com o log do workflow (RF22)                                                                     |
| `payload_original` | JSON/text                                         | o registro Bronze completo, para permitir corrigir e reenviar ao Silver sem precisar buscar de volta na fonte |
| `status`           | enum `pendente` \| `reprocessado` \| `descartado` | controla o ciclo de correção                                                                                  |

Regra de fluxo: uma linha rejeitada grava aqui **e não interrompe** o restante da carga do Silver (RF23: "sem encerrar todo o processamento"). Só falha crítica (ex. banco de destino fora do ar) deve interromper o workflow inteiro (RF22).

---
