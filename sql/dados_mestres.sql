-- RF30 — dados mestres da entidade CONTEÚDO.
-- Fonte de referência: silver.conteudo (catálogo já padronizado pelo Hop).
-- Chave de negócio na origem: conteudo_id.
-- Atributos essenciais: titulo, tipo, categoria, nivel, carga_horaria_min, data_publicacao.
--
-- Correspondência (match): dois conteúdos são o MESMO item quando têm
--   título normalizado igual (minúsculo, sem acento, espaços simples)
--   + mesmo tipo + mesmo autor.
--   Título igual com autor diferente é outro conteúdo (há 158 títulos repetidos
--   no catálogo e só 11 grupos com o mesmo autor).
-- Deduplicação: cada grupo vira um único mestre_id = 'CNT-' || menor conteudo_id.
-- Sobrevivência, por atributo:
--   titulo, tipo, categoria      do registro de menor conteudo_id (primeiro cadastro)
--   nivel, carga_horaria_min,
--   data_publicacao              do registro com data_publicacao mais recente
--                                (versão mais nova do material); empate -> maior conteudo_id
--   nulos nunca sobrevivem se outro registro do grupo tiver o valor.
-- Tabela de correspondência: mestres.correspondencia_conteudo (conteudo_id -> mestre_id).
-- Aplicar depois da Silver. Uso: CALL mestres.consolidar();

BEGIN;

CREATE SCHEMA IF NOT EXISTS mestres;

CREATE OR REPLACE FUNCTION mestres.normalizar(valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(regexp_replace(lower(translate(btrim(valor),
        'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç',
        'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc')), '\s+', ' ', 'g'), '');
$$;

-- De-para de categoria: cada grafia encontrada no Bronze aponta para a canônica.
CREATE TABLE IF NOT EXISTS mestres.categoria_depara (
    valor_origem        TEXT PRIMARY KEY,
    categoria_canonica  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mestres.conteudo_mestre (
    mestre_id           TEXT PRIMARY KEY,
    titulo              TEXT,
    tipo                TEXT NOT NULL,
    categoria           TEXT NOT NULL,
    nivel               TEXT NOT NULL,
    carga_horaria_min   INTEGER,
    data_publicacao     DATE,
    qtd_registros       INTEGER NOT NULL,
    consolidado_em      TIMESTAMP NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS mestres.correspondencia_conteudo (
    conteudo_id   INTEGER PRIMARY KEY,
    mestre_id     TEXT NOT NULL REFERENCES mestres.conteudo_mestre (mestre_id) ON DELETE CASCADE,
    regra_match   TEXT NOT NULL,
    sobrevivente  BOOLEAN NOT NULL
);

CREATE OR REPLACE PROCEDURE mestres.consolidar()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE mestres.correspondencia_conteudo, mestres.conteudo_mestre, mestres.categoria_depara;

    INSERT INTO mestres.categoria_depara (valor_origem, categoria_canonica)
    SELECT DISTINCT btrim(b.categoria), c.categoria
    FROM bronze.catalogo b
    JOIN silver.conteudo c
      ON btrim(b.conteudo_id) ~ '^\d+$' AND btrim(b.conteudo_id)::INTEGER = c.conteudo_id
    WHERE b.categoria IS NOT NULL AND btrim(b.categoria) <> ''
    ON CONFLICT (valor_origem) DO NOTHING;

    DROP TABLE IF EXISTS _grupo;
    CREATE TEMP TABLE _grupo ON COMMIT DROP AS
    SELECT c.*,
           'CNT-' || lpad(MIN(c.conteudo_id) OVER w::TEXT, 5, '0') AS mestre_id,
           COUNT(*) OVER w AS tamanho,
           ROW_NUMBER() OVER (PARTITION BY mestres.normalizar(c.titulo), c.tipo, mestres.normalizar(c.autor)
                              ORDER BY c.conteudo_id) AS ordem_cadastro,
           ROW_NUMBER() OVER (PARTITION BY mestres.normalizar(c.titulo), c.tipo, mestres.normalizar(c.autor)
                              ORDER BY c.data_publicacao DESC NULLS LAST, c.conteudo_id DESC) AS ordem_recencia
    FROM silver.conteudo c
    WINDOW w AS (PARTITION BY mestres.normalizar(c.titulo), c.tipo, mestres.normalizar(c.autor));

    INSERT INTO mestres.conteudo_mestre (
        mestre_id, titulo, tipo, categoria, nivel, carga_horaria_min, data_publicacao, qtd_registros
    )
    SELECT
        g.mestre_id,
        MAX(g.titulo)    FILTER (WHERE g.ordem_cadastro = 1),
        MAX(g.tipo)      FILTER (WHERE g.ordem_cadastro = 1),
        MAX(g.categoria) FILTER (WHERE g.ordem_cadastro = 1),
        MAX(g.nivel)     FILTER (WHERE g.ordem_recencia = 1),
        COALESCE(MAX(g.carga_horaria_min) FILTER (WHERE g.ordem_recencia = 1), MAX(g.carga_horaria_min)),
        COALESCE(MAX(g.data_publicacao)   FILTER (WHERE g.ordem_recencia = 1), MAX(g.data_publicacao)),
        MAX(g.tamanho)
    FROM _grupo g
    GROUP BY g.mestre_id;

    INSERT INTO mestres.correspondencia_conteudo (conteudo_id, mestre_id, regra_match, sobrevivente)
    SELECT conteudo_id, mestre_id,
           CASE WHEN tamanho = 1 THEN 'unico'
                ELSE 'titulo_normalizado+tipo+autor' END,
           ordem_cadastro = 1
    FROM _grupo;
END;
$$;

-- Registros conflitantes: grupos com mais de um conteudo_id e o valor que sobreviveu.
CREATE OR REPLACE VIEW mestres.vw_conflitos AS
SELECT
    m.mestre_id,
    c.conteudo_id,
    k.sobrevivente,
    c.titulo,
    c.tipo,
    c.categoria,
    c.nivel              AS nivel_origem,
    m.nivel              AS nivel_mestre,
    c.carga_horaria_min  AS carga_origem,
    m.carga_horaria_min  AS carga_mestre,
    c.data_publicacao    AS data_origem,
    m.data_publicacao    AS data_mestre
FROM mestres.correspondencia_conteudo k
JOIN mestres.conteudo_mestre m ON m.mestre_id = k.mestre_id
JOIN silver.conteudo c ON c.conteudo_id = k.conteudo_id
WHERE m.qtd_registros > 1
ORDER BY m.mestre_id, c.conteudo_id;

COMMIT;
