# Storytelling executivo — Plataforma Educacional (RF16)

Números da execução `carga-completa`, lidos da camada Gold. Para reproduzir, rode a consulta 4 de `sql/sql_lab.sql` e as consultas indicadas em cada seção.

## 1. Pergunta decisória

**Em que formato de conteúdo a plataforma deve concentrar a produção do próximo ciclo para aumentar a taxa de conclusão?**

A decisão envolve orçamento de produção: um curso custa muito mais para produzir que um vídeo ou um artigo. Se o formato caro não converte melhor em conclusão, o investimento precisa mudar de lugar.

## 2. Contexto

A plataforma tem 1000 conteúdos em quatro formatos, com quantidades parecidas: 272 artigos, 256 podcasts, 238 vídeos e 234 cursos. Entre 1º de janeiro e 25 de agosto de 2026, 150 usuários ativos geraram 1000 interações. A taxa de conclusão geral é de 28,62%, e a avaliação média é de 4,48 em 5.

O motor de recomendação do Desafio 1 gerou 744 recomendações no último lote. Dessas, 76 viraram interação: conversão de 10,22%, acima da meta de 8%.

**Fonte:** `gold.kpi_geral` e `gold.kpi_conversao_recomendacao`.

## 3. Evidência

A sequência de visualizações segue a narrativa: primeiro o volume ao longo do tempo, depois a conclusão por categoria e formato, e por fim a comparação entre formatos.

### 3.1 O engajamento é contínuo, não sazonal

Gráfico **Evolução Temporal de Interações** (dataset virtual `vds_interacoes_dia_categoria`). As 1000 interações estão distribuídas em 234 dias, sem mês concentrando o volume. A diferença de conclusão entre formatos, portanto, não vem de um pico isolado de uso.

### 3.2 A conclusão varia mais por categoria do que por formato

Gráfico **Taxa de Conclusão por Categoria** (barras agrupadas por formato):

| Categoria | Interações | Taxa de conclusão |
| --- | ---: | ---: |
| DevOps & Cloud | 141 | 42,6% |
| Programação & Software | 104 | 36,8% |
| Banco de Dados | 128 | 33,3% |
| Inteligência Artificial | 128 | 32,2% |
| Ciência de Dados | 120 | 27,0% |
| Business Intelligence | 144 | 26,9% |
| Engenharia de Dados | 121 | 22,7% |
| Segurança & Governança | 114 | 13,2% |

A distância entre a melhor e a pior categoria é de 29,4 pontos percentuais.

**Fonte:** consulta 2 de `sql/sql_lab.sql` (dataset virtual `vds_conclusao_categoria_mes`).

### 3.3 Vídeo lidera a conclusão; Curso fica em último

| Formato | Conteúdos | Interações | Taxa de conclusão | Avaliação média | Tempo médio (min) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Vídeo | 238 | 262 | **33,85%** | 4,50 | 29,2 |
| Podcast | 256 | 250 | 29,20% | 4,43 | 29,9 |
| Artigo | 272 | 262 | 28,00% | 4,50 | 9,4 |
| Curso | 234 | 226 | **23,14%** | 4,48 | 563,4 |

**Fonte:** `gold.kpi_engajamento_formato`, consulta 4 de `sql/sql_lab.sql`.

## 4. Descoberta

**Fato observado.** O Vídeo conclui 10,7 pontos percentuais a mais que o Curso, com praticamente a mesma avaliação (4,50 contra 4,48). O Curso exige, em média, 563 minutos de consumo, 19 vezes o tempo de um vídeo.

**Fato observado.** A avaliação quase não muda entre formatos: vai de 4,43 a 4,50. O usuário que termina gosta do que consumiu em qualquer formato, então a diferença está em **terminar**, não em gostar.

**Hipótese (a validar).** A duração é a principal barreira de conclusão. Um curso de 9 horas tem mais pontos de abandono que um vídeo de 30 minutos.

**Hipótese (a validar).** A categoria Segurança & Governança, com 13,2% de conclusão, tem um problema de conteúdo ou de nível, não de formato. Ela fica abaixo da média nos quatro formatos: 6,7% em Vídeo (contra 33,8% no geral), 12,5% em Podcast, 14,8% em Artigo e 16,7% em Curso.

## 5. Ação recomendada

1. **Concentrar a produção nova em vídeos**, que têm a maior conclusão com custo de produção menor que o de cursos.
2. **Quebrar os cursos longos em trilhas de vídeos curtos.** Isso testa diretamente a hipótese da duração: se a conclusão dos módulos subir para perto dos 34% do vídeo, a hipótese se confirma.
3. **Revisar o catálogo de Segurança & Governança** (nível, pré-requisitos, descrição) antes de produzir mais conteúdo nessa categoria.
4. **Manter o alerta de conversão** configurado no Superset. A conversão atual (10,22%) está 2,2 pontos acima do limite de 8%; se cair, o motor de recomendação precisa ser revisto antes de qualquer mudança de catálogo.

## 6. Fatos, hipóteses e recomendações

| Tipo | Afirmação | Base |
| --- | --- | --- |
| Fato | Vídeo tem 33,85% de conclusão; Curso, 23,14% | `gold.kpi_engajamento_formato` |
| Fato | A avaliação média varia só entre 4,43 e 4,50 entre formatos | `gold.kpi_engajamento_formato` |
| Fato | Conversão de recomendação de 10,22% (meta: 8%) | `gold.kpi_conversao_recomendacao` |
| Hipótese | A duração do curso é a principal barreira de conclusão | tempo médio de 563 min contra 29 min |
| Hipótese | Segurança & Governança tem problema de conteúdo | 13,2% de conclusão, a menor entre as categorias |
| Recomendação | Priorizar vídeo e modularizar cursos | seções 3.3 e 4 |

## 7. Limitações

- Os dados são fictícios, gerados para o desafio; as conclusões valem como exercício de método.
- São 1000 interações para 1000 conteúdos: a maioria dos conteúdos tem uma ou duas interações. As diferenças entre formatos são de alguns pontos percentuais e podem mudar com mais volume.
- A taxa de conclusão divide conclusões por inícios e visualizações do mesmo recorte. Um usuário que concluiu sem registro de início conta só no numerador.
- A conversão de recomendação considera qualquer interação posterior do mesmo usuário com o conteúdo recomendado, sem janela de tempo.
