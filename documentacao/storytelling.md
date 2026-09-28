# Storytelling Executivo — Plataforma Educacional

## 1. Pergunta Decisória

**Quais formatos de conteúdo apresentam maior retenção e deveriam receber prioridade de investimento na plataforma educacional?**

---

## 2. Contexto

A plataforma educacional oferece conteúdos em quatro formatos principais: **Curso**, **Vídeo**, **Artigo** e **Podcast**. Apesar do volume crescente de dados de interação, a instituição não possui clareza sobre qual formato gera maior engajamento e retenção. Sem essa clareza, decisões de investimento em produção de conteúdo são tomadas com base em intuição, e não em evidências.

Este documento apresenta uma narrativa executiva baseada nos dados consolidados na camada **Gold** da plataforma, respondendo à pergunta decisória e recomendando ações concretas.

---

## 3. Evidência

### 3.1 Taxa de Conclusão por Formato

A análise dos KPIs consolidados revela diferenças significativas na taxa de conclusão entre formatos:

| Formato | Taxa de Conclusão | Avaliação Média |
|---|---|---|
| **Artigo** | 70,0% | 4,7 |
| **Podcast** | 61,5% | 4,9 |
| **Vídeo** | 44,4% – 50,0% | 4,6 – 4,8 |
| **Curso** | 23,1% | 4,2 |

**Fonte:** `gold.kpi_desempenho_categoria` e `gold.kpi_engajamento_formato`

### 3.2 Evolução Temporal

A série temporal de interações mostra fluxo contínuo de estudos, com picos em ciclos quinzenais. Todas as categorias mantêm avaliação média superior a 4,0, indicando satisfação consistente.

**Fonte:** `gold.kpi_evolucao_dia`

### 3.3 Conversão de Recomendações

A taxa de conversão do motor de recomendação está na faixa de **8% a 15%**, considerada excelente no contexto de sistemas educacionais sem interface push.

**Fonte:** `gold.kpi_conversao_recomendacao`

---

## 4. Descoberta

**Fato observado:** Formatos curtos (Artigo, Podcast, Vídeo) apresentam taxa de conclusão significativamente superior à de Cursos longos (23,1%).

**Hipótese:** A menor barreira de tempo e a possibilidade de consumo fragmentado explicam a maior retenção dos formatos curtos. Cursos extensos exigem maior comprometimento contínuo do aluno.

**Correlação:** A avaliação média não cai nos formatos curtos (permanece acima de 4,5), o que indica que a maior retenção não é resultado de conteúdo mais raso.

---

## 5. Ação Recomendada

Com base nas evidências, recomenda-se:

1. **Priorizar a produção de Artigos e Podcasts temáticos** para tópicos introdutórios, dado o alto desempenho em retenção.
2. **Quebrar Cursos longos em módulos menores** (microlearning), para reduzir a barreira de conclusão.
3. **Aplicar gamificação em Cursos extensos**, com metas intermediárias e recompensas.
4. **Manter o investimento em Vídeos** para tópicos técnicos, onde já apresentam bom desempenho (44% – 50%).
5. **Monitorar continuamente a conversão de recomendações**, com alerta automático quando cair abaixo de 8%.

---

## 6. Distinção entre Fatos, Hipóteses e Recomendações

| Tipo | Descrição | Exemplo |
|---|---|---|
| **Fato** | Dado observado nos KPIs | Artigos têm taxa de conclusão de 70% |
| **Hipótese** | Explicação proposta, a validar | A menor barreira de tempo explica a maior retenção |
| **Recomendação** | Ação sugerida | Priorizar produção de Artigos e Podcasts |

---

## 7. Limitações da Análise

- Os dados utilizados são **fictícios**, gerados para o desafio.
- O modelo de recomendação é **simples** (não é machine learning de verdade).
- O período de análise é **limitado** (cerca de mil interações).
- A amostra não representa toda a diversidade de usuários de uma plataforma real.

---

## 8. Uso de IA

A IA foi utilizada para:
- Auxiliar na interpretação dos KPIs e na redação da narrativa.
- Revisar as consultas SQL Lab.
- Apoiar a documentação dos metadados no OpenMetadata.
- Sugerir melhorias no mascaramento e pseudonimização dos dados pessoais.

**Todas as decisões técnicas foram validadas manualmente pela equipe.**
