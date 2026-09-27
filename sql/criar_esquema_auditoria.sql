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
