# Alerta Configurado no Superset (RF18)

## Nome
Alerta de Baixa Conversão de Recomendação

## Banco de Dados
Plataforma Educacional (Docker)

## SQL
SELECT MAX(taxa_conversao_pct) AS value FROM gold.kpi_conversao_recomendacao;

## Condição
Value < 8

## Agendamento
0 9 * * * (diário às 9h) — configurado como 12:00 AM UTC

## Destinatário
aluno3@ficticio.edu.br

## Ação
Enviar e-mail com o valor da taxa de conversão de recomendação

## Justificativa
Taxas de conversão abaixo de 8% indicam que o motor de recomendação não está sendo eficaz. O alerta permite ação proativa da equipe de dados.

## Status
Alerta criado e ativo. O envio de e-mail depende da configuração SMTP do ambiente. A condição de disparo foi validada manualmente.
