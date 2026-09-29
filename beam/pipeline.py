"""Parquet (RF24) e pipeline Apache Beam (RF25) sobre silver.interacao.

A agregação é o grão da gold.fato_engajamento_dia: uma linha por conteúdo e dia.
A mesma função de combinação roda no DirectRunner e no Spark (PortableRunner
apontando para o job server Spark). A regra de conclusão é a de
sql/camada_gold.sql: tipo 'conclusão' ou percentual_conclusao >= 100.

Particionamento do Parquet de entrada: ano e mês de data_hora. O filtro global
de período do Superset recorta por data, e a poda de partição mensal evita ler
o arquivo inteiro quando o recorte cabe num mês. O volume deste desafio é
pequeno; a medição registra essa limitação.

Uso, na raiz do projeto, com a Silver já carregada:

    python beam/pipeline.py --execucao-id gold-local-1
"""

from __future__ import annotations

import argparse
import csv
import json
import platform
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

import apache_beam as beam
import psycopg2
import pyarrow as pa
import pyarrow.dataset  # noqa: F401  (registra pa.dataset)
import pyarrow.parquet as pq
from apache_beam.options.pipeline_options import PipelineOptions, SetupOptions
from psycopg2.extras import RealDictCursor

RAIZ = Path(__file__).resolve().parents[1]
if str(RAIZ) not in sys.path:
    sys.path.insert(0, str(RAIZ))

from src.config import load_config  # noqa: E402

PASTA_INTERACAO = RAIZ / "dados" / "gold" / "parquet" / "interacao"
PASTA_JSON = RAIZ / "dados" / "gold" / "comparacao" / "interacao.json"
PASTA_CSV = RAIZ / "dados" / "gold" / "comparacao" / "interacao.csv"
PASTA_FATO = RAIZ / "dados" / "gold" / "parquet" / "engajamento_dia"
PASTA_EVIDENCIA = RAIZ / "beam" / "evidencias"
PASTA_QUALIDADE = RAIZ / "qualidade" / "resultados"

ESQUEMA_FATO = pa.schema(
    [
        ("conteudo_id", pa.int32()),
        ("data", pa.string()),
        ("total_interacoes", pa.int64()),
        ("visualizacoes", pa.int64()),
        ("inicios", pa.int64()),
        ("conclusoes", pa.int64()),
        ("curtidas", pa.int64()),
        ("avaliacoes", pa.int64()),
        ("soma_avaliacao", pa.int64()),
        ("tempo_total_min", pa.int64()),
        ("execucao_id", pa.string()),
        ("runner", pa.string()),
    ]
)

COLUNAS_INTERACAO = (
    "interacao_id",
    "usuario_id",
    "conteudo_id",
    "tipo_interacao",
    "data_hora",
    "tempo_consumido",
    "percentual_conclusao",
    "avaliacao_atribuida",
    "origem",
    "arquivo_origem",
    "data_hora_ingestao",
    "execucao_id",
    "data_hora_padronizacao",
)


def conectar():
    pg = load_config()["postgres"]
    return psycopg2.connect(
        user=pg["user"],
        password=pg["password"],
        dbname=pg["dbname"],
        host=pg["host"],
        port=pg["port"],
    )


def ler_silver():
    sql = f"SELECT {', '.join(COLUNAS_INTERACAO)} FROM silver.interacao"
    with conectar() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql)
            return [dict(linha) for linha in cur.fetchall()]


def _iso(valor):
    if isinstance(valor, datetime):
        return valor.isoformat(sep=" ")
    return valor


def exportar_parquet(linhas):
    if PASTA_INTERACAO.exists():
        shutil.rmtree(PASTA_INTERACAO)
    PASTA_INTERACAO.mkdir(parents=True, exist_ok=True)

    registros = []
    for linha in linhas:
        data_hora = linha["data_hora"]
        registros.append(
            {
                "interacao_id": linha["interacao_id"],
                "usuario_id": linha["usuario_id"],
                "conteudo_id": linha["conteudo_id"],
                "tipo_interacao": linha["tipo_interacao"],
                "data_hora": data_hora,
                "tempo_consumido": linha["tempo_consumido"],
                "percentual_conclusao": (
                    None
                    if linha["percentual_conclusao"] is None
                    else float(linha["percentual_conclusao"])
                ),
                "avaliacao_atribuida": linha["avaliacao_atribuida"],
                "origem": linha["origem"],
                "arquivo_origem": linha["arquivo_origem"],
                "data_hora_ingestao": linha["data_hora_ingestao"],
                "execucao_id": linha["execucao_id"],
                "data_hora_padronizacao": linha["data_hora_padronizacao"],
                "ano": f"{data_hora.year:04d}",
                "mes": f"{data_hora.month:02d}",
            }
        )

    tabela = pa.Table.from_pylist(registros)
    pq.write_to_dataset(tabela, PASTA_INTERACAO, partition_cols=["ano", "mes"])
    return registros


def medir_leitura(registros):
    PASTA_JSON.parent.mkdir(parents=True, exist_ok=True)
    payload = []
    for item in registros:
        payload.append({chave: _iso(valor) for chave, valor in item.items()})
    PASTA_JSON.write_text(
        json.dumps(payload, ensure_ascii=False),
        encoding="utf-8",
    )

    with PASTA_CSV.open("w", encoding="utf-8", newline="") as arquivo:
        escritor = csv.DictWriter(arquivo, fieldnames=list(payload[0].keys()))
        escritor.writeheader()
        escritor.writerows(payload)

    # Sem esquema explicito, versoes recentes do pyarrow inferem ano/mes como int32.
    particionamento = pa.dataset.partitioning(
        pa.schema([("ano", pa.string()), ("mes", pa.string())]), flavor="hive"
    )
    inicio = time.perf_counter()
    parquet = pq.read_table(PASTA_INTERACAO, partitioning=particionamento)
    tempo_parquet = time.perf_counter() - inicio

    inicio = time.perf_counter()
    json.loads(PASTA_JSON.read_text(encoding="utf-8"))
    tempo_json = time.perf_counter() - inicio

    inicio = time.perf_counter()
    with PASTA_CSV.open(encoding="utf-8", newline="") as arquivo:
        linhas_csv = sum(1 for _ in csv.DictReader(arquivo))
    tempo_csv = time.perf_counter() - inicio

    # Mesmo recorte de um mes: o Parquet le so a particao; JSON le tudo e filtra.
    mes_alvo = registros[0]["mes"]
    inicio = time.perf_counter()
    parquet_mes = pq.read_table(
        PASTA_INTERACAO, partitioning=particionamento, filters=[("mes", "=", mes_alvo)]
    )
    tempo_parquet_mes = time.perf_counter() - inicio
    inicio = time.perf_counter()
    json_mes = [
        item for item in json.loads(PASTA_JSON.read_text(encoding="utf-8"))
        if item["mes"] == mes_alvo
    ]
    tempo_json_mes = time.perf_counter() - inicio

    particoes = sorted(
        {
            str(caminho.relative_to(PASTA_INTERACAO).parent).replace("\\", "/")
            for caminho in PASTA_INTERACAO.rglob("*.parquet")
        }
    )
    return {
        "linhas": parquet.num_rows,
        "colunas_parquet": parquet.column_names,
        "particoes": particoes,
        "bytes_parquet": sum(
            caminho.stat().st_size for caminho in PASTA_INTERACAO.rglob("*.parquet")
        ),
        "bytes_json": PASTA_JSON.stat().st_size,
        "bytes_csv": PASTA_CSV.stat().st_size,
        "linhas_csv": linhas_csv,
        "segundos_leitura_parquet": round(tempo_parquet, 6),
        "segundos_leitura_json": round(tempo_json, 6),
        "segundos_leitura_csv": round(tempo_csv, 6),
        "recorte_um_mes": {
            "mes": mes_alvo,
            "linhas_parquet": parquet_mes.num_rows,
            "linhas_json": len(json_mes),
            "segundos_parquet_com_poda": round(tempo_parquet_mes, 6),
            "segundos_json_filtrado": round(tempo_json_mes, 6),
        },
        "tipos_preservados": {campo.name: str(campo.type) for campo in parquet.schema},
        "estrategia": "particao hive por ano e mes de data_hora",
        "justificativa": (
            "O consumo analitico filtra por periodo. A particao mensal permite "
            "poda de arquivo sem multiplicar pastas alem do que o recorte tem de meses."
        ),
        "limitacao": (
            "O recorte do desafio tem poucos milhares de linhas. Nessa escala o "
            "Parquet pode nao ser mais rapido que o JSON; o ganho aparece quando "
            "a leitura passa a ignorar meses fora do filtro."
        ),
    }


class Engajamento(beam.CombineFn):
    """Mesmas medidas de gold.fato_engajamento_dia."""

    def create_accumulator(self):
        return [0, 0, 0, 0, 0, 0, 0, 0]

    def add_input(self, acumulador, linha):
        tipo = linha["tipo_interacao"]
        percentual = float(linha["percentual_conclusao"])
        acumulador[0] += 1
        if tipo == "visualização":
            acumulador[1] += 1
        if tipo == "início":
            acumulador[2] += 1
        if tipo == "conclusão" or percentual >= 100:
            acumulador[3] += 1
        if tipo == "curtida":
            acumulador[4] += 1
        nota = linha["avaliacao_atribuida"]
        if nota is not None:
            acumulador[5] += 1
            acumulador[6] += int(nota)
        tempo = linha["tempo_consumido"]
        if tempo is not None:
            acumulador[7] += int(tempo)
        return acumulador

    def merge_accumulators(self, acumuladores):
        total = [0, 0, 0, 0, 0, 0, 0, 0]
        for item in acumuladores:
            for indice, valor in enumerate(item):
                total[indice] += valor
        return total

    def extract_output(self, acumulador):
        return acumulador


def dia_da_interacao(linha):
    data_hora = linha["data_hora"]
    if isinstance(data_hora, datetime):
        dia = data_hora.date().isoformat()
    else:
        dia = str(data_hora)[:10]
    return (int(linha["conteudo_id"]), dia), linha


def formatar_fato(elemento, execucao_id, runner):
    (conteudo_id, dia), medidas = elemento
    return {
        "conteudo_id": conteudo_id,
        "data": dia,
        "total_interacoes": medidas[0],
        "visualizacoes": medidas[1],
        "inicios": medidas[2],
        "conclusoes": medidas[3],
        "curtidas": medidas[4],
        "avaliacoes": medidas[5],
        "soma_avaliacao": medidas[6],
        "tempo_total_min": medidas[7],
        "execucao_id": execucao_id,
        "runner": runner,
    }


def executar_beam(runner, argumentos, saida, execucao_id, rotulo):
    if saida.exists():
        shutil.rmtree(saida)
    saida.mkdir(parents=True, exist_ok=True)
    padrao = str(PASTA_INTERACAO / "ano=*" / "mes=*" / "*.parquet")
    inicio = time.perf_counter()
    opcoes = PipelineOptions(argumentos)
    opcoes.view_as(SetupOptions).save_main_session = True
    with beam.Pipeline(options=opcoes) as pipeline:
        (
            pipeline
            | "LerParquet" >> beam.io.ReadFromParquet(padrao)
            | "ChaveConteudoDia" >> beam.Map(dia_da_interacao)
            | "Agregar" >> beam.CombinePerKey(Engajamento())
            | "Formatar" >> beam.Map(formatar_fato, execucao_id, rotulo)
            | "GravarParquet"
            >> beam.io.WriteToParquet(
                str(saida / "parte"),
                schema=ESQUEMA_FATO,
                num_shards=1,
                file_name_suffix=".parquet",
            )
        )
    duracao = time.perf_counter() - inicio
    tabela = pq.read_table(saida)
    return {
        "runner": runner,
        "rotulo": rotulo,
        "linhas": tabela.num_rows,
        "segundos": round(duracao, 3),
        "argumentos": argumentos,
        "saida": str(saida.relative_to(RAIZ)).replace("\\", "/"),
    }, tabela


def linhas_fato(tabela):
    colunas = [
        "conteudo_id",
        "data",
        "total_interacoes",
        "visualizacoes",
        "inicios",
        "conclusoes",
        "curtidas",
        "avaliacoes",
        "soma_avaliacao",
        "tempo_total_min",
    ]
    registros = tabela.select(colunas).to_pylist()
    return sorted(registros, key=lambda item: (item["conteudo_id"], item["data"]))


def comparar_com_gold(fato_beam):
    sql = """
        SELECT conteudo_id::int AS conteudo_id,
               data::text AS data,
               total_interacoes::bigint AS total_interacoes,
               visualizacoes::bigint AS visualizacoes,
               inicios::bigint AS inicios,
               conclusoes::bigint AS conclusoes,
               curtidas::bigint AS curtidas,
               avaliacoes::bigint AS avaliacoes,
               soma_avaliacao::bigint AS soma_avaliacao,
               tempo_total_min::bigint AS tempo_total_min
        FROM gold.fato_engajamento_dia
        ORDER BY conteudo_id, data
    """
    with conectar() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql)
            gold = [dict(linha) for linha in cur.fetchall()]
    for linha in gold:
        for coluna in (
            "total_interacoes",
            "visualizacoes",
            "inicios",
            "conclusoes",
            "curtidas",
            "avaliacoes",
            "soma_avaliacao",
            "tempo_total_min",
        ):
            linha[coluna] = int(linha[coluna])
    return {
        "linhas_gold": len(gold),
        "linhas_beam": len(fato_beam),
        "iguais": gold == fato_beam,
    }


def exportar_qualidade(execucao_id):
    PASTA_QUALIDADE.mkdir(parents=True, exist_ok=True)
    with conectar() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT execucao_id, fonte, teste, dimensao, formula, valor, limite,
                       operador, severidade, aprovado, acao, mensagem,
                       executado_em
                FROM qualidade.resultado
                WHERE execucao_id = %s
                ORDER BY teste
                """,
                (execucao_id,),
            )
            linhas = [dict(item) for item in cur.fetchall()]
    for linha in linhas:
        linha["valor"] = float(linha["valor"])
        linha["limite"] = float(linha["limite"])
        linha["executado_em"] = _iso(linha["executado_em"])
    destino = PASTA_QUALIDADE / f"{execucao_id}.json"
    destino.write_text(
        json.dumps(linhas, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return str(destino.relative_to(RAIZ)).replace("\\", "/")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--execucao-id", required=True)
    parser.add_argument(
        "--job-endpoint",
        default="localhost:8099",
        help="Job server do Spark Runner portátil.",
    )
    parser.add_argument(
        "--artifact-endpoint",
        default="localhost:8098",
        help="Serviço de artefatos do job server Spark.",
    )
    parser.add_argument(
        "--pular-spark",
        action="store_true",
        help="Executa só o DirectRunner.",
    )
    args = parser.parse_args()

    linhas = ler_silver()
    if not linhas:
        raise SystemExit("silver.interacao está vazia. Rode a Silver antes do Beam.")

    registros = exportar_parquet(linhas)
    medicao = medir_leitura(registros)
    print(
        f"Parquet {medicao['bytes_parquet']} bytes em {medicao['segundos_leitura_parquet']}s; "
        f"JSON {medicao['bytes_json']} bytes em {medicao['segundos_leitura_json']}s; "
        f"{len(medicao['particoes'])} partições."
    )

    execucoes = []
    direto, tabela_direto = executar_beam(
        "DirectRunner",
        ["--runner=DirectRunner"],
        PASTA_FATO / "direct",
        args.execucao_id,
        "direct",
    )
    execucoes.append(direto)
    fato = linhas_fato(tabela_direto)
    direto["observacao"] = (
        "A opcao informada foi --runner=DirectRunner. No Apache Beam 2.76 "
        "esse runner executa o pipeline no Prism local quando todas as "
        "transformacoes sao compativeis."
    )
    print(f"DirectRunner: {direto['linhas']} linhas em {direto['segundos']}s.")

    spark = {"executado": False}
    anterior = PASTA_EVIDENCIA / "medicoes.json"
    if args.pular_spark and anterior.exists():
        registro_anterior = json.loads(anterior.read_text(encoding="utf-8"))
        if registro_anterior.get("spark", {}).get("executado"):
            spark = dict(registro_anterior["spark"])
            spark.setdefault("execucao_id_origem", registro_anterior["execucao_id"])
            spark["observacao"] = (
                "Spark nao rodou nesta execucao (--pular-spark); registro mantido da execucao anterior."
            )
    if not args.pular_spark:
        try:
            resultado, tabela_spark = executar_beam(
                "PortableRunner",
                [
                    "--runner=PortableRunner",
                    f"--job_endpoint={args.job_endpoint}",
                    f"--artifact_endpoint={args.artifact_endpoint}",
                    "--environment_type=LOOPBACK",
                ],
                PASTA_FATO / "spark",
                args.execucao_id,
                "spark",
            )
            fato_spark = linhas_fato(tabela_spark)
            resultado["igual_ao_direct"] = fato_spark == fato
            execucoes.append(resultado)
            spark = {"executado": True, **resultado}
            print(
                f"Spark/PortableRunner: {resultado['linhas']} linhas em "
                f"{resultado['segundos']}s; igual ao DirectRunner: "
                f"{resultado['igual_ao_direct']}."
            )
        except Exception as erro:
            spark = {
                "executado": False,
                "job_endpoint": args.job_endpoint,
                "erro": str(erro),
            }
            print(f"Spark não concluiu: {erro}")

    comparacao_gold = comparar_com_gold(fato)
    print(
        "Gold x DirectRunner: "
        f"{comparacao_gold['linhas_gold']} x {comparacao_gold['linhas_beam']} "
        f"iguais={comparacao_gold['iguais']}."
    )

    evidencia_qualidade = None
    try:
        evidencia_qualidade = exportar_qualidade(args.execucao_id)
    except Exception as erro:
        evidencia_qualidade = f"nao exportada: {erro}"

    PASTA_EVIDENCIA.mkdir(parents=True, exist_ok=True)
    medicoes = {
        "execucao_id": args.execucao_id,
        "volume_silver_interacao": len(linhas),
        "parquet": medicao,
        "beam": execucoes,
        "spark": spark,
        "comparacao_gold": comparacao_gold,
        "qualidade": evidencia_qualidade,
        "regra": "conclusao = tipo conclusão OU percentual_conclusao >= 100",
        "configuracao": {
            "python": platform.python_version(),
            "apache_beam": beam.__version__,
            "pyarrow": pa.__version__,
            "spark_job_server": "apache/beam_spark3_job_server:2.76.0 (--spark-master-url=local[2])",
            "sistema": platform.platform(),
        },
    }
    destino = PASTA_EVIDENCIA / "medicoes.json"
    destino.write_text(
        json.dumps(medicoes, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Evidência em {destino}.")
    if not spark.get("executado") and not args.pular_spark:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
