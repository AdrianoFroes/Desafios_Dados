-- Log estruturado do workflow orquestrador (RF22).
-- Uma linha por evento (inicio/fim) de cada etapa, correlacionada por execucao_id.
-- A duracao e a diferenca entre o fim e o inicio da mesma etapa.

CREATE SCHEMA IF NOT EXISTS auditoria;

CREATE TABLE IF NOT EXISTS auditoria.etapa (
    id            BIGSERIAL PRIMARY KEY,
    execucao_id   TEXT NOT NULL,
    etapa         TEXT NOT NULL,
    evento        TEXT NOT NULL,
    resultado     TEXT,
    instante      TIMESTAMP NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_auditoria_etapa_evento CHECK (evento IN ('inicio', 'fim')),
    CONSTRAINT ck_auditoria_etapa_resultado CHECK (
        resultado IS NULL
        OR resultado IN ('sucesso', 'sucesso com ressalvas', 'placeholder', 'falha')
    )
);

CREATE INDEX IF NOT EXISTS ix_auditoria_etapa_execucao
    ON auditoria.etapa (execucao_id, instante);

-- Etapa "metadados" do orquestrador: snapshot tecnico das tabelas publicadas.
-- A ingestao do OpenMetadata le o banco logo depois e encontra esta tabela.
CREATE TABLE IF NOT EXISTS auditoria.metadados (
    id            BIGSERIAL PRIMARY KEY,
    execucao_id   TEXT NOT NULL,
    esquema       TEXT NOT NULL,
    tabela        TEXT NOT NULL,
    linhas        BIGINT NOT NULL,
    colunas       INTEGER NOT NULL,
    publicado_em  TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE PROCEDURE auditoria.publicar_metadados(p_execucao_id TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_linhas BIGINT;
BEGIN
    DELETE FROM auditoria.metadados WHERE execucao_id = p_execucao_id;
    FOR r IN
        SELECT t.table_schema, t.table_name,
               (SELECT COUNT(*) FROM information_schema.columns c
                 WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name) AS colunas
        FROM information_schema.tables t
        WHERE t.table_schema IN ('silver', 'gold', 'mestres')
          AND t.table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM %I.%I', r.table_schema, r.table_name) INTO v_linhas;
        INSERT INTO auditoria.metadados (execucao_id, esquema, tabela, linhas, colunas)
        VALUES (p_execucao_id, r.table_schema, r.table_name, v_linhas, r.colunas);
    END LOOP;
END;
$$;
