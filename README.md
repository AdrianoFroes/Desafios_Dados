# 🎓 Plataforma Educacional — Pipeline de Dados

> Trabalho final da disciplina **Fundamentos de Dados para IA (FIC_DEV)** — Desafio Prático 2.
> Pipeline governado, escalável e seguro de conteúdos educacionais, evoluindo o Desafio 1 com camadas Bronze/Silver/Gold, processamento distribuído, governança e LGPD.

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Apache Hop](https://img.shields.io/badge/Apache%20Hop-2.19.0-1B5E20)](https://hop.apache.org/)
[![Apache Beam](https://img.shields.io/badge/Apache%20Beam-2.76.0-FF6D00)](https://beam.apache.org/)
[![Apache Superset](https://img.shields.io/badge/Apache%20Superset-3.1.1-20A7C9)](https://superset.apache.org/)
[![OpenMetadata](https://img.shields.io/badge/OpenMetadata-1.x-7C4DFF)](https://open-metadata.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-pgvector-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![MongoDB](https://img.shields.io/badge/MongoDB-NoSQL-47A248?logo=mongodb&logoColor=white)](https://www.mongodb.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)

## 👥 Equipe

| Integrante | Responsabilidade principal |
| :--- | :--- |
| **Adriano Froes** | LGPD, SQL Lab, Superset, OpenMetadata e storytelling |
| **Daniel Alves Santos** | Qualidade, camada Gold, dados mestres, Parquet e Apache Beam |
| **Felipe Ferreira Aguiar** | Apache Hop, camadas Bronze e Silver, workflows e tratamento de erros |


## 🎯 O que este projeto demonstra

- **Engenharia de Dados end-to-end**: ingestão (CSV/JSON), camadas Bronze → Silver → Gold, orquestração no Apache Hop
- **Processamento distribuído**: pipeline Apache Beam rodando com DirectRunner e Spark
- **Governança de dados**: catálogo, glossário, linhagem e classificação de PII no OpenMetadata
- **Qualidade de dados**: 5 testes automatizados com gate que bloqueia a Gold em caso de falha crítica
- **LGPD aplicada**: mascaramento, pseudonimização e hashing com salt — sem exposição de dados originais no dashboard
- **Analytics e storytelling**: SQL Lab, dashboards no Superset, filtros cruzados e alertas
- **DataOps**: parâmetros em `.env`/`config.yaml`, logs por execução e scripts reprodutíveis (Windows e Linux)

## 🏗️ Arquitetura (visão geral)

```
Fontes (CSV/JSON) ─► Apache Hop (Bronze ─► Silver ─► Quarentena)
                                   │
                                   ▼
                        Processamento (Parquet + Apache Beam)
                                   │
                                   ▼
                        Governança (OpenMetadata + Qualidade + LGPD)
                                   │
                                   ▼
                        Consumo (Gold ─► SQL Lab ─► Superset)
```

Controles transversais: configuração, metadados, qualidade, segurança, LGPD e reprocessamento.

## 🚀 Como rodar (resumo)

```bash
# 1. Subir os serviços (Postgres, MongoDB, Superset, OpenMetadata, Hop Web)
docker compose up -d

# 2. Rodar o pipeline do Desafio 1 (ingestão + KPIs + dashboard Superset)
python -m src.main

# 3. Rodar o pipeline completo do Desafio 2 (Bronze → Silver → Gold + Beam + Governança)
.\scripts\99_tudo.ps1 -DoZero          # Windows
pwsh ./scripts/99_tudo.ps1 -DoZero     # Linux
```

> Detalhes completos, portas, credenciais e execução modular na seção [Como rodar](#como-rodar) abaixo.

## 📚 Documentação técnica completa

---

# Plataforma Educacional — Pipeline de Dados

Trabalho da disciplina Fundamentos de Dados para IA (FIC_DEV).

## Equipe

* [Adriano Froes]
* [Daniel Alves Santos]
* [Felipe Ferreira Aguiar]

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

Os arquivos em `dados/brutos/` são fictícios e foram gerados para o desafio.

Os originais não são modificados em nenhuma etapa.

### Catálogo de conteúdos (`catalogo.csv`)

| Campo | Descrição |
|---|---|
| conteudo_id | Identificador do conteúdo. |
| titulo | Título do material. |
| tipo | Curso, vídeo, artigo ou podcast. |
| categoria | Área temática. |
| nivel | Básico, intermediário ou avançado. |
| carga_horaria_min | Duração estimada em minutos. |
| data_publicacao | Data de publicação. |
| descricao | Descrição textual. |
| autor | Responsável pelo conteúdo. |

### Interações de usuários (`interacoes.json`)

A fonte deverá conter, no mínimo, identificador do usuário, identificador do conteúdo, tipo de interação, data e hora, tempo consumido, percentual de conclusão e avaliação atribuída.

Tipos de interação sugeridos: visualização, início, conclusão, curtida, avaliação, compartilhamento.

### Comentários e avaliações (`comentarios.json`)

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

* Código organizado em diretórios;
* Arquivo README.md;
* Dependências registradas;
* Parâmetros de conexão separados do código;
* Registro das etapas executadas;
* Tratamento básico de erros;
* Instruções para reproduzir a solução;
* Controle de versão.

## Arquitetura mínima esperada

| Etapa | Tecnologia ou Resultado |
|---|---|
| Fontes | CSV, JSON |
| Ingestão | Leitura, validação, limpeza e registro de erros. |
| Dados Estruturados | PostgreSQL |
| Dados Semiestruturados | MongoDB |
| Dados Vetoriais | Pgvector |
| Processamento | Busca semântica e motor de recomendação. |
| Apresentação | Apache Superset conectado aos dados consolidados no PostgreSQL. |

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
# 1. criar ambiente virtual Python (3.10+)
python -m venv .venv

# Windows (PowerShell):
.\.venv\Scripts\Activate.ps1

# Windows (Prompt de Comando CMD):
.venv\Scripts\activate.bat

# Linux/Mac:
source .venv/bin/activate

# 2. instalar dependências
pip install -r requirements.txt

# 3. criar o arquivo .env a partir do modelo .env.example
# Windows (PowerShell):
Copy-Item .env.example .env
# Windows (CMD):
copy .env.example .env
# Linux / Mac:
cp .env.example .env

# Nota: As portas e credenciais padrão já vêm configuradas (PostgreSQL na porta 5433,
# e MongoDB na 27017). Se desejar alterar, basta editar as variáveis dentro do arquivo .env.

# 4. subir serviços (PostgreSQL com pgvector, MongoDB, Apache Superset e Apresentação Web)
docker compose up -d

# 5. rodar pipeline completo (processamento dos dados + geração automática dos gráficos no Superset)
python -m src.main

# 6. (Opcional) Gerar ou atualizar especificamente os gráficos e dashboard do Superset a qualquer momento:
python -m src.superset_dashboard
# Ou diretamente pelo container:
# docker exec desafio_superset python /app/setup_superset_internal.py
```

> **Geração e Sincronização dos Gráficos no Apache Superset (RF13):**
>
> * Ao rodar `python -m src.main`, o pipeline processa os dados, aplica todas as visões analíticas de KPIs no PostgreSQL e, na **Fase 3**, provisiona/atualiza automaticamente os **10 gráficos analíticos** e o **Dashboard ID 1** no Superset.
> * Se você subir o Docker do zero ou reiniciar os containers e desejar apenas sincronizar/recriar os gráficos e o dashboard sem reprocessar todos os dados, basta executar `python -m src.superset_dashboard`.
> * Após a execução, o Dashboard e os gráficos estarão disponíveis imediatamente tanto na interface do Superset quanto no **Slide 4 (Modo Kiosk ao vivo)** da apresentação web.

### Acesso aos Serviços e URLs do Projeto

* **Apresentação Executiva Web (Slides com Kiosk Superset)**: http://localhost:8085 (ou http://localhost:8085/slides.html)
  * **Slide 4**: exibe o Dashboard do Superset ao vivo em modo Kiosk (`/superset/dashboard/1/?standalone=2`), interativo, sem barras de navegação externas e com dados reais.
* **Apache Superset (RF13)**: http://localhost:8088
  * **Dashboard Direto (Kiosk Mode)**: http://localhost:8088/superset/dashboard/1/?standalone=2
  * **Login / Senha**: `admin` / `admin`
  * Dashboard consolidado em **Dashboards** → `Plataforma Educacional — KPIs e Recomendações`.
  * Backup estático em `dashboard/dashboard_plataforma_educacional.zip`.

### Comandos para Execução Modular (Opcional)

```bash
# Busca semântica vetorial (RF09)
python -m src.busca_semantica
python -m src.busca_semantica "Quero aprender os fundamentos de banco de dados para inteligência artificial."

# Motor de recomendações (RF10 / RF11)
python -m src.recomendacao
python -m src.recomendacao 1

# Recálculo de métricas e visões SQL de KPIs (RF12)
python -m src.kpis

# Provisionamento e sincronização do Dashboard e Gráficos no Apache Superset (RF13)
python -m src.superset_dashboard
```

A solução inclui uma apresentação interativa moderna com 9 slides executivos:

* **URL da Apresentação Web**: http://localhost:8085 (ou http://localhost:8085/slides.html)
* **Recursos**:
  * **Slide 4 com Superset em Kiosk Mode (`standalone=2`)**;
  * **Slides Analíticos de Aprofundamento (5 a 8)** com anotações e botões diretos para o Superset;
  * **Atalhos** para o Superset em nova aba (`/superset/dashboard/1/` e `/sqllab/`);
  * **Cronômetro Integrado** com meta de 10 minutos;
  * **Notas do Apresentador (`N`)** e **Cheat Sheet (`C`)**;
  * **Navegação** por setas, barra de espaço e tecla `F` (tela cheia).
* **Arquivo PowerPoint offline**: `apresentacao_plataforma_educacional.pptx`.

Se a senha do Postgres no `.env` mudar depois do primeiro `docker compose up`, é preciso recriar o volume (`docker compose down` + apagar `desafios_dados_postgres_data` + `up` de novo).

## Decisões que tomamos

* o enunciado pede que o sistema rode com `python -m src.main`, então organizamos os módulos como pacote único. As pastas `ingestao/` e `recomendacao/` sugeridas no PDF viram módulos (`src/ingestao.py`, `src/recomendacao.py`, `src/kpis.py`).
* **`config.yaml` + `.env`**: parâmetros versionáveis ficam no YAML, senhas ficam no `.env` (fora do Git).
* **Encoding UTF-8 explícito**: os dados têm acentuação em português (ex.: "Inteligência Artificial") e sem isso o Pandas quebra no Windows.
* **Validação antes de tratamento**: preferimos separar as etapas para deixar claro o que é regra de negócio (validação) e o que é padronização (tratamento). O diagnóstico do RF03 permanece sobre o bruto; o RF04 só padroniza a saída.
* **Tratamento sem imputação de conteúdo**: nulos de texto, data e avaliação não viram sentinela (`0`, `"nan"`, data de hoje). Categorias usam rótulo canônico *case-insensitive*, não `str.title()` (que quebraria `DevOps & Cloud` e `avaliação`). Detalhes em `documentacao/decisoes_tratamento.md`.
* **Modelo de embeddings (RF08)**: `all-MiniLM-L6-v2` do sentence-transformers. Escolhemos por ser leve (~90 MB), multilíngue o suficiente para o português e rápido em CPU. O texto embeddado é título + descrição; o vetor fica em `embedding_conteudo` associado ao `conteudo_id`. Recargas não geram de novo o mesmo par modelo/texto. Detalhes em `documentacao/modelo_embeddings.md`. **Se quiser usar um modelo maior, basta configurar o `EMBEDDING_MODEL` e `EMBEDDING_DIMENSIONS` no `.env`.**
* **Busca semântica (RF09)**: a frase em português é embeddada com o mesmo modelo e comparada aos vetores no pgvector (distância de cosseno). O `top_k` e as três consultas de demonstração ficam em `config.yaml`. Resultados no log e em `dados/processados/busca_semantica.json`. Detalhes em `documentacao/busca_semantica.md`.
* **Recomendação (RF10/RF11)**: pontuação `((Ivis + Icur) / 2) * 100 * Iconc`. Ivis e Icur vêm da similaridade de cosseno no pgvector (centroide do histórico de visualização e de curtidas/notas >= 4). Iconc remove concluídos. Positivo (>= 70) e Estável (entre 40 e 70) entram no ranking; Negativo é descartado. `top_n_por_usuario` está no YAML. O JSON vai para `dados/processados/recomendacoes.json`; o lote é gravado na tabela `recomendacao` (transação + upsert). Recargas inserem um novo `gerado_em`. Detalhes em `documentacao/recomendacao.md`.
* **PostgreSQL (RF06/RF12)**: o script `sql/criar_tabelas.sql` é a fonte da verdade do schema e `sql/criar_views_kpi.sql` cria as visões analíticas. A recarga usa upsert (`ON CONFLICT`), sem truncar. Só entram registros tratados que passam nas regras de integridade. Comentários ficam para o MongoDB (RF07); `recomendacao` é preenchida pelo RF11.
* **MongoDB (RF07)**: só comentários/avaliações (tags em array e texto livre). A recarga usa upsert na tripla `(usuario_id, conteudo_id, data)`. A `categoria` é copiada do catálogo na carga para o `$group` do RF07. Detalhes em `documentacao/escolha_mongodb.md`.
* **Apache Superset (RF13)**: orquestrado via container próprio com SQLite interno de metadados e conexão ao banco PostgreSQL do projeto. Provisionamento automático de views, datasets e dashboards via API/script Python.
* **Registro de Execução (RF14)**: log com cronometragem granular de cada etapa do pipeline gravado no resumo JSON e no arquivo de log.

## Desafio 2 — execução por aluno (Windows e Linux)

Os scripts ficam em `scripts/` e são PowerShell. No Linux eles rodam com o PowerShell 7 (`pwsh`), que é multiplataforma: os mesmos arquivos servem para os dois sistemas.

| Aluno | Responsabilidade | Script |
|---|---|---|
| Estudante 1 | Apache Hop, Bronze, Silver, quarentena, workflows (RF20–RF23) | `scripts/aluno1_hop_bronze_silver.ps1` |
| Estudante 2 | Qualidade, Gold, dados mestres, Parquet e Beam (RF24–RF26, RF30, RF31) | `scripts/aluno2_qualidade_gold_beam.ps1` |
| Estudante 3 | LGPD, SQL Lab, Superset, OpenMetadata (RF16–RF18, RF27–RF29, RF32, RF33) | `scripts/aluno3_governanca_superset.ps1` |

A ordem importa: o Estudante 2 lê a Silver do Estudante 1, e o Estudante 3 lê a Gold do Estudante 2.

### Pré-requisitos no Linux (Ubuntu/Debian)

```bash
# Docker Engine com o plugin compose (docker compose, não docker-compose)
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER      # sair e entrar de novo na sessão para valer

# PowerShell 7
sudo apt-get install -y wget apt-transport-https software-properties-common
source /etc/os-release
wget -q https://packages.microsoft.com/config/$ID/$VERSION_ID/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb
sudo apt-get update && sudo apt-get install -y powershell

# Python do projeto
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Os scripts detectam o sistema: usam `.venv/bin/python` no Linux e `.venv\Scripts\python.exe` no Windows.

### Primeira execução (cria o `.env`, sobe os containers e aplica os esquemas)

```powershell
# Windows (PowerShell)
.\scripts\99_tudo.ps1 -DoZero

# Linux
pwsh ./scripts/99_tudo.ps1 -DoZero
```

Opções do `99_tudo`: `-SemOpenMetadata` (não sobe o OpenMetadata), `-PularSpark` (Beam só com DirectRunner), `-ComFalhas` (roda as simulações de falha do Hop), `-AguardarAlerta` (espera a primeira avaliação do alerta do Superset).

### Rodar ou refazer a parte de um aluno

O `-Reset` limpa só as camadas daquele aluno e roda as etapas dele de novo.

| Aluno | Windows (PowerShell) | Linux |
|---|---|---|
| Estudante 1 | `.\scripts\aluno1_hop_bronze_silver.ps1 -Reset` | `pwsh ./scripts/aluno1_hop_bronze_silver.ps1 -Reset` |
| Estudante 2 | `.\scripts\aluno2_qualidade_gold_beam.ps1 -Reset` | `pwsh ./scripts/aluno2_qualidade_gold_beam.ps1 -Reset` |
| Estudante 3 | `.\scripts\aluno3_governanca_superset.ps1 -Reset` | `pwsh ./scripts/aluno3_governanca_superset.ps1 -Reset` |
| Todos, sem recriar o ambiente | `.\scripts\99_tudo.ps1` | `pwsh ./scripts/99_tudo.ps1` |

Outras opções úteis:

| O quê | Windows (PowerShell) | Linux |
|---|---|---|
| Estudante 1 do zero (inclui o Desafio 1) | `.\scripts\aluno1_hop_bronze_silver.ps1 -DoZero` | `pwsh ./scripts/aluno1_hop_bronze_silver.ps1 -DoZero` |
| Estudante 1 com simulações de falha | `.\scripts\aluno1_hop_bronze_silver.ps1 -Reset -ComFalhas` | `pwsh ./scripts/aluno1_hop_bronze_silver.ps1 -Reset -ComFalhas` |
| Estudante 2 sem Spark | `.\scripts\aluno2_qualidade_gold_beam.ps1 -Reset -PularSpark` | `pwsh ./scripts/aluno2_qualidade_gold_beam.ps1 -Reset -PularSpark` |
| Estudante 3 sem OpenMetadata | `.\scripts\aluno3_governanca_superset.ps1 -Reset -SemOpenMetadata` | `pwsh ./scripts/aluno3_governanca_superset.ps1 -Reset -SemOpenMetadata` |
| Demonstrar o disparo do alerta | `.\scripts\06_superset.ps1 -DemonstrarDisparo` | `pwsh ./scripts/06_superset.ps1 -DemonstrarDisparo` |

### Zerar o banco

| O quê | Windows (PowerShell) | Linux |
|---|---|---|
| Esvaziar todas as camadas (mantém `public.*` do Desafio 1) | `.\scripts\reset.ps1` | `pwsh ./scripts/reset.ps1` |
| Idem e recriar os metadados do Superset | `.\scripts\reset.ps1 -Superset` | `pwsh ./scripts/reset.ps1 -Superset` |
| Remover containers e volumes do projeto | `.\scripts\reset.ps1 -Tudo` | `pwsh ./scripts/reset.ps1 -Tudo` |
| Parar o OpenMetadata e apagar os dados dele | `.\scripts\01_openmetadata_up.ps1 -Parar -ApagarDados` | `pwsh ./scripts/01_openmetadata_up.ps1 -Parar -ApagarDados` |

### Agendamento do workflow

No Windows, `.\scripts\agendar_windows.ps1` cria a tarefa no Agendador de Tarefas. No Linux, use o cron (`crontab -e`), trocando o caminho pelo da sua cópia do projeto:

```
15 2 * * * cd /caminho/Desafios_Dados && pwsh ./scripts/02_hop_pipeline.ps1 -ExecucaoId agendado-$(date +\%Y\%m\%d) >> hop/evidencias/cron.log 2>&1
```

### Diferenças do Linux já tratadas nos scripts

* Os arquivos que o Hop grava em `dados/` pertencem ao usuário do container. Quando o reset não tem permissão para apagá-los, a remoção é feita por um container `alpine`.
* O cliente do Beam com Spark roda como root num container; no fim, os arquivos de `dados/gold` e `beam/evidencias` voltam para o seu usuário.
* `host.docker.internal` não existe por padrão no Linux; o job server do Spark e a ingestão do OpenMetadata recebem `host-gateway` para alcançar o Postgres.
* A porta do Postgres vem do `POSTGRES_PORT` no `.env` (padrão `5433`). Se ela estiver ocupada, troque no `.env` antes do primeiro `99_tudo`.

### Endereços

| Serviço | URL | Login |
|---|---|---|
| Apresentação | http://localhost:8085 | – |
| Superset (dashboard) | http://localhost:8088/superset/dashboard/plataforma-educacional-kpis/ | aberto para leitura; `admin` / `admin` para editar |
| Superset (SQL Lab e alertas) | http://localhost:8088/sqllab/ e http://localhost:8088/alert/list/ | `admin` / `admin` |
| Mailpit (e-mails do alerta) | http://localhost:8025 | – |
| Apache Hop Web | http://localhost:8086/ui | – |
| OpenMetadata | http://localhost:8585 | `admin` / `admin` |
| Airflow da ingestão do OpenMetadata | http://localhost:8090 | `admin` / `admin` |
| PostgreSQL do projeto | `localhost:${POSTGRES_PORT}` (banco `plataforma_educacional`) | usuário e senha do `.env` |

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

* A recomendação usa uma fórmula simples (média entre visualização e curtidas, filtrada por conclusão). Não é machine learning de verdade.
* O modelo de embeddings é pequeno, então buscas muito específicas podem trazer resultados apenas razoáveis.
* O Superset foi configurado localmente; em outra máquina vai precisar reconectar as fontes.
* Não há autenticação — é um projeto de estudo.
