# Regras de qualidade (RF31)

Os testes rodam sobre a Silver, depois da padronização e antes da Gold. O resultado fica em `qualidade.resultado`, uma linha por teste e por `execucao_id`. A view `qualidade.vw_evolucao` guarda a série de `completude_titulo` e `consistencia_conclusao`.

A Gold só publica se `qualidade.bloquear_se_critico` passar. Teste de severidade média ou alta reprovado fica registrado e não impede a publicação. Teste crítico reprovado interrompe o workflow na ação `Gate qualidade` e a ação `Gold` não roda.

| Teste | Dimensão | Fonte | Fórmula | Limite | Severidade | Ação |
| --- | --- | --- | --- | --- | --- | --- |
| `completude_titulo` | completude | `silver.conteudo` | 100 × conteúdos com título preenchido / conteúdos | >= 99 | alta | registrar ressalva; a Gold continua |
| `validade_percentual` | validade | `silver.interacao` | interações com `percentual_conclusao` fora de 0–100 | <= 0 | crítica | bloquear a Gold |
| `unicidade_interacao` | unicidade | `silver.interacao` | linhas menos a chave distinta `(usuario_id, conteudo_id, data_hora)` | <= 0 | crítica | bloquear a Gold |
| `consistencia_conclusao` | consistência | `silver.interacao` | 100 × conclusões com percentual >= 100 / conclusões | >= 90 | média | registrar ressalva; a Gold continua |
| `integridade_comentario_conteudo` | integridade referencial | `silver.comentario` | comentários cujo `conteudo_id` não existe em `silver.conteudo` | <= 0 | crítica | bloquear a Gold |

Aplicação isolada, sem o workflow:

```sql
SELECT qualidade.aplicar('execucao-id');
SELECT qualidade.bloquear_se_critico('execucao-id');
SELECT gold.publicar('execucao-id');
```
