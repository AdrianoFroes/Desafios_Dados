# Técnicas de proteção de dados (RF33)

Implementação em `sql/lgpd.sql` e `sql/papeis_acesso.sql`, aplicada por `scripts/05_lgpd.ps1`, que o script do Aluno 3 chama.

## 1. Mascaramento — campo exibido para consumo

| | |
| --- | --- |
| Campos | `autor` e `comentario` |
| Função | `lgpd.mascarar_nome(valor)`: mantém a inicial de cada palavra (o autor fictício `Profa. Carla Antunes Silveira` vira `P*** C*** A*** S***`). `lgpd.mascarar_texto(valor, 20)`: mantém os 20 primeiros caracteres e acrescenta `...` |
| Onde fica | `lgpd.conteudo_publico.autor_mascarado` e `lgpd.vw_comentario_mascarado.comentario_mascarado` |
| Reversível | Não. O valor completo não é guardado nessas estruturas |

## 2. Pseudonimização — identificador que ainda precisa de associação controlada

| | |
| --- | --- |
| Campo | `usuario_id` |
| Técnica | Cada `usuario_id` recebe um `pseudo_id` UUID aleatório (`gen_random_uuid()`), gravado em `lgpd_restrito.correspondencia_usuario` |
| Onde é usado | `lgpd.vw_interacao_pseudonimizada` e `lgpd.vw_comentario_mascarado` devolvem `pseudo_id` no lugar do `usuario_id` |
| Associação controlada | Só quem tem acesso ao esquema `lgpd_restrito` consegue voltar do `pseudo_id` para o `usuario_id`. O `leitor_bi` e o `om_catalogo` não têm |
| Por que UUID aleatório e não hash | Hash do `usuario_id` (um número de 1 a 150) seria revertido por força bruta em milissegundos, mesmo com salt vazado. O UUID não tem relação matemática com o id |

## 3. Hashing com salt — comparação irreversível

| | |
| --- | --- |
| Campo | `autor` |
| Técnica | `autor_hash = sha256(salt || '|' || lower(trim(autor)))`, em `lgpd.hash_com_salt` |
| Onde fica | `lgpd.conteudo_publico.autor_hash` |
| Para que serve | Comparar e contar autores (quantos conteúdos cada autor tem, se dois conteúdos são do mesmo autor) sem ver o nome |
| Salt | Vem de `LGPD_SALT` no `.env`, gerado aleatoriamente pelo `scripts/00_setup.ps1`. É passado como parâmetro para `CALL lgpd.atualizar(:'salt')` e **não é gravado** em tabela, configuração do banco ou arquivo versionado. A procedure recusa salt com menos de 16 caracteres |

## 4. Comparação entre as técnicas

| Critério | Mascaramento | Pseudonimização | Hash com salt |
| --- | --- | --- | --- |
| Reversível | Não | Sim, só com a tabela de correspondência | Não |
| Mantém associação entre registros | Não | Sim (`pseudo_id` estável) | Sim (mesmo autor gera o mesmo hash) |
| Legível por pessoa | Parcialmente | Não | Não |
| Risco se vazar | Baixo | Médio: sem a tabela restrita, o `pseudo_id` sozinho não identifica | Baixo com salt secreto; alto se o salt vazar e o domínio for pequeno |
| Uso neste projeto | Exibir autor e comentário no consumo | Analisar comportamento por usuário sem expor o id | Comparar autores sem expor o nome |

**Por que cada técnica foi aplicada onde está:**

- O `usuario_id` precisa de reassociação controlada (atender a um pedido de acesso ou exclusão do titular, por exemplo). Por isso ele é **pseudonimizado**, não hasheado.
- O `autor` não precisa voltar ao original no consumo, mas precisa ser comparável. Por isso recebe **hash com salt** para comparação e **máscara** para exibição.
- O `comentario` só precisa ser lido parcialmente. Por isso é **mascarado** por truncamento.

## 5. Segredos fora do repositório

| Segredo | Onde fica | Versionado? |
| --- | --- | --- |
| `LGPD_SALT` | `.env` | Não (`.gitignore`) |
| Tabela de correspondência `usuario_id` → `pseudo_id` | Esquema `lgpd_restrito`, só no banco | Não |
| Senhas `POSTGRES_PASSWORD`, `BI_PASSWORD`, `OM_CATALOGO_PASSWORD`, `SUPERSET_SECRET_KEY` | `.env` | Não |

O `.env.example` versionado traz só o marcador `__gerar__` no lugar de cada segredo; o `scripts/00_setup.ps1` gera os valores na primeira execução.

## 6. O dashboard não expõe os valores originais

O Superset conecta ao banco com o papel `leitor_bi`. Evidências, geradas por `scripts/05_lgpd.ps1`:

```text
leitor_bi> SELECT * FROM lgpd_restrito.correspondencia_usuario;
ERROR:  permission denied for schema lgpd_restrito

leitor_bi> SELECT autor FROM gold.dim_conteudo;
ERROR:  permission denied for table dim_conteudo
```

```sql
SELECT * FROM lgpd.vw_verificacao;
--  autor original igual ao valor exposto em lgpd.conteudo_publico   | 0
--  colunas usuario_id, autor ou comentario legiveis pelo leitor_bi  | 0
```

Nenhum dos 3 gráficos do dashboard, nem os 12 datasets, usa `usuario_id`, `autor` ou `comentario`.
