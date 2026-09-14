"""
Módulo de Métricas e KPIs (RF12).
Cria e valida as visões SQL no PostgreSQL e consolida resumo analítico em JSON.
"""
import json
from decimal import Decimal
from pathlib import Path
from sqlalchemy import create_engine, text

from src.config import RAIZ_PROJETO, load_config, postgres_url
from src.logger import get_logger

CAMINHO_VIEWS_SQL = RAIZ_PROJETO / "sql" / "criar_views_kpi.sql"
CAMINHO_EXTRAS_SQL = RAIZ_PROJETO / "sql" / "criar_kpis_extras.sql"
CAMINHO_JSON_SAIDA = RAIZ_PROJETO / "dados" / "processados" / "kpis_resumo.json"


class DecimalEncoder(json.JSONEncoder):
    """Auxiliar para serializar Decimals e tipos numéricos do PostgreSQL."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


class GeradorKPIs:
    """Gerencia a criação de visões analíticas e o cálculo de indicadores."""

    def __init__(self, config=None):
        self.config = config or load_config()
        self.logger = get_logger(__name__)
        self.engine = create_engine(postgres_url(self.config))

    def aplicar_views(self):
        """Executa o DDL de criação das views analíticas no PostgreSQL."""
        if not CAMINHO_VIEWS_SQL.exists():
            raise FileNotFoundError(f"Arquivo DDL de views não encontrado: {CAMINHO_VIEWS_SQL}")

        ddl = CAMINHO_VIEWS_SQL.read_text(encoding="utf-8")
        self.logger.info("Aplicando visões SQL analíticas de KPIs (RF12)...")

        with self.engine.connect() as conn:
            conn.execute(text(ddl))
            conn.commit()

        if CAMINHO_EXTRAS_SQL.exists():
            self.logger.info("Aplicando visões e tabelas auxiliares de KPIs extras...")
            ddl_extras = CAMINHO_EXTRAS_SQL.read_text(encoding="utf-8")
            with self.engine.connect() as conn:
                conn.execute(text(ddl_extras))
                conn.commit()

        self.logger.info("Visões SQL aplicadas com sucesso.")

    def calcular_kpis(self):
        """Consulta as visões no PostgreSQL e consolida as métricas e KPIs."""
        self.logger.info("Calculando métricas operacionais e KPIs estratégicos...")

        with self.engine.connect() as conn:
            # 1. Métricas gerais (Headline)
            res_geral = conn.execute(text("SELECT * FROM vw_kpi_metricas_gerais")).mappings().first()
            metricas_gerais = dict(res_geral) if res_geral else {}

            # 2. Desempenho por categoria
            res_cat = conn.execute(text("""
                SELECT
                    categoria_nome,
                    tipo_conteudo,
                    qtd_conteudos,
                    total_interacoes,
                    taxa_conclusao_pct,
                    avaliacao_media
                FROM vw_kpi_desempenho_categoria
                ORDER BY total_interacoes DESC
            """)).mappings().all()
            desempenho_categoria = [dict(r) for r in res_cat]

            # 3. Evolução temporal (amostra dos últimos dias registrados)
            res_temp = conn.execute(text("""
                SELECT
                    data::text as data,
                    total_interacoes,
                    visualizacoes,
                    conclusoes,
                    avaliacao_media_dia
                FROM vw_kpi_evolucao_temporal
                ORDER BY data DESC
                LIMIT 10
            """)).mappings().all()
            evolucao_temporal = [dict(r) for r in res_temp]

            # 4. Recomendações resumo
            res_rec = conn.execute(text("""
                SELECT
                    categoria_nome,
                    classificacao,
                    qtd_recomendacoes,
                    pontuacao_media
                FROM vw_kpi_recomendacoes_resumo
                ORDER BY categoria_nome, classificacao
            """)).mappings().all()
            recomendacoes_resumo = [dict(r) for r in res_rec]

        resultado = {
            "metricas_operacionais": {
                "total_usuarios": metricas_gerais.get("total_usuarios", 0),
                "total_conteudos": metricas_gerais.get("total_conteudos", 0),
                "total_interacoes": metricas_gerais.get("total_interacoes", 0),
                "total_avaliacoes": metricas_gerais.get("total_avaliacoes", 0),
                "tempo_medio_consumo_min": metricas_gerais.get("tempo_medio_consumo_min", 0.0),
                "total_recomendacoes_lote": metricas_gerais.get("total_recomendacoes_lote", 0),
            },
            "kpis_estrategicos": {
                "taxa_conclusao_global_pct": metricas_gerais.get("taxa_conclusao_global_pct", 0.0),
                "avaliacao_media_global": metricas_gerais.get("avaliacao_media_global", 0.0),
                "taxa_recomendacoes_positivas_pct": metricas_gerais.get("taxa_recomendacoes_positivas_pct", 0.0),
            },
            "detalhes": {
                "desempenho_por_categoria": desempenho_categoria,
                "evolucao_temporal_recente": evolucao_temporal,
                "distribuicao_recomendacoes": recomendacoes_resumo,
            },
        }

        # Garante criação da pasta dados/processados
        CAMINHO_JSON_SAIDA.parent.mkdir(parents=True, exist_ok=True)
        with open(CAMINHO_JSON_SAIDA, "w", encoding="utf-8") as f:
            json.dump(resultado, f, indent=2, ensure_ascii=False, cls=DecimalEncoder)

        self.logger.info(f"Resumo de KPIs exportado para {CAMINHO_JSON_SAIDA}")
        self.logger.info(
            f"KPIs Consolidados -> Usuários: {metricas_gerais.get('total_usuarios')} | "
            f"Taxa Conclusão: {metricas_gerais.get('taxa_conclusao_global_pct')}% | "
            f"Avaliação Média: {metricas_gerais.get('avaliacao_media_global')} | "
            f"Recomendações Positivas: {metricas_gerais.get('taxa_recomendacoes_positivas_pct')}%"
        )
        return resultado

    def executar(self):
        """Pipeline completo do RF12."""
        self.aplicar_views()
        return self.calcular_kpis()


def main():
    gerador = GeradorKPIs()
    gerador.executar()


if __name__ == "__main__":
    main()
