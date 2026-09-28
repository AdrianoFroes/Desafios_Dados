-- RF26 — camada Gold para o SQL Lab e o Apache Superset.
-- Fonte: silver.* (nunca bronze.*). Recomendações do Desafio 1: public.recomendacao.
-- Aplicar este arquivo uma vez, depois de sql/qualidade.sql.
-- O workflow Hop chama gold.publicar(execucao_id). A função recusa a carga
-- quando a qualidade crítica dessa execução não liberou o lote.
--
-- Contrato para o Estudante 3
-- ----------------------------
-- gold.dim_conteudo
--   grão: 1 linha por conteudo_id
--   chave: conteudo_id
-- gold.fato_engajamento_dia
--   grão: conteudo_id + dia (data_hora::date da Silver)
--   chave: (conteudo_id, data)
--   conclusao = tipo_interacao 'conclusão' OU percentual_conclusao >= 100
--     (mesma regra de documentacao/kpis.md e de beam/pipeline.py)
-- gold.kpi_desempenho_categoria
--   grão: categoria + tipo
--   taxa_conclusao_pct = 100 * conclusoes / interacoes de inicio ou visualizacao
-- gold.kpi_engajamento_formato
--   grão: tipo do conteúdo (formato)
-- gold.kpi_evolucao_dia
--   grão: 1 linha por dia
--   usuarios_ativos = usuários distintos com interação naquele dia
-- gold.kpi_geral
--   grão: 1 linha da plataforma
--   usuarios_ativos = COUNT(DISTINCT usuario_id) em silver.interacao
-- gold.kpi_conversao_recomendacao
--   grão: 1 linha do último lote de public.recomendacao
--   conversao = recomendação do último lote com interação do mesmo usuário e conteúdo
--     em silver.interacao (visualização, início, conclusão ou curtida).
--     A mesma regra de vw_kpi_conversao_recomendacoes. O carimbo gerado_em deste
--     lote é posterior a todas as interações, então um filtro "data_hora >= gerado_em"
--     zeraria o indicador.
--
-- usuario_id não entra nas tabelas de consumo. A Gold guarda a contagem.

BEGIN;

CREATE SCHEMA IF NOT EXISTS gold;

CREATE TABLE IF NOT EXISTS gold.dim_conteudo (
    conteudo_id             INTEGER PRIMARY KEY,
    titulo                  TEXT,
    tipo                    TEXT NOT NULL,
    categoria               TEXT NOT NULL,
    nivel                   TEXT NOT NULL,
    carga_horaria_min       INTEGER,
    data_publicacao         DATE,
    autor                   TEXT,
    origem                  TEXT NOT NULL,
    arquivo_origem          TEXT NOT NULL,
    data_hora_ingestao      TIMESTAMP NOT NULL,
    execucao_id_silver      TEXT NOT NULL,
    data_hora_padronizacao  TIMESTAMP NOT NULL,
    execucao_id             TEXT NOT NULL,
    publicado_em            TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS gold.fato_engajamento_dia (
    conteudo_id         INTEGER NOT NULL,
    data                DATE NOT NULL,
    total_interacoes    INTEGER NOT NULL,
    visualizacoes       INTEGER NOT NULL,
    inicios             INTEGER NOT NULL,
    conclusoes          INTEGER NOT NULL,
    curtidas            INTEGER NOT NULL,
    avaliacoes          INTEGER NOT NULL,
    soma_avaliacao      INTEGER NOT NULL,
    tempo_total_min     INTEGER NOT NULL,
    execucao_id         TEXT NOT NULL,
    publicado_em        TIMESTAMP NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT pk_fato_engajamento_dia PRIMARY KEY (conteudo_id, data),
    CONSTRAINT fk_fato_engajamento_conteudo
        FOREIGN KEY (conteudo_id) REFERENCES gold.dim_conteudo (conteudo_id)
);

CREATE TABLE IF NOT EXISTS gold.kpi_desempenho_categoria (
    categoria           TEXT NOT NULL,
    tipo                TEXT NOT NULL,
    qtd_conteudos       INTEGER NOT NULL,
    total_interacoes    INTEGER NOT NULL,
    visualizacoes       INTEGER NOT NULL,
    inicios             INTEGER NOT NULL,
    conclusoes          INTEGER NOT NULL,
    taxa_conclusao_pct  NUMERIC(8, 2),
    avaliacao_media     NUMERIC(5, 2),
    tempo_medio_min     NUMERIC(10, 1),
    execucao_id         TEXT NOT NULL,
    publicado_em        TIMESTAMP NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT pk_kpi_desempenho_categoria PRIMARY KEY (categoria, tipo)
);

CREATE TABLE IF NOT EXISTS gold.kpi_engajamento_formato (
    formato                     TEXT PRIMARY KEY,
    qtd_conteudos               INTEGER NOT NULL,
    total_interacoes            INTEGER NOT NULL,
    visualizacoes               INTEGER NOT NULL,
    inicios                     INTEGER NOT NULL,
    conclusoes                  INTEGER NOT NULL,
    taxa_conclusao_pct          NUMERIC(8, 2),
    avaliacao_media             NUMERIC(5, 2),
    tempo_medio_min             NUMERIC(10, 1),
    carga_horaria_media_min     NUMERIC(10, 1),
    execucao_id                 TEXT NOT NULL,
    publicado_em                TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS gold.kpi_evolucao_dia (
    data                DATE PRIMARY KEY,
    total_interacoes    INTEGER NOT NULL,
    usuarios_ativos     INTEGER NOT NULL,
    conclusoes          INTEGER NOT NULL,
    avaliacao_media     NUMERIC(5, 2),
    tempo_total_min     INTEGER NOT NULL,
    execucao_id         TEXT NOT NULL,
    publicado_em        TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS gold.kpi_geral (
    id                              SMALLINT PRIMARY KEY DEFAULT 1,
    usuarios_ativos                 INTEGER NOT NULL,
    total_conteudos                 INTEGER NOT NULL,
    total_interacoes                INTEGER NOT NULL,
    taxa_conclusao_pct              NUMERIC(8, 2),
    avaliacao_media                 NUMERIC(5, 2),
    tempo_medio_min                 NUMERIC(10, 1),
    total_recomendacoes             INTEGER NOT NULL,
    taxa_conversao_recomendacao_pct NUMERIC(8, 2),
    execucao_id                     TEXT NOT NULL,
    publicado_em                    TIMESTAMP NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_kpi_geral_uma_linha CHECK (id = 1)
);

CREATE TABLE IF NOT EXISTS gold.kpi_conversao_recomendacao (
    id                              SMALLINT PRIMARY KEY DEFAULT 1,
    total_recomendacoes             INTEGER NOT NULL,
    recomendacoes_com_interacao     INTEGER NOT NULL,
    taxa_conversao_pct              NUMERIC(8, 2),
    lote_gerado_em                  TIMESTAMP,
    execucao_id                     TEXT NOT NULL,
    publicado_em                    TIMESTAMP NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_kpi_conversao_uma_linha CHECK (id = 1)
);

CREATE OR REPLACE FUNCTION gold.publicar(p_execucao_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id TEXT;
    v_total_rec INTEGER := 0;
    v_consumidas INTEGER := 0;
    v_taxa NUMERIC(8, 2);
    v_lote TIMESTAMP;
BEGIN
    v_id := qualidade._validar_execucao(p_execucao_id);
    PERFORM qualidade.bloquear_se_critico(v_id);

    TRUNCATE
        gold.fato_engajamento_dia,
        gold.kpi_desempenho_categoria,
        gold.kpi_engajamento_formato,
        gold.kpi_evolucao_dia,
        gold.kpi_geral,
        gold.kpi_conversao_recomendacao,
        gold.dim_conteudo;

    INSERT INTO gold.dim_conteudo (
        conteudo_id, titulo, tipo, categoria, nivel, carga_horaria_min,
        data_publicacao, autor, origem, arquivo_origem, data_hora_ingestao,
        execucao_id_silver, data_hora_padronizacao, execucao_id
    )
    SELECT
        conteudo_id, titulo, tipo, categoria, nivel, carga_horaria_min,
        data_publicacao, autor, origem, arquivo_origem, data_hora_ingestao,
        execucao_id, data_hora_padronizacao, v_id
    FROM silver.conteudo;

    INSERT INTO gold.fato_engajamento_dia (
        conteudo_id, data, total_interacoes, visualizacoes, inicios, conclusoes,
        curtidas, avaliacoes, soma_avaliacao, tempo_total_min, execucao_id
    )
    SELECT
        conteudo_id,
        data_hora::date,
        COUNT(*)::INTEGER,
        COUNT(*) FILTER (WHERE tipo_interacao = 'visualização')::INTEGER,
        COUNT(*) FILTER (WHERE tipo_interacao = 'início')::INTEGER,
        COUNT(*) FILTER (
            WHERE tipo_interacao = 'conclusão' OR percentual_conclusao >= 100
        )::INTEGER,
        COUNT(*) FILTER (WHERE tipo_interacao = 'curtida')::INTEGER,
        COUNT(*) FILTER (WHERE avaliacao_atribuida IS NOT NULL)::INTEGER,
        COALESCE(SUM(avaliacao_atribuida), 0)::INTEGER,
        COALESCE(SUM(tempo_consumido), 0)::INTEGER,
        v_id
    FROM silver.interacao
    GROUP BY conteudo_id, data_hora::date;

    INSERT INTO gold.kpi_desempenho_categoria (
        categoria, tipo, qtd_conteudos, total_interacoes, visualizacoes, inicios,
        conclusoes, taxa_conclusao_pct, avaliacao_media, tempo_medio_min, execucao_id
    )
    SELECT
        c.categoria,
        c.tipo,
        COUNT(DISTINCT c.conteudo_id)::INTEGER,
        COUNT(i.interacao_id)::INTEGER,
        COUNT(i.interacao_id) FILTER (WHERE i.tipo_interacao = 'visualização')::INTEGER,
        COUNT(i.interacao_id) FILTER (WHERE i.tipo_interacao = 'início')::INTEGER,
        COUNT(i.interacao_id) FILTER (
            WHERE i.tipo_interacao = 'conclusão' OR i.percentual_conclusao >= 100
        )::INTEGER,
        ROUND(
            100.0 * COUNT(i.interacao_id) FILTER (
                WHERE i.tipo_interacao = 'conclusão' OR i.percentual_conclusao >= 100
            ) / NULLIF(
                COUNT(i.interacao_id) FILTER (
                    WHERE i.tipo_interacao IN ('início', 'visualização')
                ),
                0
            ),
            2
        ),
        ROUND(AVG(i.avaliacao_atribuida), 2),
        ROUND(AVG(i.tempo_consumido), 1),
        v_id
    FROM silver.conteudo c
    LEFT JOIN silver.interacao i ON i.conteudo_id = c.conteudo_id
    GROUP BY c.categoria, c.tipo;

    INSERT INTO gold.kpi_engajamento_formato (
        formato, qtd_conteudos, total_interacoes, visualizacoes, inicios, conclusoes,
        taxa_conclusao_pct, avaliacao_media, tempo_medio_min, carga_horaria_media_min,
        execucao_id
    )
    SELECT
        c.tipo,
        COUNT(DISTINCT c.conteudo_id)::INTEGER,
        COUNT(i.interacao_id)::INTEGER,
        COUNT(i.interacao_id) FILTER (WHERE i.tipo_interacao = 'visualização')::INTEGER,
        COUNT(i.interacao_id) FILTER (WHERE i.tipo_interacao = 'início')::INTEGER,
        COUNT(i.interacao_id) FILTER (
            WHERE i.tipo_interacao = 'conclusão' OR i.percentual_conclusao >= 100
        )::INTEGER,
        ROUND(
            100.0 * COUNT(i.interacao_id) FILTER (
                WHERE i.tipo_interacao = 'conclusão' OR i.percentual_conclusao >= 100
            ) / NULLIF(
                COUNT(i.interacao_id) FILTER (
                    WHERE i.tipo_interacao IN ('início', 'visualização')
                ),
                0
            ),
            2
        ),
        ROUND(AVG(i.avaliacao_atribuida), 2),
        ROUND(AVG(i.tempo_consumido), 1),
        ROUND(AVG(c.carga_horaria_min), 1),
        v_id
    FROM silver.conteudo c
    LEFT JOIN silver.interacao i ON i.conteudo_id = c.conteudo_id
    GROUP BY c.tipo;

    INSERT INTO gold.kpi_evolucao_dia (
        data, total_interacoes, usuarios_ativos, conclusoes,
        avaliacao_media, tempo_total_min, execucao_id
    )
    SELECT
        data_hora::date,
        COUNT(*)::INTEGER,
        COUNT(DISTINCT usuario_id)::INTEGER,
        COUNT(*) FILTER (
            WHERE tipo_interacao = 'conclusão' OR percentual_conclusao >= 100
        )::INTEGER,
        ROUND(AVG(avaliacao_atribuida), 2),
        COALESCE(SUM(tempo_consumido), 0)::INTEGER,
        v_id
    FROM silver.interacao
    GROUP BY data_hora::date;

    IF to_regclass('public.recomendacao') IS NOT NULL THEN
        SELECT MAX(gerado_em) INTO v_lote FROM public.recomendacao;

        SELECT COUNT(*)::INTEGER
        INTO v_total_rec
        FROM public.recomendacao
        WHERE gerado_em = v_lote;

        SELECT COUNT(*)::INTEGER
        INTO v_consumidas
        FROM public.recomendacao r
        WHERE r.gerado_em = v_lote
          AND EXISTS (
              SELECT 1
              FROM silver.interacao i
              WHERE i.usuario_id = r.usuario_id
                AND i.conteudo_id = r.conteudo_id
                AND i.tipo_interacao IN (
                    'visualização', 'início', 'conclusão', 'curtida'
                )
          );
    END IF;

    v_taxa := ROUND(100.0 * v_consumidas / NULLIF(v_total_rec, 0), 2);

    INSERT INTO gold.kpi_conversao_recomendacao (
        id, total_recomendacoes, recomendacoes_com_interacao,
        taxa_conversao_pct, lote_gerado_em, execucao_id
    ) VALUES (
        1, v_total_rec, v_consumidas, v_taxa, v_lote, v_id
    );

    INSERT INTO gold.kpi_geral (
        id, usuarios_ativos, total_conteudos, total_interacoes,
        taxa_conclusao_pct, avaliacao_media, tempo_medio_min,
        total_recomendacoes, taxa_conversao_recomendacao_pct, execucao_id
    )
    SELECT
        1,
        (SELECT COUNT(DISTINCT usuario_id)::INTEGER FROM silver.interacao),
        (SELECT COUNT(*)::INTEGER FROM silver.conteudo),
        (SELECT COUNT(*)::INTEGER FROM silver.interacao),
        (
            SELECT ROUND(
                100.0 * COUNT(*) FILTER (
                    WHERE tipo_interacao = 'conclusão' OR percentual_conclusao >= 100
                ) / NULLIF(
                    COUNT(*) FILTER (WHERE tipo_interacao IN ('início', 'visualização')),
                    0
                ),
                2
            )
            FROM silver.interacao
        ),
        (SELECT ROUND(AVG(avaliacao_atribuida), 2) FROM silver.interacao),
        (SELECT ROUND(AVG(tempo_consumido), 1) FROM silver.interacao),
        v_total_rec,
        v_taxa,
        v_id;

    RETURN 'publicado';
END;
$$;

COMMIT;
