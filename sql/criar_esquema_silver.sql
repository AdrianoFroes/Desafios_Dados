-- RF21 — esquema Silver + quarentena
-- Banco: plataforma_educacional (docker-compose.yml)
-- Lê de bronze.* (sql/criar_esquema_bronze.sql) via Apache Hop, aplica as
-- regras de hop/contratos_bronze_silver.md (seções 2 e 3) e grava aqui.
-- Colunas e domínios espelham exatamente o contrato; não inventar campo novo
-- sem atualizar o contrato primeiro.

BEGIN;

CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS quarentena;

-- -------------------------------------------------------
-- 0. Função utilitária — normalização de tags (RF04/§2.3 do contrato)
-- Recebe o texto bruto de bronze.comentarios.tags (JSON serializado, ex.
-- '["Docker","spark","docker"]') e devolve JSON-texto minúsculo, sem
-- duplicata e em ordem alfabética. Entrada nula, vazia ou que não seja um
-- array JSON válido devolve '[]' (nunca lança erro para o restante da
-- consulta/lote — é por isso que é uma função com EXCEPTION, não uma
-- expressão inline: um cast malformado inline abortaria o lote inteiro).
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION silver.tags_normalizadas(entrada TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    doc JSONB;
BEGIN
    IF entrada IS NULL OR BTRIM(entrada) = '' THEN
        RETURN '[]';
    END IF;

    BEGIN
        doc := entrada::JSONB;
    EXCEPTION WHEN OTHERS THEN
        RETURN '[]';
    END;

    IF jsonb_typeof(doc) IS DISTINCT FROM 'array' THEN
        RETURN '[]';
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(tag ORDER BY tag), '[]'::jsonb)::text
        FROM (
            SELECT DISTINCT LOWER(BTRIM(elem)) AS tag
            FROM jsonb_array_elements_text(doc) AS elem
            WHERE LOWER(BTRIM(elem)) <> ''
        ) normalizadas
    );
END;
$$;

-- -------------------------------------------------------
-- 1. Usuário — decisão de design (mesma do Desafio 1, ver sql/criar_tabelas.sql)
-- Não há cadastro de usuários na origem, só o usuario_id aparecendo em
-- interações e comentários: não existe um mestre independente contra o qual
-- validar. "Validar referência de usuário" (RF21), aqui, significa garantir
-- que o identificador é um inteiro positivo bem formado — não uma FK contra
-- um cadastro que não existe. usuario_id ausente/não numérico/≤0 é
-- USUARIO_INVALIDO (quarentena, ver seções 3 e 4). Isso evita uma FK
-- circular (interação/comentário dependeriam de uma tabela populada pelos
-- próprios pipelines de interação/comentário).
-- A referência que TEM mestre independente é conteudo_id (contra
-- silver.conteudo, carregado pelo pipeline Silver de catálogo, que por isso
-- deve rodar antes — ver hop/contratos_bronze_silver.md).
-- -------------------------------------------------------

-- -------------------------------------------------------
-- 2. silver.conteudo
-- Origem: bronze.catalogo. Chave de negócio: conteudo_id (dedupe = 1ª
-- ocorrência). Domínio fora do canônico (tipo/categoria/nivel) vira
-- TIPO_FORA_DO_DOMINIO na quarentena — diferente do RF04/Desafio 1, que só
-- registrava e mantinha o valor.
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.conteudo (
    conteudo_id             INTEGER    PRIMARY KEY,
    titulo                  TEXT,
    tipo                    TEXT       NOT NULL,
    categoria               TEXT       NOT NULL,
    nivel                   TEXT       NOT NULL,
    carga_horaria_min       INTEGER,
    data_publicacao         DATE,
    descricao               TEXT,
    autor                   TEXT,

    -- colunas de auditoria (vindas do Bronze, ver contrato §1)
    origem                  TEXT       NOT NULL,
    arquivo_origem          TEXT       NOT NULL,
    data_hora_ingestao      TIMESTAMP  NOT NULL,
    execucao_id             TEXT       NOT NULL,

    -- carimbo da própria etapa Silver
    data_hora_padronizacao  TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_silver_conteudo_tipo
        CHECK (tipo IN ('Artigo', 'Curso', 'Podcast', 'Vídeo')),

    CONSTRAINT ck_silver_conteudo_categoria
        CHECK (categoria IN (
            'Banco de Dados',
            'Business Intelligence',
            'Ciência de Dados',
            'DevOps & Cloud',
            'Engenharia de Dados',
            'Inteligência Artificial',
            'Programação & Software',
            'Segurança & Governança'
        )),

    CONSTRAINT ck_silver_conteudo_nivel
        CHECK (nivel IN ('Básico', 'Intermediário', 'Avançado')),

    CONSTRAINT ck_silver_conteudo_carga
        CHECK (carga_horaria_min IS NULL OR carga_horaria_min >= 0)
);

CREATE INDEX IF NOT EXISTS ix_silver_conteudo_categoria ON silver.conteudo (categoria);
CREATE INDEX IF NOT EXISTS ix_silver_conteudo_tipo      ON silver.conteudo (tipo);

-- -------------------------------------------------------
-- 3. silver.interacao
-- Origem: bronze.interacoes. Chave de negócio: (usuario_id, conteudo_id,
-- data_hora) — dedupe = 1ª ocorrência. conteudo_id/usuario_id sem
-- correspondência em silver.conteudo/silver.usuario => REFERENCIA_INEXISTENTE
-- (quarentena), nunca descarte silencioso (RF21/RF23).
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.interacao (
    interacao_id            BIGSERIAL      PRIMARY KEY,
    usuario_id               INTEGER       NOT NULL,
    conteudo_id               INTEGER      NOT NULL,
    tipo_interacao             TEXT        NOT NULL,
    data_hora                   TIMESTAMP  NOT NULL,
    tempo_consumido               INTEGER,
    percentual_conclusao          NUMERIC(5, 2) NOT NULL,
    avaliacao_atribuida            SMALLINT,

    origem                        TEXT      NOT NULL,
    arquivo_origem                TEXT      NOT NULL,
    data_hora_ingestao            TIMESTAMP NOT NULL,
    execucao_id                   TEXT      NOT NULL,

    data_hora_padronizacao        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_silver_interacao_usuario
        CHECK (usuario_id > 0),

    CONSTRAINT fk_silver_interacao_conteudo
        FOREIGN KEY (conteudo_id)
        REFERENCES silver.conteudo (conteudo_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_silver_interacao_chave_negocio
        UNIQUE (usuario_id, conteudo_id, data_hora),

    CONSTRAINT ck_silver_interacao_tipo
        CHECK (tipo_interacao IN (
            'avaliação',
            'compartilhamento',
            'conclusão',
            'curtida',
            'início',
            'visualização'
        )),

    CONSTRAINT ck_silver_interacao_tempo
        CHECK (tempo_consumido IS NULL OR tempo_consumido >= 0),

    CONSTRAINT ck_silver_interacao_percentual
        CHECK (percentual_conclusao >= 0 AND percentual_conclusao <= 100),

    CONSTRAINT ck_silver_interacao_avaliacao
        CHECK (
            avaliacao_atribuida IS NULL
            OR (avaliacao_atribuida BETWEEN 1 AND 5)
        )
);

CREATE INDEX IF NOT EXISTS ix_silver_interacao_usuario   ON silver.interacao (usuario_id);
CREATE INDEX IF NOT EXISTS ix_silver_interacao_conteudo  ON silver.interacao (conteudo_id);
CREATE INDEX IF NOT EXISTS ix_silver_interacao_tipo      ON silver.interacao (tipo_interacao);
CREATE INDEX IF NOT EXISTS ix_silver_interacao_data_hora ON silver.interacao (data_hora);

-- -------------------------------------------------------
-- 4. silver.comentario
-- Origem: bronze.comentarios. Chave de negócio: (usuario_id, conteudo_id,
-- data) — dedupe = 1ª ocorrência. Mesmas regras de referência do item 3.
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver.comentario (
    comentario_id           BIGSERIAL     PRIMARY KEY,
    usuario_id                INTEGER     NOT NULL,
    conteudo_id                 INTEGER   NOT NULL,
    avaliacao                     SMALLINT,
    comentario                     TEXT,
    -- Guardado como texto JSON (ex. '["docker","spark"]'), não TEXT[] nativo:
    -- mesma convenção do Bronze (ver sql/criar_esquema_bronze.sql), evita
    -- depender do driver JDBC do Hop lidar com array nativo do Postgres.
    tags                              TEXT     NOT NULL DEFAULT '[]',
    data                                DATE     NOT NULL,

    origem                             TEXT      NOT NULL,
    arquivo_origem                     TEXT      NOT NULL,
    data_hora_ingestao                 TIMESTAMP NOT NULL,
    execucao_id                        TEXT      NOT NULL,

    data_hora_padronizacao             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_silver_comentario_usuario
        CHECK (usuario_id > 0),

    CONSTRAINT fk_silver_comentario_conteudo
        FOREIGN KEY (conteudo_id)
        REFERENCES silver.conteudo (conteudo_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_silver_comentario_chave_negocio
        UNIQUE (usuario_id, conteudo_id, data),

    CONSTRAINT ck_silver_comentario_avaliacao
        CHECK (avaliacao IS NULL OR (avaliacao BETWEEN 1 AND 5))
);

CREATE INDEX IF NOT EXISTS ix_silver_comentario_usuario  ON silver.comentario (usuario_id);
CREATE INDEX IF NOT EXISTS ix_silver_comentario_conteudo ON silver.comentario (conteudo_id);
CREATE INDEX IF NOT EXISTS ix_silver_comentario_data     ON silver.comentario (data);

-- -------------------------------------------------------
-- 5. quarentena.registro
-- Tabela única para as três fontes (RF23). Uma linha por violação
-- detectada; a mesma chave de negócio pode aparecer de novo em outra
-- execução até ser corrigida (por isso não há UNIQUE em registro_id).
-- payload_original guarda a linha Bronze completa para permitir corrigir e
-- reenviar ao Silver sem reconsultar a fonte. Fica em TEXT (JSON serializado),
-- não JSONB: o driver JDBC do Hop faz bind como character varying e o
-- Postgres não converte varchar->jsonb implicitamente no INSERT parametrizado
-- (erro confirmado em teste real via Table Output). Quem precisar consultar
-- campos do payload usa payload_original::jsonb na própria query.
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS quarentena.registro (
    id                  BIGSERIAL  PRIMARY KEY,
    registro_id         TEXT       NOT NULL,
    origem               TEXT      NOT NULL,
    regra_violada         TEXT     NOT NULL,
    data                   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    mensagem                TEXT    NOT NULL,
    execucao_id              TEXT   NOT NULL,
    payload_original          TEXT  NOT NULL,
    status                     TEXT NOT NULL DEFAULT 'pendente',

    CONSTRAINT ck_quarentena_origem
        CHECK (origem IN ('catalogo', 'interacoes', 'comentarios')),

    CONSTRAINT ck_quarentena_status
        CHECK (status IN ('pendente', 'reprocessado', 'descartado'))
);

CREATE INDEX IF NOT EXISTS ix_quarentena_origem        ON quarentena.registro (origem);
CREATE INDEX IF NOT EXISTS ix_quarentena_regra_violada ON quarentena.registro (regra_violada);
CREATE INDEX IF NOT EXISTS ix_quarentena_status        ON quarentena.registro (status);
CREATE INDEX IF NOT EXISTS ix_quarentena_execucao_id   ON quarentena.registro (execucao_id);
CREATE INDEX IF NOT EXISTS ix_quarentena_registro_id   ON quarentena.registro (registro_id);

COMMIT;
