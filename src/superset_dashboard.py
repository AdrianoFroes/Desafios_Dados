"""
Script para provisionamento automatizado do Dashboard e Gráficos no Apache Superset (RF13).
Cria os 3 cartões de indicadores, 1 gráfico de barras, 1 gráfico de linhas
e 2 filtros interativos organizados em um Dashboard pronto para uso.
"""
import json
import subprocess
import sys

CONTAINER_NAME = "desafio_superset"

SCRIPT_CRIAR_DASHBOARD = """
import json
from superset.app import create_app
app = create_app()

with app.app_context():
    from superset import db
    from superset.models.core import Database
    from superset.models.slice import Slice
    from superset.models.dashboard import Dashboard
    from superset.connectors.sqla.models import SqlaTable

    # Busca o banco e as tabelas
    db_obj = db.session.query(Database).filter_by(database_name='Plataforma Educacional (PostgreSQL)').first()
    if not db_obj:
        print("Banco de dados não encontrado no Superset!")
        exit(1)

    t_geral = db.session.query(SqlaTable).filter_by(table_name='vw_kpi_metricas_gerais', database_id=db_obj.id).first()
    t_cat = db.session.query(SqlaTable).filter_by(table_name='vw_kpi_desempenho_categoria', database_id=db_obj.id).first()
    t_temp = db.session.query(SqlaTable).filter_by(table_name='vw_kpi_evolucao_temporal', database_id=db_obj.id).first()
    t_cont = db.session.query(SqlaTable).filter_by(table_name='vw_kpi_analise_conteudos', database_id=db_obj.id).first()

    # Função auxiliar para criar/atualizar slice
    def get_or_create_slice(slice_name, viz_type, datasource, params):
        s = db.session.query(Slice).filter_by(slice_name=slice_name).first()
        if not s:
            s = Slice(
                slice_name=slice_name,
                viz_type=viz_type,
                datasource_id=datasource.id,
                datasource_type='table',
                params=json.dumps(params)
            )
            db.session.add(s)
            db.session.commit()
            print(f"Gráfico criado: {slice_name}")
        else:
            s.params = json.dumps(params)
            db.session.commit()
            print(f"Gráfico atualizado: {slice_name}")
        return s

    # 1. Cartão 1: Total de Usuários Ativos (Big Number)
    s1 = get_or_create_slice(
        slice_name="Total de Usuários Ativos",
        viz_type="big_number_total",
        datasource=t_geral,
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(total_usuarios)", "label": "Total Usuários"},
            "subheader": "Discentes únicos com interações registradas",
            "y_axis_format": ",d"
        }
    )

    # 2. Cartão 2: Avaliação Média Global (Big Number)
    s2 = get_or_create_slice(
        slice_name="Avaliação Média Geral (CSAT)",
        viz_type="big_number_total",
        datasource=t_geral,
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(avaliacao_media_global)", "label": "Média Estrelas"},
            "subheader": "Escala de 1 a 5 estrelas",
            "y_axis_format": ".2f"
        }
    )

    # 3. Cartão 3: Taxa de Conclusão Global (Big Number)
    s3 = get_or_create_slice(
        slice_name="Taxa de Conclusão Global",
        viz_type="big_number_total",
        datasource=t_geral,
        params={
            "metric": {"expressionType": "SQL", "sqlExpression": "MAX(taxa_conclusao_global_pct)", "label": "Taxa Conclusão (%)"},
            "subheader": "Conclusões / Inícios e Visualizações",
            "y_axis_format": ".1f%"
        }
    )

    # 4. Gráfico de Barras: Interações e Conclusão por Categoria
    s4 = get_or_create_slice(
        slice_name="Engajamento e Conclusões por Categoria",
        viz_type="echarts_timeseries_bar",
        datasource=t_cat,
        params={
            "groupby": ["categoria_nome"],
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(total_interacoes)", "label": "Total Interações"},
                {"expressionType": "SQL", "sqlExpression": "SUM(conclusoes)", "label": "Total Conclusões"}
            ],
            "order_desc": True,
            "y_axis_title": "Quantidade",
            "x_axis_title": "Categoria Temática"
        }
    )

    # 5. Gráfico de Linhas: Evolução Temporal de Interações Diárias
    s5 = get_or_create_slice(
        slice_name="Evolução Temporal de Interações Diárias",
        viz_type="echarts_timeseries_line",
        datasource=t_temp,
        params={
            "x_axis": "data",
            "metrics": [
                {"expressionType": "SQL", "sqlExpression": "SUM(total_interacoes)", "label": "Interações Totais"},
                {"expressionType": "SQL", "sqlExpression": "SUM(visualizacoes)", "label": "Visualizações"}
            ],
            "y_axis_title": "Volume Diário"
        }
    )

    # 6. Criação do Dashboard consolidado
    dash_title = "Plataforma Educacional — KPIs e Recomendações"
    dash = db.session.query(Dashboard).filter_by(dashboard_title=dash_title).first()
    slices_list = [s1, s2, s3, s4, s5]

    if not dash:
        dash = Dashboard(
            dashboard_title=dash_title,
            slug="plataforma-educacional-kpis",
            published=True,
            slices=slices_list
        )
        db.session.add(dash)
        db.session.commit()
        print(f"Dashboard '{dash_title}' criado com sucesso!")
    else:
        dash.slices = slices_list
        dash.published = True
        db.session.commit()
        print(f"Dashboard '{dash_title}' atualizado com sucesso!")

    print(f"DASHBOARD_ID: {dash.id}")
"""

def provisionar_dashboard():
    print("=" * 60)
    print("Provisionando componentes e layout do Dashboard no Apache Superset (RF13)...")
    print("=" * 60)
    cmd = f'docker exec {CONTAINER_NAME} python /app/setup_superset_internal.py'
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        # Fallback com docker cp caso o volume não esteja mapeado
        cmd_fallback = f'docker cp src/setup_superset_internal.py {CONTAINER_NAME}:/tmp/setup_superset_internal.py && docker exec {CONTAINER_NAME} python /tmp/setup_superset_internal.py'
        res = subprocess.run(cmd_fallback, shell=True, capture_output=True, text=True)
        if res.returncode != 0:
            print("Aviso/Erro ao provisionar dashboard no Superset:", res.stderr or res.stdout)
            return False
    print(res.stdout)
    print("Dashboard e gráficos no Apache Superset provisionados com sucesso!")
    print("URL Direta do Dashboard (Kiosk): http://localhost:8088/superset/dashboard/1/?standalone=2")
    print("URL da Apresentação Web: http://localhost:8085/slides.html")
    return True

if __name__ == "__main__":
    if not provisionar_dashboard():
        sys.exit(1)
