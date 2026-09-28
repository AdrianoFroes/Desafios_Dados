# Quarentena, reprocessamento e simulação de falhas (RF23, evidência do RF34)

Este documento registra como a camada Silver trata registros rejeitados e como três falhas foram simuladas de propósito. Tudo abaixo foi executado de verdade contra o Apache Hop 2.19.0 e o PostgreSQL do `docker-compose.yml`; os números são os medidos, não estimados.

## 1. O que acontece com um registro rejeitado

Cada pipeline Silver (`silver_conteudo`, `silver_interacao`, `silver_comentario`) separa as linhas em duas saídas dentro do mesmo fluxo:

- **Aprovada** — vai para `silver.*` e para `dados/silver/`.
- **Rejeitada** — vai para `quarentena.registro` e para `dados/quarentena/`, com os campos que o RF23 exige literalmente: `registro_id`, `origem`, `regra_violada`, `data` e `mensagem`. O schema adiciona `execucao_id`, `payload_original` e `status` para permitir corrigir e reenviar sem voltar à fonte (ver `hop/contratos_bronze_silver.md`, seção 3, e `sql/criar_esquema_silver.sql`).

Uma linha rejeitada **não interrompe** o restante da carga. A execução de `silver_comentario` com um comentário de nota 9 no meio de 3397 linhas terminou normalmente: 1000 aprovados no Silver e 2397 na quarentena, sem erro de pipeline. Só uma falha crítica (banco inacessível) derruba o processamento — ver a simulação 3.

## 2. Reprocessamento

O pipeline `hop/pipelines/silver_reprocessar.hpl` lê a quarentena com `status = 'pendente'`, reaplica as mesmas regras do Silver e faz um de dois caminhos:

- **Corrigido** — entra em `silver.conteudo` e todas as ocorrências daquela chave de negócio passam a `status = 'reprocessado'`.
- **Ainda inválido** — ganha um novo registro `pendente` na quarentena, com o `execucao_id` desta execução, e o anterior permanece `pendente` para nova correção.

O `payload_original` guarda a linha completa, então a correção é feita nele (por exemplo ajustando `tipo` de um valor fora do domínio para `Curso`) e o pipeline relê esse JSON. A deduplicação usa a versão mais recente de cada `registro_id`, para uma chave corrigida e reprocessada várias vezes não gerar duplicata.

Execução de verificação (`EXECUCAO_ID=reprocessamento-1`), com três registros pendentes de catálogo:

| Registro | Correção aplicada | Resultado |
| --- | --- | --- |
| `catalogo:conteudo_id=9001` | `tipo` ajustado para `Curso` | inserido em `silver.conteudo`, status `reprocessado` |
| `catalogo:conteudo_id=9002` | `nivel` ajustado para `Básico` | inserido em `silver.conteudo`, status `reprocessado` |
| `catalogo:conteudo_id=9003` | nenhuma (`categoria` continua fora do domínio) | novo registro `pendente` com `execucao_id=reprocessamento-1` |

O pipeline hoje reprocessa a fonte `catalogo`. Interações e comentários seguem o mesmo desenho, acrescentando a validação de referência contra `silver.conteudo`.

## 3. Simulação das três falhas

### 3.1 Falha de regra — nota fora de 1 a 5

Inseri em `bronze.comentarios` um comentário com `avaliacao = 9` (`usuario_id=7777`, `conteudo_id=58`) e executei `silver_comentario` com `EXECUCAO_ID=falha-regra-1`.

Resultado: o pipeline concluiu sem erro. O comentário foi para a quarentena e os demais seguiram.

```
registro_id:    comentarios:usuario_id=7777,conteudo_id=58,data=2026-09-01
regra_violada:  AVALIACAO_FORA_DA_FAIXA
mensagem:       avaliacao ilegivel ou fora da faixa 1-5
execucao_id:    falha-regra-1
status:         pendente
```

Na mesma execução, 2396 duplicatas também foram para a quarentena (`DUPLICADO`) e 1000 comentários válidos foram para `silver.comentario`. A linha inválida não parou nada.

### 3.2 Falha de arquivo — JSON corrompido

Criei `dados/brutos/_comentario_corrompido.json` com um objeto JSON que não fecha (`{"usuario_id": 1, "comentario": "isto nao fecha`). O pipeline `hop/pipelines/falha_arquivo_json.hpl` lê esse arquivo e tem uma saída de erro configurada no transform de leitura: quando o parse falha, o erro é desviado para a quarentena em vez de encerrar o pipeline.

Execução com `EXECUCAO_ID=falha-arquivo-1`:

```
Ler JSON.0 - ERROR: Error parsing file [/dados/brutos/_comentario_corrompido.json]!
falha_arquivo_json - Pipeline duration : 0.594 seconds
(execução concluída, sem interrupção)
```

Registro gravado em `quarentena.registro`:

```
registro_id:    arquivo:/dados/brutos/_comentario_corrompido.json
origem:         comentarios
regra_violada:  ARQUIVO_CORROMPIDO
mensagem:       Error parsing file [/dados/brutos/_comentario_corrompido.json]!
execucao_id:    falha-arquivo-1
```

Com o arquivo válido (`comentarios.json`) o mesmo pipeline leu as 1000 linhas normalmente, o que confirma que a saída de erro só dispara diante de falha real de leitura.

### 3.3 Falha de conexão — porta errada do Postgres

Apontei a conexão do pipeline para `postgres:9999` (a porta real no compose é 5432) e executei. Desta vez o processamento **parou**, que é o comportamento esperado para falha crítica:

```
Ler Bronze e aplicar regras.0 - ERROR: An error occurred while connecting to the database, processing will be stopped:
Ler Bronze e aplicar regras.0 - Connection to postgres:9999 refused. Check that the hostname and port are correct
                                 and that the postmaster is accepting TCP/IP connections.
Gravar Silver.0 - ERROR: An error occurred initializing this transform
```

Nenhuma linha foi gravada. A conexão e o pipeline usados nessa simulação foram temporários e removidos depois; a conexão de verdade continua sendo `pg_desafio` (`hop/metadata/rdbms/pg_desafio.json`), que lê host e porta das variáveis de ambiente.

## 4. Como reproduzir

Com os containers no ar (`docker compose up -d`):

```bash
# falha de regra: o comentario de nota 9 ja esta em bronze.comentarios
docker exec desafio_apache_hop sh -c "cd /usr/local/tomcat/webapps/ROOT && \
  HOP_CONFIG_FOLDER=/files/config ./hop-run.sh -e docker-env -r local \
  -j desafio_dados_2 -f /files/pipelines/silver_comentario.hpl -p EXECUCAO_ID=falha-regra-1"

# falha de arquivo
docker exec desafio_apache_hop sh -c "cd /usr/local/tomcat/webapps/ROOT && \
  HOP_CONFIG_FOLDER=/files/config ./hop-run.sh -e docker-env -r local \
  -j desafio_dados_2 -f /files/pipelines/falha_arquivo_json.hpl -p EXECUCAO_ID=falha-arquivo-1"

# reprocessamento (depois de corrigir o payload_original dos registros pendentes)
docker exec desafio_apache_hop sh -c "cd /usr/local/tomcat/webapps/ROOT && \
  HOP_CONFIG_FOLDER=/files/config ./hop-run.sh -e docker-env -r local \
  -j desafio_dados_2 -f /files/pipelines/silver_reprocessar.hpl -p EXECUCAO_ID=reprocessamento-1"
```

Os três pipelines também abrem e rodam pela interface web do Hop em `http://localhost:8086/ui`.
