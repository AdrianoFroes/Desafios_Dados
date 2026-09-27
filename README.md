# Plataforma Educacional — Pipeline de Dados

Trabalho da disciplina Fundamentos de Dados para IA (FIC_DEV).

## Equipe

- [Adriano Froes]
- [Daniel Alves Santos]
- [Felipe Ferreira Aguiar]

## Situação Problema

Uma plataforma fictícia disponibiliza cursos, vídeos, artigos, podcasts e outros materiais educacionais. Atualmente, os dados estão distribuídos em diferentes arquivos e formatos, dificultando a identificação dos conteúdos mais procurados, a análise do comportamento dos usuários, a avaliação da qualidade dos materiais, a recomendação de conteúdos relacionados e a construção de indicadores para apoiar decisões.

A instituição deseja organizar esses dados, produzir recomendações simples e acompanhar os principais resultados em um dashboard.

> Produto esperado: pipeline reproduzível que integre ingestão, PostgreSQL, MongoDB, armazenamento vetorial, recomendações e um dashboard no Apache Superset.

## Problema Proposto

Cada equipe deverá desenvolver uma solução de dados capaz de:

1. Ingerir dados provenientes de diferentes fontes e formatos;
2. Armazenar dados estruturados em um banco relacional;
3. Armazenar dados semiestruturados em um banco NoSQL;
4. Representar descrições textuais por meio de embeddings;
5. Recuperar conteúdos semanticamente semelhantes;
6. Gerar recomendações simples;
7. Disponibilizar métricas e KPIs em um dashboard no Apache Superset.

> A solução deverá formar um fluxo integrado e reproduzível, desde a leitura dos dados de origem até sua apresentação no dashboard.

## Sobre os dados

Os arquivos em `dados/brutos/` são fictícios e foram gerados para o desafio:

Os originais não são modificados em nenhuma etapa.

### Catálogo de conteúdos (`catalogo.csv`):

| Campo             | Descrição                          |
| ----------------- | ---------------------------------- |
| conteudo_id       | Identificador do conteúdo.         |
| titulo            | Título do material.                |
| tipo              | Curso, vídeo, artigo ou podcast.   |
| categoria         | Área temática.                     |
| nivel             | Básico, intermediário ou avançado. |
| carga_horaria_min | Duração estimada em minutos.       |
| data_publicacao   | Data de publicação.                |
| descricao         | Descrição textual.                 |
| autor             | Responsável pelo conteúdo.         |

### Interações de usuários (`interacoes.json`):

A fonte deverá conter, no mínimo, identificador do usuário, identificador do conteúdo, tipo de interação, data e hora, tempo consumido, percentual de conclusão e avaliação atribuída.

Tipos de interação sugeridos:

- visualização;
- início;
- conclusão;
- curtida;
- avaliação;
- compartilhamento.

### Comentários e avaliações (`comentarios.json`):

Exemplo de documento:

```json
{
  "usuario_id": 104,
  "conteudo_id": 28,
  "avaliacao": 5,
  "comentario": "Conteúdo introdutório, claro e objetivo.",
  "tags": ["didático", "iniciante", "python"],
  "data": "2026-08-20"
}
```

## Práticas de DataOps

A solução deverá apresentar práticas básicas de DataOps:

- Código organizado em diretórios;
- Arquivo README.md;
- Dependências registradas;
- Parâmetros de conexão separados do código;
- Registro das etapas executadas;
- Tratamento básico de erros;
- Instruções para reproduzir a solução;
- Controle de versão.

## Arquitetura mínima esperada

| Etapa                  | Tecnologia ou Resultado                                         |
| ---------------------- | --------------------------------------------------------------- |
| Fontes                 | CSV, JSON                                                       |
| Ingestão               | Leitura, validação, limpeza e registro de erros.                |
| Dados Estruturados     | PostgreSQL                                                      |
| Dados Semiestruturados | MongoDB                                                         |
| Dados Vetoriais        | Pgvector                                                        |
| Processamento          | Busca semântica e motor de recomendação.                        |
| Apresentação           | Apache Superset conectado aos dados consolidados no PostgreSQL. |

## Estrutura

```
Desafios_Dados/
  src/          código Python do pipeline
  dados/        brutos (originais) e processados (tratados)
  sql/          scripts SQL (criação de tabelas, consultas)
  mongodb/      consultas NoSQL
  dashboard/    prints do Superset
  documentacao/ decisoes_tratamento.md, escolha_mongodb.md, modelo_embeddings.md, busca_semantica.md, recomendacao.md, kpis.md, uso_da_ia.md
  README.md
  config.yaml   parâmetros
  .env          credenciais (não versionado)
```

## Como rodar

Pré-requisitos: Python 3.10+, Docker, Git.

```bash
# 1. criar ambiente
python -m venv .venv

# Windows:
.\venv\Scripts\Activate.ps1

# Linux/Mac:
source venv/bin/activate

# 2. instalar dependências
pip install -r requirements.txt

# 3. criar .env na raiz (POSTGRES_* e MONGO_*)

# 4. subir serviços (PostgreSQL com pgvector, MongoDB, Apache Superset e Apresentação)
docker compose up -d

> **Automação do Apache Superset:** O container `desafio_superset` inicializa o banco de metadados, cria o usuário administrador (`admin`/`admin`), sincroniza permissões com perfil público e provisiona os datasets e o dashboard automaticamente via `docker-compose.yml`.

# 5. rodar pipeline completo (ingestão, validação, bancos, embeddings, recomendações e KPIs)
python -m src.main
```

O schema PostgreSQL é criado automaticamente na carga (`sql/criar_tabelas.sql`), juntamente com as visões analíticas de métricas e KPIs (`sql/criar_views_kpi.sql`). Consultas manuais de verificação: `sql/consultas.sql`. A coleção MongoDB (índices e validador) é aplicada na carga; consultas manuais: `mongodb/consultas.js`.

Depois dos embeddings, o pipeline demonstra a busca semântica (RF09), gera e persiste as recomendações (RF10/RF11) e consolida os KPIs (RF12). Para repetir só essas etapas:

```bash
python -m src.busca_semantica
python -m src.busca_semantica "Quero aprender os fundamentos de banco de dados para inteligência artificial."

python -m src.recomendacao
python -m src.recomendacao 1

python -m src.kpis
```

### Acesso ao Apache Superset (RF13)

- **URL**: [http://localhost:8088](http://localhost:8088)
- **Usuário**: `admin`
- **Senha**: `admin`
- O dashboard consolidado está acessível em **Dashboards** -> `Plataforma Educacional — KPIs e Recomendações`.
- Arquivo exportado do dashboard disponível em `dashboard/dashboard_plataforma_educacional.zip`.

### Apresentação Executiva de Slides (Docker / Web)

A solução inclui uma apresentação interativa moderna com 9 slides executivos, estruturada especificamente para a banca avaliadora com ênfase na análise de dados, KPIs (RF12) e Dashboard no Apache Superset (RF13):

- **URL da Apresentação Web**: [http://localhost:8085](http://localhost:8085) (ou [http://localhost:8085/slides.html](http://localhost:8085/slides.html))
- **Recursos da Apresentação**:
  - **Slide 4 com Superset em Kiosk Mode (`standalone=2`)**: O painel executivo do Apache Superset é renderizado diretamente dentro do slide de forma interativa (com filtros por categoria e nível funcionais), além de um alternador instantâneo para a versão de backup de alta fidelidade;
  - **Slides Analíticos de Aprofundamento (Slides 5 a 8)**: Gráficos de alta legibilidade em tema escuro com anotações analíticas e botões diretos `⚡ Abrir Slice no Superset (Kiosk)` para exploração granular;
  - **Acesso Rápido ao Superset**: Atalhos diretos para abrir o Apache Superset em nova aba na porta `8088` (`/superset/dashboard/1/` e `/sqllab/`);
  - **Cronômetro Integrado**: Temporizador com meta de 10 minutos e alerta visual para controle de tempo do pitch;
  - **Notas do Apresentador (`N`)**: Roteiro de fala detalhado com números e insights para cada slide;
  - **Cheat Sheet de Defesa Técnica (`C`)**: Guia com respostas prontas e justificativas arquiteturais para as perguntas da banca;
  - **Navegação**: Setas do teclado `←` / `→`, barra de espaço, e tecla `F` (tela cheia).
- **Arquivo PowerPoint Offline**: Apresentação completa e diagramada em formato `.pptx` disponível na raiz do repositório: `apresentacao_plataforma_educacional.pptx`.

Se a senha do Postgres no `.env` mudar depois do primeiro `docker compose up`, é preciso recriar o volume (`docker compose down` + apagar `desafios_dados_postgres_data` + `up` de novo).

## Decisões que tomamos

- o enunciado pede que o sistema rode com `python -m src.main`, então organizamos os módulos como pacote único.
  As pastas `ingestao/` e `recomendacao/` sugeridas no PDF viram módulos (`src/ingestao.py`, `src/recomendacao.py`, `src/kpis.py`).
- **`config.yaml` + `.env`**: parâmetros versionáveis ficam no YAML, senhas ficam no `.env` (fora do Git).
- **Encoding UTF-8 explícito**: os dados têm acentuação em português (ex.: "Inteligência Artificial") e sem isso o Pandas quebra no Windows.
- **Validação antes de tratamento**: preferimos separar as etapas para deixar claro o que é regra de negócio (validação) e o que é padronização
  (tratamento). O diagnóstico do RF03 permanece sobre o bruto; o RF04 só padroniza a saída.
- **Tratamento sem imputação de conteúdo**: nulos de texto, data e avaliação não viram sentinela (`0`, `"nan"`, data de hoje). Categorias usam rótulo canônico *case-insensitive*, não `str.title()` (que quebraria `DevOps & Cloud` e `avaliação`). Detalhes em `documentacao/decisoes_tratamento.md`.
- **Modelo de embeddings (RF08)**: `all-MiniLM-L6-v2` do sentence-transformers. Escolhemos por ser leve (~90 MB), multilíngue o suficiente para o português e rápido em CPU. O texto embeddado é título + descrição; o vetor fica em `embedding_conteudo` associado ao `conteudo_id`. Recargas não geram de novo o mesmo par modelo/texto. Detalhes em `documentacao/modelo_embeddings.md`. **Se quiser usar um modelo maior, basta configurar o EMBEDDING_MODEL e EMBEDDING_DIMENSIONS no .env.**
- **Busca semântica (RF09)**: a frase em português é embeddada com o mesmo modelo e comparada aos vetores no pgvector (distância de cosseno). O `top_k` e as três consultas de demonstração ficam em `config.yaml`. Resultados no log e em `dados/processados/busca_semantica.json`. Detalhes em `documentacao/busca_semantica.md`.
- **Recomendação (RF10/RF11)**: pontuação `((Ivis + Icur) / 2) * 100 * Iconc`. Ivis e Icur vêm da similaridade de cosseno no pgvector (centroide do histórico de visualização e de curtidas/notas >= 4). Iconc remove concluídos. Positivo (>= 70) e Estável (entre 40 e 70) entram no ranking; Negativo é descartado. `top_n_por_usuario` está no YAML. O JSON vai para `dados/processados/recomendacoes.json`; o lote é gravado na tabela `recomendacao` (transação + upsert). Recargas inserem um novo `gerado_em`. Detalhes em `documentacao/recomendacao.md`.
- **PostgreSQL (RF06/RF12)**: o script `sql/criar_tabelas.sql` é a fonte da verdade do schema e `sql/criar_views_kpi.sql` cria as visões analíticas. A recarga usa upsert (`ON CONFLICT`), sem truncar. Só entram registros tratados que passam nas regras de integridade. Comentários ficam para o MongoDB (RF07); `recomendacao` é preenchida pelo RF11.
- **MongoDB (RF07)**: só comentários/avaliações (tags em array e texto livre). A recarga usa upsert na tripla `(usuario_id, conteudo_id, data)`. A `categoria` é copiada do catálogo na carga para o `$group` do RF07. Detalhes em `documentacao/escolha_mongodb.md`.
- **Apache Superset (RF13)**: orquestrado via container próprio com SQLite interno de metadados e conexão ao banco PostgreSQL do projeto. Provisionamento automático de views, datasets e dashboards via API/script Python.
- **Registro de Execução (RF14)**: log com cronometragem granular de cada etapa do pipeline gravado no resumo JSON e no arquivo de log.

## Desafio 2 — qualidade, Gold, Parquet e Beam

A Silver continua sendo produzida pelo Apache Hop. Antes do primeiro workflow com qualidade e Gold, copie os scripts para o container e aplique uma vez. No Windows, não encaminhe o arquivo pelo pipe do PowerShell: a acentuação dos domínios (`Vídeo`, `Básico`) chega corrompida.

```bash
docker cp sql/qualidade.sql desafio_postgres:/tmp/qualidade.sql
docker cp sql/camada_gold.sql desafio_postgres:/tmp/camada_gold.sql
docker exec desafio_postgres psql -U postgres -d plataforma_educacional -v ON_ERROR_STOP=1 -f /tmp/qualidade.sql
docker exec desafio_postgres psql -U postgres -d plataforma_educacional -v ON_ERROR_STOP=1 -f /tmp/camada_gold.sql
```

O workflow `hop/workflows/orquestrador.hwf` chama, nesta ordem, `qualidade.hpl`, `qualidade_gate.hpl` e `gold.hpl`. O gate é um pipeline separado para o resultado do teste já estar gravado quando um teste crítico interrompe a Gold.

As tabelas de consumo ficam em `gold.*`. O contrato de grão, chave e fórmula está no cabeçalho de `sql/camada_gold.sql`. As regras dos cinco testes estão em `qualidade/regras.md`.

Parquet e Beam leem `silver.interacao` e gravam em `dados/gold/` e `beam/evidencias/medicoes.json`:

```bash
python beam/pipeline.py --execucao-id gold-local-1
```

O DirectRunner roda na máquina local com `python beam/pipeline.py --execucao-id gold-local-1 --pular-spark`. No Apache Beam 2.76 essa opção executa o pipeline no Prism, o motor local usado pelo DirectRunner quando a transformação é compatível.

O Spark não fecha com o cliente no Windows e o job server no Docker: o executor tenta falar com o worker Python em `localhost` e cai no container, não na máquina. O cliente precisa compartilhar a rede do job server:

```bash
docker run -d --name beam_spark_job -p 8099:8099 -p 8098:8098 -p 8097:8097 apache/beam_spark3_job_server:2.76.0 --job-host=0.0.0.0 --spark-master-url=local[2]

docker run --rm --network container:beam_spark_job -v "%CD%:/work" -w /work -e POSTGRES_HOST=host.docker.internal -e POSTGRES_PORT=5434 python:3.12-slim bash -c "pip install -q 'apache-beam==2.76.0' pyarrow psycopg2-binary python-dotenv pyyaml && python beam/pipeline.py --execucao-id gold-local-1 --job-endpoint localhost:8099 --artifact-endpoint localhost:8098"
```

A porta `5434` é a deste ambiente, porque `5433` já estava ocupada. No `docker-compose.yml` do projeto a porta publicada continua `5433`.

Versões usadas nesta etapa: Apache Hop 2.19.0, Apache Beam 2.76.0, job server Spark `apache/beam_spark3_job_server:2.76.0` (Spark local[2]), Apache Superset 3.1.1. A agregação é a mesma da `gold.fato_engajamento_dia`: conteúdo e dia, com conclusão definida por tipo `conclusão` ou percentual >= 100. O Parquet de entrada é particionado por ano e mês. Nesta base o Parquet ficou menor que o JSON, mas a leitura do JSON foi mais rápida: o recorte tem cerca de mil linhas, pouco para o formato colunar compensar.

## Status da Solução

Todos os requisitos obrigatórios do edital (**RF01 a RF14**) foram integralmente implementados, testados e documentados.

## Limitações

- A recomendação usa uma fórmula simples (média entre visualização e curtidas, filtrada por conclusão). Não é machine learning de verdade.
- O modelo de embeddings é pequeno, então buscas muito específicas podem trazer resultados apenas razoáveis.
- O Superset foi configurado localmente; em outra máquina vai precisar reconectar as fontes.
- Não há autenticação — é um projeto de estudo.

## Limitações conhecidas

- O motor de recomendação usa uma fórmula simples (média de visualização e curtidas, filtrada por conclusão). Não é aprendizado de máquina de verdade.
- O modelo de embeddings é pequeno, então buscas muito específicas podem trazer resultados apenas razoáveis.
- O Superset foi configurado localmente; em outra máquina vai precisar reconectar as fontes.
- Não temos autenticação em nada — é um projeto de estudo.
