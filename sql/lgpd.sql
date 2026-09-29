-- RF32 / RF33 — proteção de dados pessoais.
-- Aplicado por scripts/05_lgpd.ps1, que em seguida executa
--   CALL lgpd.atualizar(:'salt')
-- com o salt lido do .env (LGPD_SALT). O salt não é gravado no banco,
-- em configuração nem neste arquivo: só existe no .env local.
--
-- Técnicas:
--   pseudonimização  usuario_id -> pseudo_id (UUID aleatório). A tabela de
--                    correspondência fica em lgpd_restrito, sem acesso para o BI.
--                    Permite reassociação controlada por quem tem o papel dono.
--   hashing com salt autor -> autor_hash = sha256(salt || '|' || autor). Irreversível,
--                    serve para comparar/deduplicar autores sem ver o nome.
--   mascaramento     autor -> 'P*** C*** A***' e comentário truncado nas views de consumo.
--
-- O papel leitor_bi (sql/papeis_acesso.sql) é o usuário do Superset. Ele lê
-- gold (sem a coluna autor), mestres e lgpd; não lê bronze, silver nem lgpd_restrito.

BEGIN;

CREATE SCHEMA IF NOT EXISTS lgpd;
CREATE SCHEMA IF NOT EXISTS lgpd_restrito;

CREATE OR REPLACE FUNCTION lgpd.hash_com_salt(valor TEXT, salt TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN valor IS NULL THEN NULL
                ELSE encode(sha256(convert_to(salt || '|' || valor, 'UTF8')), 'hex') END;
$$;

CREATE OR REPLACE FUNCTION lgpd.mascarar_nome(valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN valor IS NULL OR btrim(valor) = '' THEN NULL
        ELSE (SELECT string_agg(left(p, 1) || '***', ' ')
              FROM regexp_split_to_table(btrim(valor), '\s+') AS p) END;
$$;

CREATE OR REPLACE FUNCTION lgpd.mascarar_texto(valor TEXT, visiveis INTEGER DEFAULT 20)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN valor IS NULL THEN NULL
                WHEN length(valor) <= visiveis THEN valor
                ELSE left(valor, visiveis) || '...' END;
$$;

-- Tabela de correspondência: fica só no banco, sem GRANT para o BI.
CREATE TABLE IF NOT EXISTS lgpd_restrito.correspondencia_usuario (
    usuario_id  INTEGER PRIMARY KEY,
    pseudo_id   UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    criado_em   TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS lgpd.conteudo_publico (
    conteudo_id      INTEGER PRIMARY KEY,
    titulo           TEXT,
    tipo             TEXT NOT NULL,
    categoria        TEXT NOT NULL,
    nivel            TEXT NOT NULL,
    autor_mascarado  TEXT,
    autor_hash       TEXT,
    atualizado_em    TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE PROCEDURE lgpd.atualizar(p_salt TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_salt IS NULL OR length(p_salt) < 16 THEN
        RAISE EXCEPTION 'LGPD_SALT ausente ou curto (minimo 16 caracteres)';
    END IF;

    INSERT INTO lgpd_restrito.correspondencia_usuario (usuario_id)
    SELECT usuario_id FROM silver.interacao
    UNION
    SELECT usuario_id FROM silver.comentario
    ON CONFLICT (usuario_id) DO NOTHING;

    TRUNCATE lgpd.conteudo_publico;
    INSERT INTO lgpd.conteudo_publico (
        conteudo_id, titulo, tipo, categoria, nivel, autor_mascarado, autor_hash
    )
    SELECT conteudo_id, titulo, tipo, categoria, nivel,
           lgpd.mascarar_nome(autor),
           lgpd.hash_com_salt(lower(btrim(autor)), p_salt)
    FROM gold.dim_conteudo;
END;
$$;

-- Views de consumo: nenhuma delas devolve usuario_id, autor ou comentário completo.
CREATE OR REPLACE VIEW lgpd.vw_interacao_pseudonimizada AS
SELECT
    m.pseudo_id,
    i.conteudo_id,
    i.tipo_interacao,
    i.data_hora::date AS data,
    i.tempo_consumido,
    i.percentual_conclusao,
    i.avaliacao_atribuida
FROM silver.interacao i
JOIN lgpd_restrito.correspondencia_usuario m ON m.usuario_id = i.usuario_id;

CREATE OR REPLACE VIEW lgpd.vw_comentario_mascarado AS
SELECT
    m.pseudo_id,
    c.conteudo_id,
    c.avaliacao,
    lgpd.mascarar_texto(c.comentario) AS comentario_mascarado,
    c.data
FROM silver.comentario c
JOIN lgpd_restrito.correspondencia_usuario m ON m.usuario_id = c.usuario_id;

-- Evidência RF33: valores originais não aparecem no que o BI consegue ler.
CREATE OR REPLACE VIEW lgpd.vw_verificacao AS
SELECT 'autor original igual ao valor exposto em lgpd.conteudo_publico' AS verificacao,
       COUNT(*) FILTER (WHERE p.autor_mascarado = d.autor OR p.autor_hash = d.autor)::BIGINT AS violacoes
FROM lgpd.conteudo_publico p
JOIN gold.dim_conteudo d USING (conteudo_id)
UNION ALL
SELECT 'colunas usuario_id, autor ou comentario legiveis pelo leitor_bi',
       COUNT(*)::BIGINT
FROM information_schema.columns c
WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
  AND c.column_name IN ('usuario_id', 'autor', 'comentario')
  AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'leitor_bi')
  AND has_schema_privilege('leitor_bi', c.table_schema, 'USAGE')
  AND has_column_privilege('leitor_bi', format('%I.%I', c.table_schema, c.table_name), c.column_name, 'SELECT');

COMMIT;
