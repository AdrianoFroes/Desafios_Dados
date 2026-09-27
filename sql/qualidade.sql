-- RF31 — testes de qualidade sobre a Silver, antes da publicação na Gold.
-- Aplicar este arquivo uma vez no banco plataforma_educacional.
-- O workflow Hop chama qualidade.aplicar e, em seguida, qualidade.bloquear_se_critico.
--
-- A função aplicar grava o resultado e faz COMMIT junto com o pipeline.
-- A função bloquear_se_critico roda num segundo pipeline: se reprovar um teste
-- crítico, o Hop aborta e a Gold não publica. O resultado do teste permanece.

BEGIN;

CREATE SCHEMA IF NOT EXISTS qualidade;

CREATE TABLE IF NOT EXISTS qualidade.resultado (
    id              BIGSERIAL PRIMARY KEY,
    execucao_id     TEXT NOT NULL,
    fonte           TEXT NOT NULL,
    teste           TEXT NOT NULL,
    dimensao        TEXT NOT NULL,
    formula         TEXT NOT NULL,
    valor           NUMERIC NOT NULL,
    limite          NUMERIC NOT NULL,
    operador        TEXT NOT NULL,
    severidade      TEXT NOT NULL,
    aprovado        BOOLEAN NOT NULL,
    acao            TEXT NOT NULL,
    mensagem        TEXT NOT NULL,
    executado_em    TIMESTAMP NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT ck_qualidade_dimensao CHECK (
        dimensao IN ('completude', 'validade', 'unicidade', 'consistencia', 'integridade')
    ),
    CONSTRAINT ck_qualidade_severidade CHECK (
        severidade IN ('critica', 'alta', 'media')
    ),
    CONSTRAINT ck_qualidade_operador CHECK (operador IN ('>=', '<='))
);

CREATE INDEX IF NOT EXISTS ix_qualidade_resultado_execucao
    ON qualidade.resultado (execucao_id, teste);

-- Duas séries pedidas pelo RF31: completude do título e consistência da conclusão.
CREATE OR REPLACE VIEW qualidade.vw_evolucao AS
SELECT
    execucao_id,
    executado_em,
    teste,
    fonte,
    valor,
    limite,
    aprovado
FROM qualidade.resultado
WHERE teste IN ('completude_titulo', 'consistencia_conclusao');

CREATE OR REPLACE FUNCTION qualidade._validar_execucao(p_execucao_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_execucao_id IS NULL OR btrim(p_execucao_id) = '' THEN
        RAISE EXCEPTION 'execucao_id obrigatorio';
    END IF;
    IF p_execucao_id !~ '^[A-Za-z0-9_.:-]+$' THEN
        RAISE EXCEPTION 'execucao_id invalido: %', p_execucao_id;
    END IF;
    RETURN p_execucao_id;
END;
$$;

CREATE OR REPLACE FUNCTION qualidade.aplicar(p_execucao_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id TEXT;
    v_completude NUMERIC;
    v_validade NUMERIC;
    v_unicidade NUMERIC;
    v_consistencia NUMERIC;
    v_integridade NUMERIC;
    v_retorno TEXT;
BEGIN
    v_id := qualidade._validar_execucao(p_execucao_id);

    DELETE FROM qualidade.resultado WHERE execucao_id = v_id;

    SELECT CASE
        WHEN COUNT(*) = 0 THEN 0
        ELSE ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE titulo IS NOT NULL AND btrim(titulo) <> ''
            ) / COUNT(*),
            2
        )
    END
    INTO v_completude
    FROM silver.conteudo;

    SELECT COUNT(*) FILTER (
        WHERE percentual_conclusao < 0 OR percentual_conclusao > 100
    )
    INTO v_validade
    FROM silver.interacao;

    SELECT COUNT(*) - COUNT(DISTINCT (usuario_id, conteudo_id, data_hora))
    INTO v_unicidade
    FROM silver.interacao;

    SELECT COALESCE(
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE percentual_conclusao >= 100)
            / NULLIF(COUNT(*), 0),
            2
        ),
        100
    )
    INTO v_consistencia
    FROM silver.interacao
    WHERE tipo_interacao = 'conclusão';

    SELECT COUNT(*)
    INTO v_integridade
    FROM silver.comentario c
    LEFT JOIN silver.conteudo s ON s.conteudo_id = c.conteudo_id
    WHERE s.conteudo_id IS NULL;

    INSERT INTO qualidade.resultado (
        execucao_id, fonte, teste, dimensao, formula, valor, limite,
        operador, severidade, aprovado, acao, mensagem
    ) VALUES
    (
        v_id, 'silver.conteudo', 'completude_titulo', 'completude',
        '100 * conteudos com titulo preenchido / conteudos na silver.conteudo',
        v_completude, 99, '>=', 'alta', v_completude >= 99,
        'registrar ressalva; a Gold continua',
        'titulo e atributo essencial do conteudo'
    ),
    (
        v_id, 'silver.interacao', 'validade_percentual', 'validade',
        'interacoes com percentual_conclusao fora da faixa 0-100',
        v_validade, 0, '<=', 'critica', v_validade <= 0,
        'bloquear a publicacao na Gold',
        'percentual de conclusao precisa permanecer na faixa do contrato Silver'
    ),
    (
        v_id, 'silver.interacao', 'unicidade_interacao', 'unicidade',
        'linhas de silver.interacao menos a chave distinta (usuario_id, conteudo_id, data_hora)',
        v_unicidade, 0, '<=', 'critica', v_unicidade <= 0,
        'bloquear a publicacao na Gold',
        'a chave de negocio da interacao nao pode repetir na Silver'
    ),
    (
        v_id, 'silver.interacao', 'consistencia_conclusao', 'consistencia',
        '100 * interacoes do tipo conclusao com percentual >= 100 / interacoes do tipo conclusao',
        v_consistencia, 90, '>=', 'media', v_consistencia >= 90,
        'registrar ressalva; a Gold continua',
        'uma conclusao deveria corresponder a percentual 100'
    ),
    (
        v_id, 'silver.comentario', 'integridade_comentario_conteudo', 'integridade',
        'comentarios cujo conteudo_id nao existe em silver.conteudo',
        v_integridade, 0, '<=', 'critica', v_integridade <= 0,
        'bloquear a publicacao na Gold',
        'comentario aprovado precisa apontar para um conteudo mestre'
    );

    IF EXISTS (
        SELECT 1 FROM qualidade.resultado
        WHERE execucao_id = v_id AND NOT aprovado
    ) THEN
        v_retorno := 'sucesso com ressalvas';
    ELSE
        v_retorno := 'sucesso';
    END IF;

    RETURN v_retorno;
END;
$$;

CREATE OR REPLACE FUNCTION qualidade.bloquear_se_critico(p_execucao_id TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id TEXT;
    v_testes TEXT;
BEGIN
    v_id := qualidade._validar_execucao(p_execucao_id);

    IF NOT EXISTS (
        SELECT 1 FROM qualidade.resultado WHERE execucao_id = v_id
    ) THEN
        RAISE EXCEPTION
            'publicacao gold bloqueada: sem resultado de qualidade para %', v_id;
    END IF;

    SELECT string_agg(teste, ', ' ORDER BY teste)
    INTO v_testes
    FROM qualidade.resultado
    WHERE execucao_id = v_id
      AND severidade = 'critica'
      AND NOT aprovado;

    IF v_testes IS NOT NULL THEN
        RAISE EXCEPTION
            'publicacao gold bloqueada: teste critico reprovado (%) na execucao %',
            v_testes, v_id;
    END IF;

    RETURN 'liberado';
END;
$$;

COMMIT;
