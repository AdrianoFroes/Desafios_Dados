-- RF23 — reprocessamento da quarentena para interações e comentários.
-- O catálogo é reprocessado por hop/pipelines/silver_reprocessar.hpl.
-- Aqui, cada registro pendente é relido do payload_original (linha Bronze
-- completa), passa pelas mesmas regras do contrato Silver e, se aprovado,
-- entra na Silver e vira 'reprocessado'. O que continua inválido segue
-- 'pendente'. Uso: SELECT * FROM quarentena.reprocessar_pendentes('reproc-1');

CREATE OR REPLACE FUNCTION quarentena.reprocessar_pendentes(p_execucao_id TEXT)
RETURNS TABLE (origem TEXT, reprocessados BIGINT, ainda_pendentes BIGINT)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
BEGIN
    -- interações
    WITH pend AS (
        SELECT DISTINCT ON (q.registro_id) q.id, q.registro_id, q.payload_original::jsonb AS p
        FROM quarentena.registro q
        WHERE q.status = 'pendente' AND q.origem = 'interacoes'
        ORDER BY q.registro_id, q.id DESC
    ),
    pad AS (
        SELECT id, registro_id, p,
            CASE WHEN BTRIM(p->>'usuario_id') ~ '^\d+$' AND BTRIM(p->>'usuario_id')::BIGINT > 0
                 THEN BTRIM(p->>'usuario_id')::INTEGER END AS usuario_id,
            CASE WHEN BTRIM(p->>'conteudo_id') ~ '^\d+$' THEN BTRIM(p->>'conteudo_id')::INTEGER END AS conteudo_id,
            CASE LOWER(BTRIM(p->>'tipo_interacao'))
                WHEN 'avaliacao' THEN 'avaliação' WHEN 'conclusao' THEN 'conclusão'
                WHEN 'inicio' THEN 'início' WHEN 'visualizacao' THEN 'visualização'
                ELSE LOWER(BTRIM(p->>'tipo_interacao')) END AS tipo_interacao,
            CASE WHEN BTRIM(p->>'data_hora') ~ '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}:\d{2})?$'
                 THEN REPLACE(BTRIM(p->>'data_hora'), ' ', 'T')::TIMESTAMP END AS data_hora,
            CASE WHEN BTRIM(p->>'tempo_consumido') ~ '^\d+(\.\d+)?$'
                 THEN ROUND((p->>'tempo_consumido')::NUMERIC)::INTEGER END AS tempo_consumido,
            CASE WHEN BTRIM(p->>'percentual_conclusao') ~ '^-?\d+(\.\d+)?$'
                 THEN ROUND((p->>'percentual_conclusao')::NUMERIC, 2) END AS percentual_conclusao,
            CASE WHEN BTRIM(p->>'avaliacao_atribuida') ~ '^-?\d+(\.\d+)?$'
                 THEN ROUND((p->>'avaliacao_atribuida')::NUMERIC)::INTEGER END AS avaliacao_atribuida
        FROM pend
    ),
    aprovados AS (
        SELECT a.* FROM pad a
        WHERE a.usuario_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM silver.conteudo c WHERE c.conteudo_id = a.conteudo_id)
          AND a.tipo_interacao IN ('avaliação','compartilhamento','conclusão','curtida','início','visualização')
          AND a.data_hora IS NOT NULL
          AND a.percentual_conclusao BETWEEN 0 AND 100
          AND (a.avaliacao_atribuida IS NULL OR a.avaliacao_atribuida BETWEEN 1 AND 5)
          AND NOT EXISTS (
              SELECT 1 FROM silver.interacao s
              WHERE s.usuario_id = a.usuario_id AND s.conteudo_id = a.conteudo_id AND s.data_hora = a.data_hora
          )
    ),
    ins AS (
        INSERT INTO silver.interacao (
            usuario_id, conteudo_id, tipo_interacao, data_hora, tempo_consumido,
            percentual_conclusao, avaliacao_atribuida, origem, arquivo_origem,
            data_hora_ingestao, execucao_id
        )
        SELECT usuario_id, conteudo_id, tipo_interacao, data_hora, tempo_consumido,
               percentual_conclusao, avaliacao_atribuida, p->>'origem', p->>'arquivo_origem',
               (p->>'data_hora_ingestao')::TIMESTAMP, p_execucao_id
        FROM aprovados
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    UPDATE quarentena.registro q SET status = 'reprocessado'
    WHERE q.origem = 'interacoes' AND q.status = 'pendente'
      AND q.registro_id IN (SELECT registro_id FROM aprovados);

    -- comentários
    WITH pend AS (
        SELECT DISTINCT ON (q.registro_id) q.id, q.registro_id, q.payload_original::jsonb AS p
        FROM quarentena.registro q
        WHERE q.status = 'pendente' AND q.origem = 'comentarios'
        ORDER BY q.registro_id, q.id DESC
    ),
    pad AS (
        SELECT id, registro_id, p,
            CASE WHEN BTRIM(p->>'usuario_id') ~ '^\d+$' AND BTRIM(p->>'usuario_id')::BIGINT > 0
                 THEN BTRIM(p->>'usuario_id')::INTEGER END AS usuario_id,
            CASE WHEN BTRIM(p->>'conteudo_id') ~ '^\d+$' THEN BTRIM(p->>'conteudo_id')::INTEGER END AS conteudo_id,
            NULLIF(BTRIM(p->>'avaliacao'), '') AS avaliacao_raw,
            CASE WHEN BTRIM(p->>'avaliacao') ~ '^-?\d+(\.\d+)?$'
                 THEN ROUND((p->>'avaliacao')::NUMERIC)::INTEGER END AS avaliacao,
            NULLIF(BTRIM(p->>'comentario'), '') AS comentario,
            silver.tags_normalizadas(p->>'tags') AS tags,
            CASE WHEN BTRIM(p->>'data') ~ '^\d{4}-\d{2}-\d{2}$' THEN BTRIM(p->>'data')::DATE END AS data
        FROM pend
    ),
    aprovados AS (
        SELECT a.* FROM pad a
        WHERE a.usuario_id IS NOT NULL
          AND EXISTS (SELECT 1 FROM silver.conteudo c WHERE c.conteudo_id = a.conteudo_id)
          AND a.data IS NOT NULL
          AND (a.avaliacao_raw IS NULL OR a.avaliacao BETWEEN 1 AND 5)
          AND NOT EXISTS (
              SELECT 1 FROM silver.comentario s
              WHERE s.usuario_id = a.usuario_id AND s.conteudo_id = a.conteudo_id AND s.data = a.data
          )
    ),
    ins AS (
        INSERT INTO silver.comentario (
            usuario_id, conteudo_id, avaliacao, comentario, tags, data,
            origem, arquivo_origem, data_hora_ingestao, execucao_id
        )
        SELECT usuario_id, conteudo_id, avaliacao, comentario, tags, data,
               p->>'origem', p->>'arquivo_origem', (p->>'data_hora_ingestao')::TIMESTAMP, p_execucao_id
        FROM aprovados
        ON CONFLICT DO NOTHING
        RETURNING 1
    )
    UPDATE quarentena.registro q SET status = 'reprocessado'
    WHERE q.origem = 'comentarios' AND q.status = 'pendente'
      AND q.registro_id IN (SELECT registro_id FROM aprovados);

    RETURN QUERY
    SELECT q.origem,
           COUNT(*) FILTER (WHERE q.status = 'reprocessado'),
           COUNT(*) FILTER (WHERE q.status = 'pendente')
    FROM quarentena.registro q
    WHERE q.origem IN ('interacoes', 'comentarios')
    GROUP BY q.origem
    ORDER BY q.origem;
END;
$$;
