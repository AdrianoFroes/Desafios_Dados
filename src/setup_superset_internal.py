import json
import os
import re
import time
from superset.app import create_app

app = create_app()
with app.app_context():
    from superset import db, security_manager
    from superset.models.core import Database
    from superset.models.slice import Slice
    from superset.models.dashboard import Dashboard
    from superset.connectors.sqla.models import SqlaTable
    from superset.reports.models import (
        ReportRecipients,
        ReportSchedule,
        ReportScheduleType,
        ReportScheduleValidatorType,
        ReportDataFormat,
    )
    from sqlalchemy import create_engine, text

    # 1. Obter usuário admin
    admin = security_manager.find_user(os.environ.get("SUPERSET_ADMIN_USER", "admin"))
    owners = [admin] if admin else []

    # 2. Conexão com o PostgreSQL pelo papel leitor_bi (sql/papeis_acesso.sql).
    #    A URI vem do docker-compose/.env; nenhuma senha fica neste arquivo.
    pg_uri = os.environ["SUPERSET_DB_URI"]
    print("Aguardando conexao com PostgreSQL...")
    engine_pg = None
    for tentativa in range(1, 16):
        try:
            engine_pg = create_engine(pg_uri)
            with engine_pg.connect() as conn:
                conn.execute(text("SELECT 1 FROM gold.kpi_geral LIMIT 1"))
            print(f"Conexao com PostgreSQL estabelecida na tentativa {tentativa}.")
            break
        except Exception as e:
            print(f"Tentativa {tentativa}/15: PostgreSQL ainda nao disponivel ({e}). Aguardando 2s...")
            engine_pg = None
            time.sleep(2)
    if engine_pg is None:
        raise SystemExit("Sem acesso a gold.* com o leitor_bi. Rode scripts/02 e scripts/05 antes.")

    db_name = "Plataforma Educacional (PostgreSQL)"
    db_obj = db.session.query(Database).filter_by(database_name=db_name).first()
    if not db_obj:
        db_obj = Database(database_name=db_name)
        db.session.add(db_obj)
    db_obj.set_sqlalchemy_uri(pg_uri)
    db_obj.expose_in_sqllab = True
    db.session.commit()
    print(f"Banco '{db_name}' com id {db_obj.id} apontando para o leitor_bi")

    def registrar_tabela(table_name, schema, desc):
        tbl = db.session.query(SqlaTable).filter_by(
            table_name=table_name, schema=schema, database_id=db_obj.id
        ).first()
        if not tbl:
            tbl = SqlaTable(table_name=table_name, database_id=db_obj.id, schema=schema,
                            description=desc, owners=owners)
            db.session.add(tbl)
            db.session.commit()
        try:
            tbl.fetch_metadata()
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Aviso metadata para {schema}.{table_name}: {e}")
        print(f"Dataset {schema}.{table_name} sincronizado com id {tbl.id}")
        return tbl

    datasets = {}

    # Views do Desafio 1, mantidas só como referência do pipeline Python.
    for table_name, desc in [
        ("vw_kpi_metricas_gerais", "Métricas Gerais da Plataforma"),
        ("vw_kpi_desempenho_categoria", "Desempenho por Categoria e Tipo"),
        ("vw_kpi_evolucao_temporal", "Evolução Temporal de Interações"),
        ("vw_kpi_engajamento_formato", "Engajamento e Retenção por Formato"),
        ("vw_kpi_conversao_recomendacoes", "Taxa de Conversão de Recomendações"),
    ]:
        datasets[table_name] = registrar_tabela(table_name, "public", desc)

    # Datasets físicos da Gold (estudante 3, commit 7122171).
    for table_name, desc in [
        ("kpi_geral", "KPI geral publicado por gold.publicar"),
        ("kpi_evolucao_dia", "Série diária da Gold"),
        ("kpi_desempenho_categoria", "Conclusão por categoria e tipo"),
        ("kpi_engajamento_formato", "Retenção por formato"),
        ("kpi_conversao_recomendacao", "Conversão do último lote de recomendação"),
    ]:
        datasets[table_name] = registrar_tabela(table_name, "gold", desc)

    # 3. Datasets virtuais (RF17). O SQL é o mesmo de sql/sql_lab.sql.
    def consulta_sql_lab(numero):
        with open("/app/sql/sql_lab.sql", encoding="utf-8") as f:
            blocos = re.split(r"^-- Consulta (\d+)", f.read(), flags=re.M)
        for i in range(1, len(blocos), 2):
            if int(blocos[i]) == numero:
                linhas = [l for l in blocos[i + 1].splitlines() if not l.strip().startswith("--")]
                return "\n".join(linhas[1:]).strip().rstrip(";")
        raise KeyError(numero)

    def registrar_virtual(nome, numero, desc, colunas_data):
        sql = consulta_sql_lab(numero)
        tbl = db.session.query(SqlaTable).filter_by(table_name=nome, database_id=db_obj.id).first()
        if not tbl:
            tbl = SqlaTable(table_name=nome, database_id=db_obj.id, schema="gold",
                            sql=sql, description=desc, owners=owners)
            db.session.add(tbl)
        tbl.sql = sql
        tbl.description = desc
        db.session.commit()
        tbl.fetch_metadata()
        for col in tbl.columns:
            if col.column_name in colunas_data:
                col.is_dttm = True
        tbl.main_dttm_col = colunas_data[0]
        db.session.commit()
        print(f"Dataset virtual {nome} (consulta {numero} do sql_lab.sql) com id {tbl.id}")
        return tbl

    vds_dia = registrar_virtual(
        "vds_interacoes_dia_categoria", 1,
        "Interações por dia, categoria e tipo (fato x dimensão da Gold)", ["data", "mes"])
    vds_mes = registrar_virtual(
        "vds_conclusao_categoria_mes", 2,
        "Taxa de conclusão mensal por categoria com faixa de desempenho", ["mes"])

    # 4. Gráficos (os três do estudante 3)
    def salvar_slice(nome, viz_type, datasource, params):
        params = dict(params, viz_type=viz_type, datasource=f"{datasource.id}__table")
        s = db.session.query(Slice).filter_by(slice_name=nome).first()
        if not s:
            s = Slice(slice_name=nome, viz_type=viz_type, datasource_id=datasource.id,
                      datasource_type="table", owners=owners)
            db.session.add(s)
        s.params = json.dumps(params, ensure_ascii=False)
        # Sem query_context o e-mail TEXT do alerta tenta gerar screenshot (sem webdriver na imagem).
        colunas = [c for c in [params.get("x_axis"), *params.get("groupby", [])] if c]
        metricas = params.get("metrics") or [params["metric"]]
        s.query_context = json.dumps({
            "datasource": {"id": datasource.id, "type": "table"},
            "force": False,
            "queries": [{
                "columns": colunas, "metrics": metricas, "filters": [], "extras": {},
                "orderby": [], "row_limit": params.get("row_limit", 1000),
            }],
            "form_data": params,
            "result_format": "json",
            "result_type": "full",
        }, ensure_ascii=False)
        s.datasource_id = datasource.id
        s.viz_type = viz_type
        if owners:
            s.owners = owners
        db.session.commit()
        print(f"Gráfico salvo: {nome} (ID {s.id})")
        return s

    s_usuarios = salvar_slice(
        "Usuários Ativos", "big_number_total", datasets["kpi_geral"],
        {
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(usuarios_ativos)", "label": "Usuários ativos"},
            "subheader": "",
            "y_axis_format": ",d",
        },
    )

    # Mesma métrica SUM(total_interacoes) por data; o dataset virtual tem categoria
    # e tipo, então o gráfico recebe o filtro cruzado e o filtro de categoria.
    s_temporal = salvar_slice(
        "Evolução Temporal de Interações", "echarts_timeseries_line", vds_dia,
        {
            "x_axis": "data",
            "time_grain_sqla": "P1D",
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(total_interacoes)", "label": "total_interacoes"}
            ],
            "groupby": [],
            "row_limit": 10000,
            "y_axis_title": "",
        },
    )

    # Mesmas barras (categoria no eixo, tipo como série). ECharts no lugar do
    # Bar Chart legado porque só os gráficos ECharts emitem filtro cruzado.
    s_categoria = salvar_slice(
        "Taxa de Conclusão por Categoria", "echarts_timeseries_bar", datasets["kpi_desempenho_categoria"],
        {
            "x_axis": "categoria",
            "groupby": ["tipo"],
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "MAX(taxa_conclusao_pct)", "label": "Taxa de conclusão"}
            ],
            "orientation": "vertical",
            "x_axis_sort_asc": True,
            "row_limit": 1000,
            "show_legend": True,
            "y_axis_format": ".2f",
            "truncateXAxis": True,
        },
    )

    all_slices = [s_usuarios, s_temporal, s_categoria]
    ids = [s.id for s in all_slices]

    pos = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"children": ["GRID_ID"], "id": "ROOT_ID", "type": "ROOT"},
        "HEADER_ID": {"id": "HEADER_ID", "meta": {"text": "Plataforma Educacional — KPIs e Recomendações"}, "type": "HEADER"},
        "GRID_ID": {"children": ["ROW-ESTUDANTE3"], "id": "GRID_ID", "parents": ["ROOT_ID"], "type": "GRID"},
        "ROW-ESTUDANTE3": {
            "children": ["CHART-USUARIOS", "CHART-TEMPORAL", "CHART-CATEGORIA"],
            "id": "ROW-ESTUDANTE3",
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
            "parents": ["ROOT_ID", "GRID_ID"],
            "type": "ROW",
        },
    }
    for chave, s, largura in [("CHART-USUARIOS", s_usuarios, 3), ("CHART-TEMPORAL", s_temporal, 4), ("CHART-CATEGORIA", s_categoria, 5)]:
        pos[chave] = {
            "children": [],
            "id": chave,
            "meta": {"chartId": s.id, "height": 50, "sliceName": s.slice_name, "uuid": str(s.uuid), "width": largura},
            "parents": ["ROOT_ID", "GRID_ID", "ROW-ESTUDANTE3"],
            "type": "CHART",
        }

    # 5. Filtros globais (RF18): período e categoria.
    native_filters = [
        {
            "id": "NATIVE_FILTER-periodo",
            "name": "Período",
            "filterType": "filter_time",
            "type": "NATIVE_FILTER",
            "targets": [{}],
            "controlValues": {},
            "defaultDataMask": {"extraFormData": {}, "filterState": {}, "ownState": {}},
            "cascadeParentIds": [],
            "scope": {"rootPath": ["ROOT_ID"], "excluded": [s_usuarios.id, s_categoria.id]},
            "chartsInScope": [s_temporal.id],
            "description": "Intervalo de datas aplicado à série temporal",
        },
        {
            "id": "NATIVE_FILTER-categoria",
            "name": "Categoria",
            "filterType": "filter_select",
            "type": "NATIVE_FILTER",
            "targets": [{"datasetId": vds_mes.id, "column": {"name": "categoria"}}],
            "controlValues": {
                "enableEmptyFilter": False,
                "defaultToFirstItem": False,
                "multiSelect": True,
                "searchAllOptions": False,
                "inverseSelection": False,
            },
            "defaultDataMask": {"extraFormData": {}, "filterState": {}, "ownState": {}},
            "cascadeParentIds": [],
            "scope": {"rootPath": ["ROOT_ID"], "excluded": [s_usuarios.id]},
            "chartsInScope": [s_temporal.id, s_categoria.id],
            "description": "Categoria temática do conteúdo",
        },
    ]

    # Filtro cruzado: clicar numa série (tipo) das barras filtra a série temporal.
    chart_configuration = {
        str(s.id): {
            "id": s.id,
            "crossFilters": {"scope": "global", "chartsInScope": [i for i in ids if i != s.id]},
        }
        for s in all_slices
    }
    json_metadata = {
        "native_filter_configuration": native_filters,
        "cross_filters_enabled": True,
        "chart_configuration": chart_configuration,
        "global_chart_configuration": {
            "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
            "chartsInScope": ids,
        },
        "color_scheme": "",
        "refresh_frequency": 0,
        "timed_refresh_immune_slices": [],
        "expanded_slices": {},
        "label_colors": {},
    }

    # 6. Dashboard
    dash_title = "Plataforma Educacional — KPIs e Recomendações"
    dash = db.session.query(Dashboard).filter_by(dashboard_title=dash_title).first()
    if not dash:
        dash = db.session.query(Dashboard).filter_by(id=1).first()
    if not dash:
        dash = Dashboard(dashboard_title=dash_title, owners=owners)
        db.session.add(dash)
    dash.dashboard_title = dash_title
    dash.slug = "plataforma-educacional-kpis"
    dash.slices = all_slices
    dash.published = True
    dash.position_json = json.dumps(pos, ensure_ascii=False)
    dash.json_metadata = json.dumps(json_metadata, ensure_ascii=False)
    if owners:
        dash.owners = owners
    db.session.commit()
    print(f"Dashboard '{dash_title}' salvo com ID {dash.id}")

    # Leitura anônima (iframe da apresentação): só os datasets agregados do dashboard.
    publico = security_manager.find_role(app.config["AUTH_ROLE_PUBLIC"]) or security_manager.add_role(app.config["AUTH_ROLE_PUBLIC"])
    for tbl in {s.table for s in all_slices} | {vds_mes}:
        pv = security_manager.add_permission_view_menu("datasource_access", tbl.perm)
        security_manager.add_permission_role(publico, pv)
    print(f"Papel {publico.name}: leitura dos datasets do dashboard, sem SQL Lab")

    # 7. Alerta (RF18): conversão de recomendação abaixo de 8%.
    alerta_sql = "SELECT MAX(taxa_conversao_pct) AS value FROM gold.kpi_conversao_recomendacao"
    alerta_nome = "Conversão de recomendação abaixo de 8%"
    destinatario = os.environ.get("ALERTA_DESTINATARIO", "aluno3@ficticio.edu.br")

    def salvar_alerta(nome, limite, cron, descricao, grace_period):
        alerta = db.session.query(ReportSchedule).filter_by(name=nome).first()
        if not alerta:
            alerta = ReportSchedule(name=nome, type=ReportScheduleType.ALERT)
            db.session.add(alerta)
        alerta.description = descricao
        alerta.active = True
        alerta.crontab = cron
        alerta.timezone = "America/Sao_Paulo"
        alerta.database_id = db_obj.id
        alerta.sql = alerta_sql
        alerta.validator_type = ReportScheduleValidatorType.OPERATOR
        alerta.validator_config_json = json.dumps({"op": "<", "threshold": limite})
        alerta.chart_id = s_categoria.id
        alerta.dashboard_id = None
        alerta.report_format = ReportDataFormat.TEXT
        alerta.grace_period = grace_period
        alerta.working_timeout = 3600
        alerta.log_retention = 90
        alerta.creation_method = "alerts_reports"
        alerta.force_screenshot = False
        if owners:
            alerta.owners = owners
        db.session.commit()
        alerta.recipients = [
            ReportRecipients(type="Email", recipient_config_json=json.dumps({"target": destinatario}))
        ]
        db.session.commit()
        return alerta

    alerta = salvar_alerta(
        alerta_nome, 8, os.environ.get("ALERTA_CRON", "*/5 * * * *"),
        "Avisa a equipe de dados quando a conversão do último lote de recomendação cai abaixo da meta.",
        86400,
    )

    # Demonstração do disparo: mesmo SQL com limite acima do valor atual, avaliado a cada minuto.
    demo_nome = "Demonstração de disparo do alerta de conversão"
    demo_limite = os.environ.get("ALERTA_DEMO_LIMITE")
    if demo_limite:
        demo = salvar_alerta(demo_nome, float(demo_limite), "* * * * *",
                             "Alerta temporário para comprovar o envio do e-mail (scripts/06_superset.ps1 -DemonstrarDisparo).", 0)
        print(f"ALERTA_DEMO: id={demo.id} condicao='value < {demo_limite}'")
    else:
        demo = db.session.query(ReportSchedule).filter_by(name=demo_nome).first()
        if demo:
            db.session.delete(demo)
            db.session.commit()

    with engine_pg.connect() as conn:
        valor = conn.execute(text(alerta_sql)).scalar()
    dispara = valor is not None and float(valor) < 8
    print(f"Alerta '{alerta_nome}' (ID {alerta.id}) cron='{alerta.crontab}' destinatario={destinatario}")
    print(f"AVALIACAO_ALERTA: value={valor} condicao='value < 8' dispara={dispara}")
    print(f"URL_DO_DASHBOARD: /superset/dashboard/{dash.id}/")
