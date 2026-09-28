# Técnicas de Proteção de Dados — LGPD

## 1. Mascaramento
Aplicado ao campo `autor` no dashboard: `A*** F***`.

## 2. Pseudonimização
Aplicada ao `usuario_id` na Silver: `pseudo_id = SHA256(usuario_id + salt)`.

## 3. Hashing com Salt
Aplicado para deduplicação: `hash_usuario = SHA256(usuario_id + salt)`.

## 4. Comparação
| Técnica | Reversível? | Mantém Associação? | Uso |
|---|---|---|---|
| Mascaramento | Não | Não | Exibição |
| Pseudonimização | Não | Sim | Análise com JOIN |
| Hashing + Salt | Não | Sim | Deduplicação |
