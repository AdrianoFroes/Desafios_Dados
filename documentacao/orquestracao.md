# Workflow orquestrador (RF22)

O arquivo `hop/workflows/orquestrador.hwf` executa a carga na ordem Bronze, Silver, Qualidade, Gold e publicação de metadados. Qualidade e Gold chamam `qualidade.aplicar`, `qualidade.bloquear_se_critico` e `gold.publicar`. A publicação de metadados (Estudante 3) ainda é uma ação de log, marcada como `placeholder`.

## Ordem e o que cada etapa faz

| Ordem | Etapa | O que roda hoje |
| --- | --- | --- |
| 1 | Bronze | `bronze_catalogo`, `bronze_interacoes`, `bronze_comentarios` |
| 2 | Silver | `silver_conteudo`, depois `silver_interacao` e `silver_comentario` (o catálogo precisa existir antes, por causa da chave estrangeira) |
| 3 | Qualidade | `qualidade.hpl` grava os testes; `qualidade_gate.hpl` bloqueia a Gold se um teste crítico reprovar |
| 4 | Gold | `gold.hpl` publica `gold.*` a partir da Silver |
| 5 | Metadados | ação `Metadados (placeholder)` |

Antes da primeira etapa, `orquestrador_inicio` define o `execucao_id`: usa o valor recebido pelo parâmetro `EXECUCAO_ID` ou, se vier vazio, gera um UUID. Esse mesmo valor é passado a todos os pipelines e gravado em `auditoria.etapa`.

No fim, `orquestrador_resumo` lê a auditoria e a quarentena e registra o resultado.

## Falha crítica e falha de linha

Uma etapa seguinte só começa se a anterior terminou sem erro. O hop de sucesso (`evaluation=Y`) liga Bronze a Silver, Silver a Qualidade, e assim por diante. O hop de falha de cada pipeline de Bronze ou Silver grava `resultado=falha` em `auditoria.etapa`, escreve `FIM workflow resultado=falha` e aborta. Qualidade, Gold e Metadados não chegam a rodar.

Uma linha rejeitada pela regra de negócio não derruba o pipeline Silver: ela vai para `quarentena.registro` e o pipeline termina com sucesso. O workflow segue. Se essa execução deixou registro `pendente` na quarentena, o resultado final é **sucesso com ressalvas**.

## Resultado final

| Resultado | Quando | Código de saída do `hop-run` |
| --- | --- | --- |
| `sucesso` | Todas as etapas reais ok e nenhuma linha nova na quarentena | 0 |
| `sucesso com ressalvas` | Etapas ok, mas há registro `pendente` na quarentena desta execução | 0 |
| `falha` | Erro crítico (banco fora, chave duplicada na carga, SQL da auditoria) | diferente de 0 (ação Abortar) |

O placeholder de metadados não conta como ressalva. Ele registra `resultado=placeholder` só nessa etapa. Qualidade e Gold registram `sucesso` ou `falha`. A ressalva do workflow continua vindo de linha pendente na quarentena. Um teste crítico reprovado na qualidade encerra o fluxo como falha e não publica a Gold.

## Log por etapa

Cada etapa grava duas linhas em `auditoria.etapa` (`inicio` e `fim`), com `execucao_id`, `resultado` e `instante`. A duração é a diferença entre os dois. O pipeline `orquestrador_resumo` imprime uma linha por etapa e fecha com:

```
FIM workflow resultado=<sucesso | sucesso com ressalvas | falha> execucao_id=<id>
```

Execução `orquestrador-ok` (caminho completo, com a nota 9 e as duplicatas do Bronze já na base):

| Etapa | Início | Fim | Duração (s) | Resultado |
| --- | --- | --- | --- | --- |
| bronze | 00:13:14 | 00:13:15 | 0,652 | sucesso |
| silver | 00:13:15 | 00:13:16 | 1,687 | sucesso |
| qualidade | 00:13:16 | 00:13:16 | 0,023 | placeholder |
| gold | 00:13:16 | 00:13:16 | 0,022 | placeholder |
| metadados | 00:13:16 | 00:13:16 | 0,022 | placeholder |

Linha final do log: `FIM workflow resultado=sucesso com ressalvas execucao_id=orquestrador-ok`.

Execução `orquestrador-falha`, disparada de propósito com `silver.conteudo` já carregado (a inserção bate na chave primária):

| Etapa | Resultado |
| --- | --- |
| bronze | sucesso |
| silver | falha |
| qualidade, gold, metadados | não iniciaram |

O log fechou com `FIM workflow resultado=falha execucao_id=orquestrador-falha` e a ação Abortar. `silver_interacao` não chegou a ser chamado.

## Como executar

Manual, pela interface: abrir `hop/workflows/orquestrador.hwf` em `http://localhost:8086/ui` e usar Run. O parâmetro `EXECUCAO_ID` pode ficar vazio.

Manual ou agendado, pela linha de comando (o projeto `desafio_dados_2` e o ambiente `docker-env` já estão em `hop/config/hop-config.json`):

```bash
docker exec desafio_apache_hop sh -c "cd /usr/local/tomcat/webapps/ROOT && \
  HOP_CONFIG_FOLDER=/files/config ./hop-run.sh -e docker-env -r local \
  -j desafio_dados_2 -f /files/workflows/orquestrador.hwf \
  -p EXECUCAO_ID=orquestrador-ok"
```

### Agendamento: cron chamando hop-run

A carga agendada usa **cron (ou o Agendador de Tarefas do Windows) chamando `hop-run`**, não o Hop Server.

O `docker-compose.yml` sobe o Hop Web, que é a interface. Não sobe um Hop Server, que seria outro processo só para receber agendamento. O `hop-run` já conhece o projeto, o ambiente e os pipelines, e o mesmo comando serve para o teste manual e para o agendamento. No Linux, uma entrada de cron no host basta:

```cron
15 2 * * * docker exec desafio_apache_hop sh -c 'cd /usr/local/tomcat/webapps/ROOT && HOP_CONFIG_FOLDER=/files/config ./hop-run.sh -e docker-env -r local -j desafio_dados_2 -f /files/workflows/orquestrador.hwf -p EXECUCAO_ID=agendado-$(date +\%Y\%m\%d)'
```

Nesta máquina (Windows), o equivalente é uma tarefa do Agendador de Tarefas com o mesmo `docker exec`.

## Trocar um placeholder pelo pipeline do colega

No `orquestrador.hwf`, a ação `Qualidade (placeholder)` (e o par Gold / Metadados) é do tipo `WRITE_TO_LOG`. Quando o pipeline existir:

1. Trocar o tipo para `PIPELINE`, apontando para o `.hpl` novo e passando `EXECUCAO_ID=${EXECUCAO_ID}`.
2. Manter o hop de sucesso para a ação `Fim ...` da etapa.
3. Acrescentar um hop de falha (`evaluation=N`) no mesmo desenho de `Falha silver`: grava `resultado=falha` em `auditoria.etapa` e segue para `Registrar falha`.
4. No `Fim` da etapa, trocar o valor `'placeholder'` por `'sucesso'`.

O restante do workflow não muda.
