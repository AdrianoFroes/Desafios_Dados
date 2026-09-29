"""RF27-RF29 / RF32 - catálogo no OpenMetadata 1.3.1.

1. Obtém o token do ingestion-bot pelo login do admin (nada fica versionado).
2. Roda a ingestão de metadados técnicos do PostgreSQL e do Superset dentro do
   container openmetadata_ingestion (YAMLs em openmetadata/ingestao/).
3. Cria os times responsáveis, descrições e proprietários dos ativos principais.
4. Cria a classificação LGPD e aplica PII/LGPD/Tier às colunas e tabelas.
5. Cria o glossário com os termos de negócio e associa aos campos.
6. Registra a linhagem fonte -> Bronze -> Silver -> Gold -> dataset virtual -> dashboard,
   com a transformação de cada aresta e a linhagem de coluna do KPI "usuários ativos".

Uso: python openmetadata/configurar_catalogo.py [--sem-ingestao]
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
API = "http://localhost:8585/api/v1"
SERVICO_PG = "plataforma_educacional_pg"
BANCO = "plataforma_educacional"
SERVICO_SUPERSET = "superset_desafio"
GLOSSARIO = "PlataformaEducacional"


def ler_env() -> dict:
    valores = {}
    for linha in (RAIZ / ".env").read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if linha.strip().startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        valores[chave.strip()] = valor.strip()
    return valores


class OM:
    def __init__(self, token: str | None = None):
        self.token = token

    def req(self, metodo: str, caminho: str, corpo=None, patch: bool = False):
        dados = None if corpo is None else json.dumps(corpo).encode("utf-8")
        tipo = "application/json-patch+json" if patch else "application/json"
        pedido = urllib.request.Request(API + caminho, data=dados, method=metodo)
        pedido.add_header("Content-Type", tipo)
        if self.token:
            pedido.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(pedido, timeout=60) as resp:
                texto = resp.read().decode("utf-8")
                try:
                    return json.loads(texto) if texto else {}
                except json.JSONDecodeError:
                    return {"texto": texto}
        except urllib.error.HTTPError as erro:
            detalhe = erro.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{metodo} {caminho} -> {erro.code}: {detalhe[:300]}") from None

    def get(self, caminho):
        return self.req("GET", caminho)

    def put(self, caminho, corpo):
        return self.req("PUT", caminho, corpo)

    def patch(self, caminho, operacoes):
        if operacoes:
            return self.req("PATCH", caminho, operacoes, patch=True)
        return None


def login(env: dict) -> OM:
    om = OM()
    senha = base64.b64encode(env.get("OM_ADMIN_PASSWORD", "admin").encode()).decode()
    resp = om.req("POST", "/users/login", {
        "email": env.get("OM_ADMIN_EMAIL", "admin"),
        "password": senha,
    })
    om.token = resp["accessToken"]
    return om


def token_bot(om: OM, env: dict) -> str:
    if env.get("OM_JWT_TOKEN"):
        return env["OM_JWT_TOKEN"]
    bot = om.get("/bots/name/ingestion-bot?fields=botUser")
    mecanismo = om.get(f"/users/auth-mechanism/{bot['botUser']['id']}")
    return mecanismo["config"]["JWTToken"]


def ingerir(env: dict, jwt: str, arquivo: str) -> None:
    print(f"== ingestão {arquivo}")
    variaveis = {
        "OM_JWT_TOKEN": jwt,
        "OM_CATALOGO_PASSWORD": env["OM_CATALOGO_PASSWORD"],
        "POSTGRES_PORT": env.get("POSTGRES_PORT", "5433"),
        "SUPERSET_ADMIN_USER": env.get("SUPERSET_ADMIN_USER", "admin"),
        "SUPERSET_ADMIN_PASSWORD": env["SUPERSET_ADMIN_PASSWORD"],
    }
    cmd = ["docker", "exec"]
    for chave, valor in variaveis.items():
        cmd += ["-e", f"{chave}={valor}"]
    cmd += ["openmetadata_ingestion", "metadata", "ingest", "-c", f"/opt/ingestao/{arquivo}"]
    resultado = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    saida = resultado.stdout + resultado.stderr
    for linha in saida.splitlines():
        if any(p in linha for p in ("Success %", "Processed records", "Errors", "Workflow Summary", "ERROR")):
            print("   ", linha.strip()[:200])
    if resultado.returncode != 0:
        raise RuntimeError(f"ingestão {arquivo} falhou (código {resultado.returncode})")


def fqn(esquema: str, tabela: str) -> str:
    return f"{SERVICO_PG}.{BANCO}.{esquema}.{tabela}"


_cache_tabelas: dict = {}


def tabela(om: OM, esquema: str, nome: str) -> dict | None:
    chave = (esquema, nome)
    if chave not in _cache_tabelas:
        try:
            _cache_tabelas[chave] = om.get(f"/tables/name/{fqn(esquema, nome)}?fields=columns,tags,owner")
        except RuntimeError:
            _cache_tabelas[chave] = None
    return _cache_tabelas[chave]


def tag_label(tag_fqn: str, glossario: bool = False) -> dict:
    return {
        "tagFQN": tag_fqn,
        "source": "Glossary" if glossario else "Classification",
        "labelType": "Manual",
        "state": "Confirmed",
    }


# ---------------------------------------------------------------- responsáveis
TIMES = {
    "estudante_1_ingestao": "Estudante 1 - Bronze e Silver (Apache Hop)",
    "estudante_2_gold": "Estudante 2 - Qualidade, Gold, Dados mestres, Parquet e Beam",
    "estudante_3_governanca": "Estudante 3 - Superset, OpenMetadata e LGPD",
}


def criar_times(om: OM) -> dict:
    refs = {}
    for nome, exibicao in TIMES.items():
        time_ = om.put("/teams", {"name": nome, "displayName": exibicao, "teamType": "Group",
                                  "description": f"Responsável: {exibicao}."})
        refs[nome] = {"id": time_["id"], "type": "team"}
    print(f"== times responsáveis: {', '.join(refs)}")
    return refs


DESCRICOES = {
    ("bronze", "catalogo"): ("estudante_1_ingestao", "Cópia auditável de dados/brutos/catalogo.csv, sem transformação destrutiva. Colunas de auditoria: origem, arquivo_origem, data_hora_ingestao, execucao_id."),
    ("bronze", "interacoes"): ("estudante_1_ingestao", "Cópia auditável de dados/brutos/interacoes.json com colunas de auditoria."),
    ("bronze", "comentarios"): ("estudante_1_ingestao", "Cópia auditável de dados/brutos/comentarios.json com colunas de auditoria."),
    ("silver", "conteudo"): ("estudante_1_ingestao", "Catálogo padronizado. Chave de negócio conteudo_id; domínio de tipo, categoria e nível validado; inválidos vão para quarentena.registro."),
    ("silver", "interacao"): ("estudante_1_ingestao", "Interações padronizadas. Chave (usuario_id, conteudo_id, data_hora); referência a silver.conteudo validada."),
    ("silver", "comentario"): ("estudante_1_ingestao", "Comentários padronizados com tags normalizadas. Chave (usuario_id, conteudo_id, data)."),
    ("quarentena", "registro"): ("estudante_1_ingestao", "Registros rejeitados pela Silver: registro_id, origem, regra_violada, data, mensagem, payload_original e status de reprocessamento."),
    ("qualidade", "resultado"): ("estudante_2_gold", "Resultado dos 5 testes de qualidade por execução e fonte. Teste crítico reprovado bloqueia gold.publicar."),
    ("auditoria", "etapa"): ("estudante_2_gold", "Log estruturado do workflow Hop: início, fim e resultado de cada etapa por execucao_id."),
    ("gold", "dim_conteudo"): ("estudante_2_gold", "Dimensão de conteúdo. Grão: 1 linha por conteudo_id. A coluna autor não é concedida ao leitor_bi."),
    ("gold", "fato_engajamento_dia"): ("estudante_2_gold", "Fato de engajamento. Grão: conteudo_id + dia. Conclusão = tipo 'conclusão' ou percentual >= 100."),
    ("gold", "kpi_geral"): ("estudante_2_gold", "KPIs da plataforma em 1 linha: usuários ativos, taxa de conclusão, avaliação, conversão de recomendação."),
    ("gold", "kpi_evolucao_dia"): ("estudante_2_gold", "Série diária: interações, usuários ativos e conclusões por dia."),
    ("gold", "kpi_desempenho_categoria"): ("estudante_2_gold", "Taxa de conclusão por categoria e tipo. Alimenta o gráfico Taxa de Conclusão por Categoria."),
    ("gold", "kpi_engajamento_formato"): ("estudante_2_gold", "Retenção por formato (Artigo, Curso, Podcast, Vídeo). Base da pergunta do storytelling."),
    ("gold", "kpi_conversao_recomendacao"): ("estudante_2_gold", "Conversão do último lote de recomendação. Condição do alerta: taxa_conversao_pct < 8."),
    ("mestres", "conteudo_mestre"): ("estudante_2_gold", "Registro mestre de conteúdo (RF30). mestre_id = CNT- + menor conteudo_id do grupo."),
    ("mestres", "correspondencia_conteudo"): ("estudante_2_gold", "Tabela de correspondência conteudo_id -> mestre_id com a regra de match aplicada."),
    ("lgpd", "conteudo_publico"): ("estudante_3_governanca", "Conteúdo para consumo: autor mascarado e autor_hash (sha256 com salt fora do repositório)."),
    ("lgpd", "vw_interacao_pseudonimizada"): ("estudante_3_governanca", "Interações com pseudo_id no lugar de usuario_id. Correspondência em lgpd_restrito, sem acesso para o BI."),
    ("lgpd", "vw_comentario_mascarado"): ("estudante_3_governanca", "Comentários com texto truncado e pseudo_id."),
}


def descrever(om: OM, times: dict) -> None:
    ok = 0
    for (esquema, nome), (dono, texto) in DESCRICOES.items():
        t = tabela(om, esquema, nome)
        if not t:
            print(f"   aviso: {esquema}.{nome} não catalogada")
            continue
        om.patch(f"/tables/{t['id']}", [
            {"op": "add", "path": "/description", "value": texto},
            {"op": "add", "path": "/owner", "value": times[dono]},
        ])
        ok += 1
    print(f"== descrição e proprietário em {ok} tabelas")


# ---------------------------------------------------------------- classificação
TAGS_LGPD = {
    "DadoPessoal": "Dado pessoal direto (nome). Não pode chegar ao dashboard.",
    "IdentificadorIndireto": "Identificador que associa ações a uma pessoa (usuario_id).",
    "Pseudonimizado": "Substituído por pseudônimo; reassociação só via lgpd_restrito.",
    "Mascarado": "Exibido parcialmente para consumo.",
    "HashComSalt": "sha256 com salt fora do repositório; comparação irreversível.",
}

CLASSIFICACOES_COLUNA = [
    ("bronze", "interacoes", "usuario_id", ["PII.Sensitive", "LGPD.IdentificadorIndireto"]),
    ("bronze", "comentarios", "usuario_id", ["PII.Sensitive", "LGPD.IdentificadorIndireto"]),
    ("bronze", "comentarios", "comentario", ["PII.Sensitive"]),
    ("bronze", "catalogo", "autor", ["PersonalData.Personal", "LGPD.DadoPessoal"]),
    ("silver", "interacao", "usuario_id", ["PII.Sensitive", "LGPD.IdentificadorIndireto"]),
    ("silver", "comentario", "usuario_id", ["PII.Sensitive", "LGPD.IdentificadorIndireto"]),
    ("silver", "comentario", "comentario", ["PII.Sensitive"]),
    ("silver", "conteudo", "autor", ["PersonalData.Personal", "LGPD.DadoPessoal"]),
    ("gold", "dim_conteudo", "autor", ["PersonalData.Personal", "LGPD.DadoPessoal"]),
    ("lgpd", "vw_interacao_pseudonimizada", "pseudo_id", ["PII.NonSensitive", "LGPD.Pseudonimizado"]),
    ("lgpd", "vw_comentario_mascarado", "comentario_mascarado", ["LGPD.Mascarado"]),
    ("lgpd", "conteudo_publico", "autor_mascarado", ["LGPD.Mascarado"]),
    ("lgpd", "conteudo_publico", "autor_hash", ["LGPD.HashComSalt"]),
]


def aplicar_tags_coluna(om: OM, esquema: str, nome: str, coluna: str, tags: list[dict]) -> bool:
    t = tabela(om, esquema, nome)
    if not t:
        return False
    for i, col in enumerate(t["columns"]):
        if col["name"] == coluna:
            atuais = col.get("tags") or []
            existentes = {x["tagFQN"] for x in atuais}
            novas = atuais + [x for x in tags if x["tagFQN"] not in existentes]
            if len(novas) != len(atuais):
                om.patch(f"/tables/{t['id']}", [{"op": "add", "path": f"/columns/{i}/tags", "value": novas}])
                col["tags"] = novas
            return True
    return False


def classificar(om: OM) -> None:
    om.put("/classifications", {
        "name": "LGPD",
        "description": "Classificação de sensibilidade conforme lgpd/inventario_de_dados.md.",
    })
    for nome, descricao in TAGS_LGPD.items():
        om.put("/tags", {"classification": "LGPD", "name": nome, "description": descricao})
    ok = 0
    for esquema, nome, coluna, tags in CLASSIFICACOES_COLUNA:
        ok += aplicar_tags_coluna(om, esquema, nome, coluna, [tag_label(x) for x in tags])
    for esquema, nome in [("gold", n) for n in ("kpi_geral", "kpi_evolucao_dia", "kpi_desempenho_categoria",
                                                   "kpi_engajamento_formato", "kpi_conversao_recomendacao")]:
        t = tabela(om, esquema, nome)
        if t and not any(x["tagFQN"].startswith("Tier.") for x in t.get("tags") or []):
            om.patch(f"/tables/{t['id']}", [{"op": "add", "path": "/tags", "value": (t.get("tags") or []) + [tag_label("Tier.Tier1")]}])
    print(f"== classificação LGPD/PII em {ok} colunas e Tier1 nas tabelas de KPI")


# ---------------------------------------------------------------- glossário
TERMOS = {
    "UsuarioAtivo": ("Usuário ativo",
                     "Usuário com pelo menos uma interação aprovada na Silver no período analisado.",
                     "COUNT(DISTINCT usuario_id) em silver.interacao (geral) ou por data_hora::date (diário).",
                     "estudante_2_gold",
                     [("gold", "kpi_geral", "usuarios_ativos"), ("gold", "kpi_evolucao_dia", "usuarios_ativos")]),
    "TaxaConclusao": ("Taxa de conclusão",
                      "Proporção de interações que terminaram o conteúdo em relação às que o iniciaram ou visualizaram.",
                      "100 * interações com tipo 'conclusão' ou percentual_conclusao >= 100 / interações de 'início' ou 'visualização'.",
                      "estudante_2_gold",
                      [("gold", "kpi_geral", "taxa_conclusao_pct"), ("gold", "kpi_desempenho_categoria", "taxa_conclusao_pct"),
                       ("gold", "kpi_engajamento_formato", "taxa_conclusao_pct")]),
    "ConversaoRecomendacao": ("Conversão de recomendação",
                              "Parcela das recomendações do último lote que o usuário efetivamente consumiu.",
                              "100 * recomendações do último lote com interação (visualização, início, conclusão ou curtida) do mesmo usuário e conteúdo / total do lote. Meta >= 8%.",
                              "estudante_3_governanca",
                              [("gold", "kpi_conversao_recomendacao", "taxa_conversao_pct"), ("gold", "kpi_geral", "taxa_conversao_recomendacao_pct")]),
    "Engajamento": ("Engajamento",
                    "Volume de interações de qualquer tipo com um conteúdo.",
                    "COUNT(*) de silver.interacao por conteudo_id e dia (gold.fato_engajamento_dia.total_interacoes).",
                    "estudante_2_gold",
                    [("gold", "fato_engajamento_dia", "total_interacoes"), ("gold", "kpi_evolucao_dia", "total_interacoes")]),
    "RegistroMestre": ("Registro mestre de conteúdo",
                       "Versão única e confiável de um conteúdo após correspondência e deduplicação.",
                       "Agrupa por título normalizado + tipo + autor; mestre_id = 'CNT-' + menor conteudo_id; nível, carga e data vêm da publicação mais recente.",
                       "estudante_2_gold",
                       [("mestres", "conteudo_mestre", "mestre_id"), ("mestres", "correspondencia_conteudo", "mestre_id")]),
}


def glossario(om: OM, times: dict) -> None:
    om.put("/glossaries", {
        "name": GLOSSARIO,
        "displayName": "Plataforma Educacional",
        "description": "Termos de negócio dos KPIs do dashboard. Fórmulas em sql/camada_gold.sql e documentacao/kpis.md.",
        "owner": times["estudante_3_governanca"],
    })
    associados = 0
    for nome, (exibicao, definicao, regra, dono, colunas) in TERMOS.items():
        om.put("/glossaryTerms", {
            "glossary": GLOSSARIO,
            "name": nome,
            "displayName": exibicao,
            "description": f"**Definição:** {definicao}\n\n**Regra de cálculo:** {regra}\n\n**Responsável:** {TIMES[dono]}",
            "owner": times[dono],
        })
        for esquema, tab, coluna in colunas:
            associados += aplicar_tags_coluna(om, esquema, tab, coluna, [tag_label(f"{GLOSSARIO}.{nome}", glossario=True)])
    print(f"== glossário {GLOSSARIO}: {len(TERMOS)} termos, {associados} campos associados")


# ---------------------------------------------------------------- linhagem
ARESTAS = [
    ("bronze.catalogo", "silver.conteudo", "Hop silver_conteudo: padroniza tipo/categoria/nível, deduplica por conteudo_id, envia inválidos à quarentena."),
    ("bronze.interacoes", "silver.interacao", "Hop silver_interacao: tipa datas e números, valida faixa e referência a silver.conteudo, deduplica pela chave de negócio."),
    ("bronze.comentarios", "silver.comentario", "Hop silver_comentario: normaliza tags, valida nota 1-5 e referência a silver.conteudo."),
    ("bronze.catalogo", "quarentena.registro", "Registros do catálogo que violam regra do contrato Silver."),
    ("bronze.interacoes", "quarentena.registro", "Interações rejeitadas pela Silver."),
    ("bronze.comentarios", "quarentena.registro", "Comentários rejeitados pela Silver."),
    ("silver.conteudo", "gold.dim_conteudo", "gold.publicar: cópia 1:1 por conteudo_id com execucao_id da publicação."),
    ("silver.interacao", "gold.fato_engajamento_dia", "gold.publicar: GROUP BY conteudo_id, data_hora::date; conclusão = 'conclusão' ou percentual >= 100."),
    ("silver.interacao", "gold.kpi_evolucao_dia", "gold.publicar: GROUP BY data_hora::date; usuarios_ativos = COUNT(DISTINCT usuario_id)."),
    ("silver.interacao", "gold.kpi_geral", "gold.publicar: usuarios_ativos = COUNT(DISTINCT usuario_id); taxa de conclusão global."),
    ("silver.interacao", "gold.kpi_desempenho_categoria", "gold.publicar: JOIN com silver.conteudo, GROUP BY categoria, tipo."),
    ("silver.conteudo", "gold.kpi_desempenho_categoria", "gold.publicar: dimensão categoria e tipo."),
    ("silver.interacao", "gold.kpi_engajamento_formato", "gold.publicar: GROUP BY tipo do conteúdo."),
    ("silver.conteudo", "gold.kpi_engajamento_formato", "gold.publicar: formato e carga horária."),
    ("public.recomendacao", "gold.kpi_conversao_recomendacao", "gold.publicar: último lote de recomendação do Desafio 1 x silver.interacao."),
    ("silver.interacao", "gold.kpi_conversao_recomendacao", "gold.publicar: recomendação convertida = interação do mesmo usuário e conteúdo."),
    ("gold.kpi_conversao_recomendacao", "gold.kpi_geral", "gold.publicar: taxa_conversao_recomendacao_pct."),
    ("silver.conteudo", "mestres.conteudo_mestre", "mestres.consolidar: match por título normalizado + tipo + autor; sobrevivência por atributo."),
    ("silver.conteudo", "mestres.correspondencia_conteudo", "mestres.consolidar: conteudo_id -> mestre_id."),
    ("silver.interacao", "lgpd.vw_interacao_pseudonimizada", "usuario_id trocado por pseudo_id via lgpd_restrito.correspondencia_usuario."),
    ("silver.comentario", "lgpd.vw_comentario_mascarado", "comentário truncado e pseudo_id."),
    ("gold.dim_conteudo", "lgpd.conteudo_publico", "lgpd.atualizar: autor mascarado e sha256 com salt."),
]

LINHAGEM_COLUNA_USUARIOS = {
    ("silver.interacao", "gold.kpi_geral"): [
        ("usuario_id", "usuarios_ativos", "COUNT(DISTINCT usuario_id)"),
        ("percentual_conclusao", "taxa_conclusao_pct", "conclusões / (inícios + visualizações)"),
    ],
    ("silver.interacao", "gold.kpi_evolucao_dia"): [
        ("usuario_id", "usuarios_ativos", "COUNT(DISTINCT usuario_id) por dia"),
        ("data_hora", "data", "data_hora::date"),
    ],
}


def ref_tabela(om: OM, nome: str) -> dict | None:
    esquema, tab = nome.split(".")
    t = tabela(om, esquema, tab)
    return {"id": t["id"], "type": "table"} if t else None


def pipeline_hop(om: OM) -> dict | None:
    try:
        om.put("/services/pipelineServices", {
            "name": "apache_hop",
            "serviceType": "CustomPipeline",
            "description": "Apache Hop 2.19.0 - projeto desafio_dados_2, ambiente docker-env.",
            "connection": {"config": {"type": "CustomPipeline"}},
        })
        p = om.put("/pipelines", {
            "name": "orquestrador",
            "displayName": "Workflow orquestrador (hop/workflows/orquestrador.hwf)",
            "service": "apache_hop",
            "description": "Bronze -> Silver -> Qualidade -> Gate -> Gold -> Metadados -> Resumo.",
            "tasks": [{"name": n, "displayName": n} for n in
                      ("bronze", "silver", "qualidade", "gate_qualidade", "gold", "metadados", "resumo")],
        })
        return {"id": p["id"], "type": "pipeline"}
    except RuntimeError as erro:
        print(f"   aviso: pipeline Hop não registrado ({erro})")
        return None


def adicionar_aresta(om: OM, origem: dict, destino: dict, descricao: str, pipeline=None, colunas=None) -> bool:
    detalhes = {"description": descricao}
    if pipeline:
        detalhes["pipeline"] = pipeline
    if colunas:
        detalhes["columnsLineage"] = colunas
    try:
        om.put("/lineage", {"edge": {"fromEntity": origem, "toEntity": destino, "lineageDetails": detalhes}})
        return True
    except RuntimeError as erro:
        print(f"   aviso: aresta não registrada ({erro})")
        return False


def entidade_superset(om: OM, caminho: str, trecho: str) -> dict | None:
    try:
        itens = om.get(f"{caminho}?service={SERVICO_SUPERSET}&limit=100")["data"]
    except RuntimeError:
        return None
    for item in itens:
        if trecho.lower() in (item.get("displayName") or item["name"]).lower():
            return item
    return None


def linhagem(om: OM) -> None:
    pipeline = pipeline_hop(om)
    ok = 0
    for origem, destino, descricao in ARESTAS:
        a, b = ref_tabela(om, origem), ref_tabela(om, destino)
        if not (a and b):
            print(f"   aviso: {origem} ou {destino} não catalogada")
            continue
        colunas = None
        if (origem, destino) in LINHAGEM_COLUNA_USUARIOS:
            colunas = [
                {"fromColumns": [f"{fqn(*origem.split('.'))}.{de}"], "toColumn": f"{fqn(*destino.split('.'))}.{para}", "function": funcao}
                for de, para, funcao in LINHAGEM_COLUNA_USUARIOS[(origem, destino)]
            ]
        usa_pipeline = pipeline if origem.split(".")[0] in ("bronze", "silver") and destino.split(".")[0] in ("silver", "gold", "quarentena") else None
        ok += adicionar_aresta(om, a, b, descricao, usa_pipeline, colunas)

    dashboard = entidade_superset(om, "/dashboards", "Plataforma Educacional")
    modelo = entidade_superset(om, "/dashboard/datamodels", "vds_interacoes_dia_categoria")
    if dashboard:
        destino_dash = {"id": dashboard["id"], "type": "dashboard"}
        for tab in ("gold.kpi_geral", "gold.kpi_desempenho_categoria", "gold.kpi_evolucao_dia"):
            ref = ref_tabela(om, tab)
            if ref:
                ok += adicionar_aresta(om, ref, destino_dash, f"Dataset físico {tab} usado por gráfico do dashboard.")
        if modelo:
            ref_modelo = {"id": modelo["id"], "type": "dashboardDataModel"}
            for tab in ("gold.fato_engajamento_dia", "gold.dim_conteudo"):
                ref = ref_tabela(om, tab)
                if ref:
                    ok += adicionar_aresta(om, ref, ref_modelo, "Consulta 1 de sql/sql_lab.sql (JOIN fato x dimensão).")
            ok += adicionar_aresta(om, ref_modelo, destino_dash, "Dataset virtual do SQL Lab que alimenta 'Evolução Temporal de Interações'.")
        else:
            print("   aviso: dataset virtual não encontrado no serviço Superset; ver documentacao/linhagem.md")
    else:
        print("   aviso: dashboard do Superset não encontrado; rode a ingestão do Superset")
    print(f"== linhagem: {ok} arestas registradas")


def reindexar(om: OM) -> None:
    # A tela Explore lê do Elasticsearch; após recriar os containers o índice pode
    # ficar vazio mesmo com as entidades gravadas no banco do OpenMetadata.
    om.req("POST", "/apps/trigger/SearchIndexingApplication", {})
    total = 0
    for _ in range(24):
        time.sleep(5)
        total = om.get("/search/query?q=*&index=table_search_index&size=0")["hits"]["total"]["value"]
        if total >= om.get("/tables?limit=1")["paging"]["total"]:
            break
    print(f"== índice de busca: {total} tabelas visíveis no Explore")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sem-ingestao", action="store_true", help="Só aplica governança e linhagem.")
    args = parser.parse_args()

    env = ler_env()
    om = login(env)
    versao = om.get("/system/version")
    print(f"OpenMetadata {versao.get('version')}")
    if not args.sem_ingestao:
        jwt = token_bot(om, env)
        ingerir(env, jwt, "postgres.yaml")
        try:
            ingerir(env, jwt, "superset.yaml")
        except RuntimeError as erro:
            print(f"   aviso: {erro}")

    times = criar_times(om)
    descrever(om, times)
    classificar(om)
    glossario(om, times)
    linhagem(om)
    reindexar(om)
    print("Catálogo: http://localhost:8585/explore/tables | Glossário: http://localhost:8585/glossary")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as erro:
        print(f"ERRO: {erro}", file=sys.stderr)
        sys.exit(1)
