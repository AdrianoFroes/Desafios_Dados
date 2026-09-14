import json
import os
import time
from superset.app import create_app

app = create_app()
with app.app_context():
    from superset import db, security_manager
    from superset.models.core import Database
    from superset.models.slice import Slice
    from superset.models.dashboard import Dashboard
    from superset.connectors.sqla.models import SqlaTable
    from sqlalchemy import create_engine, text

    # 1. Obter usuário admin
    admin = security_manager.find_user("admin")
    owners = [admin] if admin else []

    # 2. Conectar e aguardar PostgreSQL estar pronto
    pg_uri = "postgresql+psycopg2://postgres:postgres@postgres:5432/plataforma_educacional"
    print("Aguardando conexao com PostgreSQL...")
    engine_pg = None
    for tentativa in range(1, 16):
        try:
            engine_pg = create_engine(pg_uri)
            with engine_pg.connect() as conn:
                conn.execute(text("SELECT 1"))
            print(f"Conexao com PostgreSQL estabelecida com sucesso na tentativa {tentativa}.")
            break
        except Exception as e:
            print(f"Tentativa {tentativa}/15: PostgreSQL ainda nao disponivel ({e}). Aguardando 2s...")
            time.sleep(2)

    # 2.1 Garantir que as views e tabelas existam no PostgreSQL (para inicializacao do zero)
    if engine_pg:
        try:
            with engine_pg.connect() as conn:
                res = conn.execute(text("SELECT 1 FROM information_schema.views WHERE table_name = 'vw_kpi_metricas_gerais'")).first()
                if not res:
                    print("Views de KPI nao encontradas. Inicializando DDLs SQL...")
                    sql_files = [
                        "/app/sql/criar_tabelas.sql",
                        "/app/sql/criar_views_kpi.sql",
                        "/app/sql/criar_kpis_extras.sql"
                    ]
                    for sfile in sql_files:
                        if os.path.exists(sfile):
                            print(f"Executando {sfile} no PostgreSQL...")
                            with open(sfile, "r", encoding="utf-8") as f:
                                ddl_content = f.read()
                            conn.execute(text(ddl_content))
                            conn.commit()
                            print(f"{sfile} executado com sucesso.")
        except Exception as e:
            print(f"Aviso durante inicializacao automatica do schema SQL: {e}")

    # 2.2 Registrar conexao PostgreSQL no Superset
    db_name = "Plataforma Educacional (PostgreSQL)"
    db_obj = db.session.query(Database).filter_by(database_name=db_name).first()
    if not db_obj:
        db_obj = Database(database_name=db_name, sqlalchemy_uri=pg_uri)
        db.session.add(db_obj)
        db.session.commit()
        print(f"Banco '{db_name}' criado com id: {db_obj.id}")
    else:
        print(f"Banco '{db_name}' ja existe com id: {db_obj.id}")

    # 3. Registrar Datasets de todas as views (RF12 / RF13 + KPIs Extras)
    views_info = [
        ("vw_kpi_metricas_gerais", "Métricas Gerais da Plataforma"),
        ("vw_kpi_desempenho_categoria", "Desempenho por Categoria e Tipo"),
        ("vw_kpi_evolucao_temporal", "Evolução Temporal de Interações"),
        ("vw_kpi_analise_conteudos", "Análise Granular de Conteúdos"),
        ("vw_kpi_recomendacoes_resumo", "Resumo de Recomendações Vetoriais"),
        ("vw_kpi_seletividade_recomendacao", "Seletividade do Motor de Recomendação"),
        ("vw_kpi_recomendacoes_categoria_status", "Recomendações por Categoria e Status"),
        ("vw_kpi_qualidade_ingestao", "Qualidade e Correção na Ingestão"),
        ("vw_kpi_desempenho_categoria_tipo", "Desempenho Cruzado Categoria x Tipo"),
        ("vw_kpi_evolucao_temporal_diaria", "Evolução Temporal Diária"),
        ("vw_kpi_engajamento_formato", "Engajamento e Retenção por Formato"),
        ("vw_kpi_conversao_recomendacoes", "Taxa de Conversão de Recomendações")
    ]

    datasets = {}
    for table_name, desc in views_info:
        tbl = db.session.query(SqlaTable).filter_by(table_name=table_name, database_id=db_obj.id).first()
        if not tbl:
            tbl = SqlaTable(
                table_name=table_name,
                database_id=db_obj.id,
                schema="public",
                description=desc,
                owners=owners
            )
            db.session.add(tbl)
            db.session.commit()
            try:
                tbl.fetch_metadata()
                db.session.commit()
            except Exception as e:
                print(f"Aviso metadata para {table_name}: {e}")
            print(f"Dataset '{table_name}' criado com id: {tbl.id}")
        else:
            try:
                tbl.fetch_metadata()
                db.session.commit()
            except Exception as e:
                print(f"Aviso metadata para {table_name}: {e}")
            print(f"Dataset '{table_name}' sincronizado com id: {tbl.id}")
        datasets[table_name] = tbl

    # 4. Criar ou Atualizar Gráficos (Slices)
    def salvar_slice(nome, viz_type, datasource, params):
        s = db.session.query(Slice).filter_by(slice_name=nome).first()
        if not s:
            s = Slice(
                slice_name=nome,
                viz_type=viz_type,
                datasource_id=datasource.id,
                datasource_type="table",
                params=json.dumps(params, ensure_ascii=False),
                owners=owners
            )
            db.session.add(s)
            db.session.commit()
            print(f"Gráfico criado: {nome} (ID {s.id})")
        else:
            s.params = json.dumps(params, ensure_ascii=False)
            s.datasource_id = datasource.id
            s.viz_type = viz_type
            if owners:
                s.owners = owners
            db.session.commit()
            print(f"Gráfico atualizado: {nome} (ID {s.id})")
        return s

    # Slice 1: Total de Usuários Ativos
    s1 = salvar_slice(
        nome="Total de Usuários Ativos",
        viz_type="big_number_total",
        datasource=datasets["vw_kpi_metricas_gerais"],
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(total_usuarios)", "label": "Total Usuários"},
            "subheader": "Discentes ativos com interações",
            "y_axis_format": ",d"
        }
    )

    # Slice 2: Avaliação Média Global (CSAT)
    s2 = salvar_slice(
        nome="Avaliação Média Global (CSAT)",
        viz_type="big_number_total",
        datasource=datasets["vw_kpi_metricas_gerais"],
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(avaliacao_media_global)", "label": "Nota Média"},
            "subheader": "Escala de 1 a 5 estrelas",
            "y_axis_format": ".2f"
        }
    )

    # Slice 3: Taxa de Conclusão Global
    s3 = salvar_slice(
        nome="Taxa de Conclusão Global",
        viz_type="big_number_total",
        datasource=datasets["vw_kpi_metricas_gerais"],
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(taxa_conclusao_global_pct)", "label": "Taxa de Conclusão (%)"},
            "subheader": "Percentual de finalização de materiais",
            "y_axis_format": ".1f"
        }
    )

    # Slice 4: Taxa de Recomendações Positivas
    s4 = salvar_slice(
        nome="Taxa de Recomendações Positivas",
        viz_type="big_number_total",
        datasource=datasets["vw_kpi_metricas_gerais"],
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(taxa_recomendacoes_positivas_pct)", "label": "Afinidade Alta (%)"},
            "subheader": "Percentual de recomendações com score >= 70",
            "y_axis_format": ".1f"
        }
    )

    # Slice 5: Taxa de Seletividade do Motor
    s5 = salvar_slice(
        nome="Taxa de Seletividade do Motor",
        viz_type="big_number_total",
        datasource=datasets["vw_kpi_seletividade_recomendacao"],
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(taxa_seletividade_pct)", "label": "Seletividade (%)"},
            "subheader": "Pares persistidos vs 38.007 avaliados",
            "y_axis_format": ".2f"
        }
    )

    # Slice 6: Engajamento e Conclusões por Categoria (Barras Categóricas)
    s6 = salvar_slice(
        nome="Engajamento e Conclusões por Categoria",
        viz_type="dist_bar",
        datasource=datasets["vw_kpi_desempenho_categoria"],
        params={
            "viz_type": "dist_bar",
            "groupby": ["categoria_nome"],
            "columns": [],
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(total_interacoes)", "label": "Total Interações"},
                {"expressionType": "SQL", "sqlExpression": "SUM(conclusoes)", "label": "Total Conclusões"}
            ],
            "order_desc": True,
            "show_legend": True,
            "bar_stacked": False,
            "show_bar_value": False,
            "y_axis_format": ",d",
            "x_axis_label": "Categoria Temática",
            "y_axis_label": "Quantidade"
        }
    )

    # Slice 7: Evolução Temporal de Interações Diárias (Linhas)
    s7 = salvar_slice(
        nome="Evolução Temporal de Interações Diárias",
        viz_type="echarts_timeseries_line",
        datasource=datasets["vw_kpi_evolucao_temporal"],
        params={
            "x_axis": "data",
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(total_interacoes)", "label": "Interações Totais"},
                {"expressionType": "SQL", "sqlExpression": "SUM(visualizacoes)", "label": "Visualizações"}
            ],
            "y_axis_title": "Volume Diário"
        }
    )

    # Slice 8: Recomendações por Categoria e Volume (Barras Categóricas)
    s8 = salvar_slice(
        nome="Distribuição de Recomendações por Categoria",
        viz_type="dist_bar",
        datasource=datasets["vw_kpi_recomendacoes_categoria_status"],
        params={
            "viz_type": "dist_bar",
            "groupby": ["categoria_nome"],
            "columns": [],
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(qtd_recomendacoes)", "label": "Qtd Recomendações"}
            ],
            "order_desc": True,
            "show_legend": False,
            "bar_stacked": False,
            "show_bar_value": True,
            "y_axis_format": ",d",
            "x_axis_label": "Categoria",
            "y_axis_label": "Recomendações Geradas"
        }
    )

    # Slice 9: Engajamento por Formato de Conteúdo (Barras Categóricas)
    s9 = salvar_slice(
        nome="Engajamento e Retenção por Formato de Conteúdo",
        viz_type="dist_bar",
        datasource=datasets["vw_kpi_engajamento_formato"],
        params={
            "viz_type": "dist_bar",
            "groupby": ["formato_conteudo"],
            "columns": [],
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(total_interacoes)", "label": "Interações"},
                {"expressionType": "SQL", "sqlExpression": "SUM(conclusoes)", "label": "Conclusões"}
            ],
            "order_desc": True,
            "show_legend": True,
            "bar_stacked": False,
            "show_bar_value": False,
            "y_axis_format": ",d",
            "x_axis_label": "Formato Didático",
            "y_axis_label": "Volume"
        }
    )

    # Slice 10: Tabela de Qualidade e Conformidade da Ingestão
    s10 = salvar_slice(
        nome="Controle de Qualidade e Higienização da Ingestão",
        viz_type="table",
        datasource=datasets["vw_kpi_qualidade_ingestao"],
        params={
            "all_columns": [
                "fonte",
                "lidos",
                "validos",
                "corrigidos",
                "taxa_correcao_pct",
                "taxa_conformidade_pct"
            ],
            "order_by_cols": [],
            "query_mode": "raw",
            "row_limit": 50,
            "show_cell_bars": False
        }
    )

    all_slices = [s1, s2, s3, s4, s5, s6, s7, s8, s9, s10]

    # 5. Criar Layout v2 Válido e Hierárquico no Dashboard
    pos = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {
            "children": ["GRID_ID"],
            "id": "ROOT_ID",
            "type": "ROOT"
        },
        "HEADER_ID": {
            "id": "HEADER_ID",
            "meta": {"text": "Plataforma Educacional — Painel Executivo de KPIs e Recomendações"},
            "type": "HEADER"
        },
        "GRID_ID": {
            "children": ["ROW-CARDS", "ROW-CHARTS-1", "ROW-CHARTS-2", "ROW-TABLE"],
            "id": "GRID_ID",
            "parents": ["ROOT_ID"],
            "type": "GRID"
        },
        # Linha 1: 5 Cards Estratégicos
        "ROW-CARDS": {
            "children": ["CHART-1", "CHART-2", "CHART-3", "CHART-4", "CHART-5"],
            "id": "ROW-CARDS",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "parents": ["ROOT_ID", "GRID_ID"],
            "type": "ROW"
        },
        "CHART-1": {
            "children": [],
            "id": "CHART-1",
            "meta": {"chartId": s1.id, "height": 26, "sliceName": s1.slice_name, "uuid": str(s1.uuid), "width": 2},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CARDS"],
            "type": "CHART"
        },
        "CHART-2": {
            "children": [],
            "id": "CHART-2",
            "meta": {"chartId": s2.id, "height": 26, "sliceName": s2.slice_name, "uuid": str(s2.uuid), "width": 2},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CARDS"],
            "type": "CHART"
        },
        "CHART-3": {
            "children": [],
            "id": "CHART-3",
            "meta": {"chartId": s3.id, "height": 26, "sliceName": s3.slice_name, "uuid": str(s3.uuid), "width": 2},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CARDS"],
            "type": "CHART"
        },
        "CHART-4": {
            "children": [],
            "id": "CHART-4",
            "meta": {"chartId": s4.id, "height": 26, "sliceName": s4.slice_name, "uuid": str(s4.uuid), "width": 3},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CARDS"],
            "type": "CHART"
        },
        "CHART-5": {
            "children": [],
            "id": "CHART-5",
            "meta": {"chartId": s5.id, "height": 26, "sliceName": s5.slice_name, "uuid": str(s5.uuid), "width": 3},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CARDS"],
            "type": "CHART"
        },
        # Linha 2: Gráficos de Interações e Temporal
        "ROW-CHARTS-1": {
            "children": ["CHART-6", "CHART-7"],
            "id": "ROW-CHARTS-1",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "parents": ["ROOT_ID", "GRID_ID"],
            "type": "ROW"
        },
        "CHART-6": {
            "children": [],
            "id": "CHART-6",
            "meta": {"chartId": s6.id, "height": 45, "sliceName": s6.slice_name, "uuid": str(s6.uuid), "width": 6},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CHARTS-1"],
            "type": "CHART"
        },
        "CHART-7": {
            "children": [],
            "id": "CHART-7",
            "meta": {"chartId": s7.id, "height": 45, "sliceName": s7.slice_name, "uuid": str(s7.uuid), "width": 6},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CHARTS-1"],
            "type": "CHART"
        },
        # Linha 3: Recomendações e Formatos
        "ROW-CHARTS-2": {
            "children": ["CHART-8", "CHART-9"],
            "id": "ROW-CHARTS-2",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "parents": ["ROOT_ID", "GRID_ID"],
            "type": "ROW"
        },
        "CHART-8": {
            "children": [],
            "id": "CHART-8",
            "meta": {"chartId": s8.id, "height": 45, "sliceName": s8.slice_name, "uuid": str(s8.uuid), "width": 6},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CHARTS-2"],
            "type": "CHART"
        },
        "CHART-9": {
            "children": [],
            "id": "CHART-9",
            "meta": {"chartId": s9.id, "height": 45, "sliceName": s9.slice_name, "uuid": str(s9.uuid), "width": 6},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-CHARTS-2"],
            "type": "CHART"
        },
        # Linha 4: Auditoria e Qualidade
        "ROW-TABLE": {
            "children": ["CHART-10"],
            "id": "ROW-TABLE",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "parents": ["ROOT_ID", "GRID_ID"],
            "type": "ROW"
        },
        "CHART-10": {
            "children": [],
            "id": "CHART-10",
            "meta": {"chartId": s10.id, "height": 38, "sliceName": s10.slice_name, "uuid": str(s10.uuid), "width": 12},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-TABLE"],
            "type": "CHART"
        }
    }

    # 6. Salvar ou Atualizar Dashboard
    dash_title = "Plataforma Educacional — KPIs e Recomendações"
    dash = db.session.query(Dashboard).filter_by(dashboard_title=dash_title).first()
    if not dash:
        dash = db.session.query(Dashboard).filter_by(id=1).first()

    if not dash:
        dash = Dashboard(
            dashboard_title=dash_title,
            slug="plataforma-educacional-kpis",
            published=True,
            slices=all_slices,
            position_json=json.dumps(pos),
            owners=owners
        )
        db.session.add(dash)
        db.session.commit()
        print(f"Dashboard '{dash_title}' criado com ID: {dash.id}")
    else:
        dash.dashboard_title = dash_title
        dash.slug = "plataforma-educacional-kpis"
        dash.slices = all_slices
        dash.published = True
        dash.position_json = json.dumps(pos)
        if owners:
            dash.owners = owners
        db.session.commit()
        print(f"Dashboard '{dash_title}' atualizado com ID: {dash.id}")

    print(f"URL_DO_DASHBOARD: /superset/dashboard/{dash.id}/")
    print(f"URL_SLUG_DO_DASHBOARD: /superset/dashboard/{dash.slug}/")
