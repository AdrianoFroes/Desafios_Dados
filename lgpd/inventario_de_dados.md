# Inventário de Dados Pessoais — Plataforma Educacional

| Campo | Ativo | Classificação | Finalidade | Necessidade | Acesso | Retenção | Proteção |
|---|---|---|---|---|---|---|---|
| usuario_id | usuario, interacao, recomendacao, silver.* | PII.IndirectIdentifier | Associar interações | Sim | Restrito | Longo prazo | Pseudonimização (Gold) + Hashing (Silver) |
| autor | conteudo, gold.dim_conteudo | PII.IndirectIdentifier | Crédito de autoria | Sim | Restrito | Permanente | Mascaramento no dashboard |
| comentario (MongoDB) | comentarios | PII.IndirectIdentifier | Feedback | Sim | Restrito | 12 meses | Mascaramento |
