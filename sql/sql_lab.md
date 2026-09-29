# Consultas do SQL Lab (RF17)

As quatro consultas estão em `sql/sql_lab.sql`. Todas leem só a camada Gold (`gold.fato_engajamento_dia`, `gold.dim_conteudo` e as tabelas `gold.kpi_*`) e rodam com o usuário `leitor_bi`, o mesmo que o Superset usa. Por isso qualquer resultado do SQL Lab pode ser reproduzido a partir da Gold, sem acesso a Bronze, Silver ou a dados pessoais.

As consultas 1 e 2 estão salvas como **datasets virtuais** no Superset. O script `src/setup_superset_internal.py` lê o próprio `sql_lab.sql` e cria os datasets com o mesmo SQL, então o arquivo e o Superset não se desencontram.

| Consulta | Dataset virtual | Junção | Agregação | Condicional | Função de data |
| --- | --- | --- | --- | --- | --- |
| 1 | `vds_interacoes_dia_categoria` | fato x dimensão | `SUM` | `CASE` tipo de dia | `DATE_TRUNC`, `EXTRACT(ISODOW)` |
| 2 | `vds_conclusao_categoria_mes` | fato x dimensão | `SUM`, `ROUND` | `CASE` faixa de conclusão | `DATE_TRUNC` |
| 3 | não (condição do alerta) | `CROSS JOIN` | não | `CASE` situação do alerta | `TO_CHAR` |
| 4 | não (storytelling) | não | janela `RANK()` | não | não |

## Consulta 1 — interações por dia e categoria

**Finalidade:** série diária de interações, recortável por categoria e formato. Alimenta o gráfico **Evolução Temporal de Interações** e o filtro global de período.

| Campo | Tipo | Cálculo |
| --- | --- | --- |
| `data` | data | dia da interação (grão do fato) |
| `mes` | data | `DATE_TRUNC('month', data)`, primeiro dia do mês |
| `categoria`, `tipo` | texto | de `gold.dim_conteudo` |
| `total_interacoes` | inteiro | `SUM(total_interacoes)` |
| `conclusoes` | inteiro | `SUM(conclusoes)` |
| `inicios_visualizacoes` | inteiro | `SUM(inicios + visualizacoes)`, denominador da taxa de conclusão |
| `tipo_dia` | texto | `CASE` sobre `EXTRACT(ISODOW)`: `fim de semana` (6 e 7) ou `dia útil` |

**Conferência:** a soma de `total_interacoes` por `data` é igual a `gold.kpi_evolucao_dia.total_interacoes` (1000 interações em 234 dias na execução `carga-completa`).

## Consulta 2 — taxa de conclusão por categoria e mês

**Finalidade:** taxa mensal de conclusão por categoria, com uma faixa de desempenho. Alimenta o filtro global **Categoria**.

| Campo | Tipo | Cálculo |
| --- | --- | --- |
| `mes` | data | `DATE_TRUNC('month', data)` |
| `categoria` | texto | de `gold.dim_conteudo` |
| `conclusoes`, `inicios_visualizacoes` | inteiro | somas do fato |
| `taxa_conclusao_pct` | numérico | `100 * conclusoes / NULLIF(inicios_visualizacoes, 0)`, 2 casas decimais |
| `faixa_conclusao` | texto | `CASE`: `alta` (≥ 30%), `média` (≥ 20%) ou `baixa` |

O `NULLIF` evita divisão por zero em um mês sem início nem visualização.

## Consulta 3 — condição do alerta de conversão

**Finalidade:** mostrar no SQL Lab a mesma condição que o alerta **Conversão de recomendação abaixo de 8%** avalia (RF18).

| Campo | Cálculo |
| --- | --- |
| `total_recomendacoes`, `recomendacoes_com_interacao`, `taxa_conversao_pct` | de `gold.kpi_conversao_recomendacao` |
| `usuarios_ativos` | de `gold.kpi_geral`, pelo `CROSS JOIN` (as duas tabelas têm uma linha) |
| `situacao` | `CASE WHEN taxa_conversao_pct < 8 THEN 'dispara alerta' ELSE 'dentro da meta' END` |
| `lote_recomendacao` | `TO_CHAR(lote_gerado_em, 'YYYY-MM-DD HH24:MI')` |

Resultado na execução `carga-completa`: 744 recomendações, 76 com interação, taxa de 10,22%, situação `dentro da meta`.

## Consulta 4 — formatos por retenção

**Finalidade:** responder à pergunta do storytelling (`documentacao/storytelling.md`): qual formato conclui mais.

| Campo | Cálculo |
| --- | --- |
| `formato`, `qtd_conteudos`, `total_interacoes`, `taxa_conclusao_pct`, `avaliacao_media` | de `gold.kpi_engajamento_formato` |
| `posicao_retencao` | `RANK() OVER (ORDER BY taxa_conclusao_pct DESC)` |

Resultado: Vídeo 33,85% (1º), Podcast 29,20% (2º), Artigo 28,00% (3º), Curso 23,14% (4º).

## Como rodar

- **No Superset:** SQL Lab em http://localhost:8088/sqllab/, banco `Plataforma Educacional (PostgreSQL)`; colar a consulta desejada.
- **Pelo terminal:** `.\scripts\aluno3_governanca_superset.ps1` executa o arquivo inteiro. Para rodar só as consultas:

```powershell
docker cp sql/sql_lab.sql desafio_postgres:/tmp/sql_lab.sql
docker exec desafio_postgres psql -U postgres -d plataforma_educacional -f /tmp/sql_lab.sql
```
