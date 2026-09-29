# Dados mestres — entidade CONTEÚDO (RF30)

Implementação em `sql/dados_mestres.sql`, executada por `scripts/04_dados_mestres.ps1`, que o script do Aluno 2 chama. Números da execução `carga-completa`.

## 1. Entidade, chave e fonte de referência

| Item | Definição |
| --- | --- |
| Entidade mestre | Conteúdo educacional |
| Fonte de referência | `silver.conteudo`: catálogo já tipado e validado pelo Hop |
| Chave de negócio na origem | `conteudo_id` |
| Identificador mestre | `mestre_id = 'CNT-' + menor conteudo_id do grupo`, com 5 dígitos (ex.: `CNT-00039`) |
| Atributos essenciais | `titulo`, `tipo`, `categoria`, `nivel`, `carga_horaria_min`, `data_publicacao` |

**Por que conteúdo.** É a entidade que aparece em todas as fontes (catálogo, interações, comentários e recomendações) e onde há duplicidade real: o catálogo tem 158 títulos repetidos. Usuário não serve, porque só existe como identificador numérico, sem atributos para conciliar. Categoria tem só 8 valores.

## 2. Regra de correspondência

Dois registros são o **mesmo conteúdo** quando têm, ao mesmo tempo:

1. o mesmo título normalizado: minúsculo, sem acento, com espaços simples (`mestres.normalizar`);
2. o mesmo `tipo`;
3. o mesmo autor normalizado.

O autor faz parte da regra porque título igual com autor diferente é outro material. Dos 158 títulos repetidos, só 11 grupos têm o mesmo autor e o mesmo tipo. Sem o autor, conteúdos distintos seriam fundidos por engano.

## 3. Deduplicação e sobrevivência

Cada grupo vira um único registro em `mestres.conteudo_mestre`. O valor que sobrevive depende do atributo:

| Atributo | Regra | Motivo |
| --- | --- | --- |
| `titulo`, `tipo`, `categoria` | Do registro de menor `conteudo_id` (primeiro cadastro) | Identificação estável: o primeiro cadastro é o que os usuários já conhecem |
| `nivel`, `carga_horaria_min`, `data_publicacao` | Do registro com `data_publicacao` mais recente; empate vai para o maior `conteudo_id` | Descrevem a versão atual do material |
| Qualquer atributo | Nulo nunca sobrevive se outro registro do grupo tiver valor | Evita perder informação |

A **tabela de correspondência** `mestres.correspondencia_conteudo` liga cada `conteudo_id` ao seu `mestre_id` e registra a regra aplicada (`unico` ou `titulo_normalizado+tipo+autor`) e se aquele registro é o sobrevivente.

O de-para de categoria (`mestres.categoria_depara`) guarda cada grafia encontrada no Bronze e a categoria canônica. Nesta base, as 8 grafias do Bronze já chegam iguais às canônicas.

## 4. Resultado

| Medida | Valor |
| --- | ---: |
| Registros de origem (`silver.conteudo`) | 1000 |
| Registros mestres | 989 |
| Grupos com mais de um registro | 11 |

## 5. Dois registros conflitantes

Os conteúdos 39 e 480 têm o mesmo título ("Melhores Práticas e Arquitetura de Processamento..."), o mesmo tipo e o mesmo autor, mas carga horária e data de publicação diferentes:

| conteudo_id | Sobrevivente | Nível | Carga (min) | Publicação |
| ---: | --- | --- | ---: | --- |
| 39 | sim (título, tipo, categoria) | Básico | 17 | 2024-02-08 |
| 480 | não | Básico | 29 | 2024-04-13 |
| **CNT-00039 (mestre)** | | **Básico** | **29** | **2024-04-13** |

O `mestre_id` vem do 39, o menor id. A carga e a data vêm do 480, a publicação mais recente. O registro mestre mistura os dois de propósito, conforme a regra de sobrevivência por atributo.

Para reproduzir:

```sql
CALL mestres.consolidar();
SELECT * FROM mestres.vw_conflitos WHERE mestre_id = 'CNT-00039';
```

## 6. Limitações

- A normalização não trata sinônimos nem erros de digitação ("Introducao a SQL" e "Intro a SQL" continuam diferentes).
- O mestre é recalculado a cada execução (`TRUNCATE` e recarga). O `mestre_id` é estável enquanto o menor `conteudo_id` do grupo não mudar.
- A Gold ainda usa `conteudo_id`. Adotar o `mestre_id` nos KPIs somaria as interações dos 11 grupos duplicados.
