CREATE SCHEMA IF NOT EXISTS bronze;

CREATE TABLE IF NOT EXISTS bronze.catalogo (
    conteudo_id         TEXT,
    titulo              TEXT,
    tipo                TEXT,
    categoria           TEXT,
    nivel               TEXT,
    carga_horaria_min   TEXT,
    data_publicacao     TEXT,
    descricao           TEXT,
    autor               TEXT,
    origem              TEXT NOT NULL,
    arquivo_origem      TEXT NOT NULL,
    data_hora_ingestao  TIMESTAMP NOT NULL,
    execucao_id         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS bronze.interacoes (
    usuario_id            TEXT,
    conteudo_id            TEXT,
    tipo_interacao         TEXT,
    data_hora              TEXT,
    tempo_consumido        TEXT,
    percentual_conclusao   TEXT,
    avaliacao_atribuida    TEXT,
    origem                 TEXT NOT NULL,
    arquivo_origem         TEXT NOT NULL,
    data_hora_ingestao     TIMESTAMP NOT NULL,
    execucao_id            TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS bronze.comentarios (
    usuario_id          TEXT,
    conteudo_id         TEXT,
    avaliacao           TEXT,
    comentario          TEXT,
    tags                TEXT, -- array de origem serializado como texto, sem reordenar/normalizar
    data                TEXT,
    origem              TEXT NOT NULL,
    arquivo_origem      TEXT NOT NULL,
    data_hora_ingestao  TIMESTAMP NOT NULL,
    execucao_id         TEXT NOT NULL
);