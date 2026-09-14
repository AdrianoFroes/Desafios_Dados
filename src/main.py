"""
Ponto de entrada do pipeline.
Executado com: python -m src.main
Implementa a orquestração completa dos requisitos RF01 a RF12 e RF14.
"""
import sys
import time

from src.busca_semantica import BuscadorSemantico
from src.config import load_config
from src.embeddings import GeradorEmbeddings
from src.ingestao import Ingestor
from src.kpis import GeradorKPIs
from src.logger import get_logger
from src.persistencia import PersistenciaPostgres
from src.persistencia_mongo import PersistenciaMongo
from src.recomendacao import GeradorRecomendacoes
from src.tratamento import Tratador
from src.validacao import Validador


def main():
    inicio = time.time()
    logger = get_logger(__name__)
    tempos_etapas = {}

    logger.info("=" * 60)
    logger.info("INICIO DO PIPELINE - Plataforma Educacional")
    logger.info("=" * 60)

    try:
        t0 = time.time()
        config = load_config()
        tempos_etapas["configuracao"] = round(time.time() - t0, 3)

        # ---------- FASE 1: Ingestao (RF02) ----------
        logger.info("[FASE 1] Ingestao de dados (RF02)")
        t0 = time.time()
        ingestor = Ingestor()
        ingestor.processar()
        tempos_etapas["ingestao"] = round(time.time() - t0, 3)
        logger.info(f"Ingestao concluida em {tempos_etapas['ingestao']}s")

        # ---------- FASE 1: Validacao (RF03) ----------
        logger.info("[FASE 1] Validacao de dados (RF03)")
        t0 = time.time()
        validador = Validador()
        ids_conteudos = set(ingestor.df_catalogo["conteudo_id"].tolist())
        ids_usuarios = set(ingestor.df_interacoes["usuario_id"].tolist())
        validador.validar_catalogo(ingestor.df_catalogo)
        validador.validar_interacoes(ingestor.df_interacoes, ids_conteudos, ids_usuarios)
        validador.validar_comentarios(ingestor.lista_comentarios, ids_conteudos, ids_usuarios)
        tempos_etapas["validacao"] = round(time.time() - t0, 3)
        logger.info(f"Validacao concluida em {tempos_etapas['validacao']}s")

        # ---------- FASE 1: Tratamento (RF04) ----------
        logger.info("[FASE 1] Tratamento e padronizacao (RF04)")
        t0 = time.time()
        tratador = Tratador()
        df_catalogo = tratador.tratar_catalogo(ingestor.df_catalogo)
        df_interacoes = tratador.tratar_interacoes(ingestor.df_interacoes)
        df_comentarios = tratador.tratar_comentarios(ingestor.lista_comentarios)
        tempos_etapas["tratamento"] = round(time.time() - t0, 3)
        logger.info(f"Tratamento concluido em {tempos_etapas['tratamento']}s")

        # ---------- FASE 2: Persistencia PostgreSQL (RF06) ----------
        logger.info("[FASE 2] Persistencia PostgreSQL (RF06)")
        t0 = time.time()
        persistencia = PersistenciaPostgres()
        carregados_pg = persistencia.carregar(df_catalogo, df_interacoes)
        tempos_etapas["persistencia_postgres"] = round(time.time() - t0, 3)
        logger.info(
            f"Registros enviados ao PostgreSQL: {carregados_pg} (duracao: {tempos_etapas['persistencia_postgres']}s)"
        )

        # ---------- FASE 2: Persistencia MongoDB (RF07) ----------
        logger.info("[FASE 2] Persistencia MongoDB (RF07)")
        t0 = time.time()
        persistencia_mongo = PersistenciaMongo()
        try:
            carregados_mongo = persistencia_mongo.carregar(df_comentarios, df_catalogo)
        finally:
            persistencia_mongo.fechar()
        tempos_etapas["persistencia_mongo"] = round(time.time() - t0, 3)
        logger.info(
            f"Documentos enviados ao MongoDB: {carregados_mongo} (duracao: {tempos_etapas['persistencia_mongo']}s)"
        )

        # ---------- FASE 2: Embeddings (RF08) ----------
        logger.info("[FASE 2] Geracao de embeddings (RF08)")
        t0 = time.time()
        gerador_embeddings = GeradorEmbeddings()
        resultado_emb = gerador_embeddings.gerar()
        tempos_etapas["embeddings"] = round(time.time() - t0, 3)
        logger.info(
            f"Embeddings gerados/validados: {resultado_emb} (duracao: {tempos_etapas['embeddings']}s)"
        )

        # ---------- FASE 2: Busca semantica (RF09) ----------
        logger.info("[FASE 2] Busca semantica (RF09)")
        t0 = time.time()
        buscador = BuscadorSemantico(gerador=gerador_embeddings)
        resultado_busca = buscador.demonstrar()
        tempos_etapas["busca_semantica"] = round(time.time() - t0, 3)
        logger.info(
            f"Consultas semanticas demonstradas: {len(resultado_busca['consultas'])} (duracao: {tempos_etapas['busca_semantica']}s)"
        )

        # ---------- FASE 2: Recomendacao (RF10/RF11) ----------
        logger.info("[FASE 2] Geracao e persistencia de recomendacoes (RF10/RF11)")
        t0 = time.time()
        gerador_rec = GeradorRecomendacoes()
        resultado_rec = gerador_rec.gerar()
        tempos_etapas["recomendacoes"] = round(time.time() - t0, 3)
        logger.info(
            f"Recomendacoes geradas: {resultado_rec['resumo']['total']}, persistidas: "
            f"{resultado_rec['resumo'].get('persistidas', 0)} (duracao: {tempos_etapas['recomendacoes']}s)"
        )

        # ---------- FASE 2: Metricas e KPIs (RF12) ----------
        logger.info("[FASE 2] Producao de metricas e KPIs (RF12)")
        t0 = time.time()
        gerador_kpis = GeradorKPIs()
        resultado_kpis = gerador_kpis.executar()
        tempos_etapas["kpis"] = round(time.time() - t0, 3)
        logger.info(f"Metricas e KPIs aplicados com sucesso em {tempos_etapas['kpis']}s")

        # ---------- FASE 2: Resumo Consolidado (RF05/RF14) ----------
        logger.info("[FASE 2] Consolidando resumo da ingestao e registro de execucao (RF05/RF14)")
        resumo = ingestor.consolidar_resumo(
            relatorios_validacao=validador.get_relatorios(),
            corrigidos=tratador.get_corrigidos(),
            carregados_pg=carregados_pg,
            carregados_mongo=carregados_mongo,
            tempo=round(time.time() - inicio, 2),
            tempos_etapas=tempos_etapas,
        )
        logger.info("Resumo consolidado: " + str(resumo))

        # ---------- FASE 3: Dashboard e Gráficos no Apache Superset (RF13) ----------
        logger.info("[FASE 3] Provisionamento do Dashboard e Gráficos no Apache Superset (RF13)")
        t0 = time.time()
        try:
            from src.superset_dashboard import provisionar_dashboard
            provisionar_dashboard()
            tempos_etapas["superset_dashboard"] = round(time.time() - t0, 3)
            logger.info(f"Dashboard Superset provisionado em {tempos_etapas['superset_dashboard']}s")
        except Exception as e:
            logger.warning(f"Aviso no provisionamento do Superset: {e}. Pode ser provisionado com 'python -m src.superset_dashboard'.")

        duracao = round(time.time() - inicio, 2)
        logger.info("=" * 60)
        logger.info(f"FIM DO PIPELINE COM SUCESSO - duracao total: {duracao}s")
        logger.info("Tempos detalhados por etapa:")
        for etapa, tempo_s in tempos_etapas.items():
            logger.info(f"  - {etapa.ljust(25)}: {tempo_s:>6.2f}s")
        logger.info("=" * 60)
        return 0

    except ConnectionError as e:
        logger.error(
            f"[FALHA DE CONEXAO] Nao foi possivel conectar ao servico: {e}. "
            "Causa provavel: container Postgres/Mongo nao esta em execucao ou porta incorreta no .env."
        )
        return 1
    except Exception as e:
        logger.exception(
            f"Erro fatal no pipeline: {e}. "
            "Verifique a integridade dos dados brutos, credenciais no .env e schemas SQL."
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())