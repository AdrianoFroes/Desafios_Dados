-- RF32 / RF33 — papel de leitura do Superset.
-- Executado por scripts/05_lgpd.ps1 com: psql -v bi_password=... -f papeis_acesso.sql
-- A senha vem do .env (BI_PASSWORD) e não fica neste arquivo.
-- O leitor_bi enxerga só a camada de consumo: gold (sem a coluna autor),
-- mestres (sem correspondência de pessoa) e as views mascaradas de lgpd.

SELECT format('CREATE ROLE leitor_bi LOGIN PASSWORD %L', :'bi_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'leitor_bi')
\gexec

ALTER ROLE leitor_bi WITH LOGIN PASSWORD :'bi_password';

SELECT format('GRANT CONNECT ON DATABASE %I TO leitor_bi', current_database())
\gexec

REVOKE ALL ON SCHEMA lgpd_restrito FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA lgpd_restrito FROM PUBLIC;
REVOKE ALL ON SCHEMA bronze, silver, quarentena FROM leitor_bi;

GRANT USAGE ON SCHEMA gold, mestres, lgpd, qualidade TO leitor_bi;

GRANT SELECT ON ALL TABLES IN SCHEMA gold TO leitor_bi;
REVOKE SELECT ON gold.dim_conteudo FROM leitor_bi;
GRANT SELECT (conteudo_id, titulo, tipo, categoria, nivel, carga_horaria_min,
              data_publicacao, execucao_id, publicado_em)
    ON gold.dim_conteudo TO leitor_bi;

GRANT SELECT ON mestres.conteudo_mestre, mestres.categoria_depara,
                mestres.correspondencia_conteudo, mestres.vw_conflitos TO leitor_bi;
GRANT SELECT ON lgpd.conteudo_publico, lgpd.vw_interacao_pseudonimizada,
                lgpd.vw_comentario_mascarado, lgpd.vw_verificacao TO leitor_bi;
GRANT SELECT ON qualidade.resultado, qualidade.vw_evolucao TO leitor_bi;

-- om_catalogo: usuário da ingestão do OpenMetadata. Lê a estrutura de todas as
-- camadas (inclusive bronze e silver, para a linhagem), nunca lgpd_restrito.
SELECT format('CREATE ROLE om_catalogo LOGIN PASSWORD %L', :'om_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'om_catalogo')
\gexec

ALTER ROLE om_catalogo WITH LOGIN PASSWORD :'om_password';

SELECT format('GRANT CONNECT ON DATABASE %I TO om_catalogo', current_database())
\gexec

GRANT USAGE ON SCHEMA public, bronze, silver, quarentena, qualidade, auditoria, gold, mestres, lgpd TO om_catalogo;
GRANT SELECT ON ALL TABLES IN SCHEMA public, bronze, silver, quarentena, qualidade, auditoria, gold, mestres, lgpd TO om_catalogo;
REVOKE ALL ON ALL TABLES IN SCHEMA lgpd_restrito FROM om_catalogo;

-- Views do Desafio 1 que o Superset ainda registra como referência (agregadas).
-- Views com usuario_id, autor ou comentario ficam de fora (ex.: vw_kpi_analise_conteudos).
DO $$
DECLARE v RECORD;
BEGIN
    FOR v IN SELECT t.table_name,
                    EXISTS (SELECT 1 FROM information_schema.columns c
                            WHERE c.table_schema = 'public' AND c.table_name = t.table_name
                              AND c.column_name IN ('usuario_id', 'autor', 'comentario')) AS pessoal
             FROM information_schema.views t
             WHERE t.table_schema = 'public' AND t.table_name LIKE 'vw_kpi_%'
    LOOP
        IF v.pessoal THEN
            EXECUTE format('REVOKE ALL ON public.%I FROM leitor_bi', v.table_name);
        ELSE
            EXECUTE format('GRANT SELECT ON public.%I TO leitor_bi', v.table_name);
        END IF;
    END LOOP;
END $$;
