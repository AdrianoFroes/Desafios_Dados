# RF24 / RF25 - Parquet particionado e pipeline Apache Beam (DirectRunner + Spark).
# Uso: .\scripts\03_beam.ps1 [-ExecucaoId gold-local-1] [-PularSpark]
#   Sem -PularSpark: sobe o job server Spark (apache/beam_spark3_job_server:2.76.0)
#   e roda o cliente num container na mesma rede, porque o worker Python precisa
#   ser alcancado pelo executor Spark em localhost.
param([string]$ExecucaoId = 'gold-local-1', [switch]$PularSpark)

. "$PSScriptRoot\_comum.ps1"

if ($PularSpark) {
    Write-Etapa "DirectRunner local (python beam/pipeline.py --pular-spark)"
    $ErrorActionPreference = 'Continue'
    & $Py beam/pipeline.py --execucao-id $ExecucaoId --pular-spark
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw "Beam DirectRunner falhou" }
    return
}

Write-Etapa "Job server Spark"
$existe = docker ps -a --filter name=^beam_spark_job$ --format '{{.Names}}'
if ($existe) { docker rm -f beam_spark_job | Out-Null }
Invoke-Docker run -d --name beam_spark_job -p 8099:8099 -p 8098:8098 -p 8097:8097 `
    apache/beam_spark3_job_server:2.76.0 --job-host=0.0.0.0 --spark-master-url=local[2] | Out-Null
Start-Sleep -Seconds 15

Write-Etapa "Beam DirectRunner + Spark (cliente em container na rede do job server)"
$cmd = "pip install -q 'apache-beam==2.76.0' pyarrow psycopg2-binary python-dotenv pyyaml && " +
       "python beam/pipeline.py --execucao-id $ExecucaoId --job-endpoint localhost:8099 --artifact-endpoint localhost:8098"
$ErrorActionPreference = 'Continue'
docker run --rm --network container:beam_spark_job -v "${Raiz}:/work" -w /work `
    -e POSTGRES_HOST=host.docker.internal -e "POSTGRES_PORT=$($Cfg.POSTGRES_PORT)" `
    python:3.12-slim bash -c $cmd
$codigo = $LASTEXITCODE
docker rm -f beam_spark_job | Out-Null
$ErrorActionPreference = 'Stop'
if ($codigo -ne 0) { throw "Beam com Spark falhou (codigo $codigo)" }
Write-Host "Evidencia: beam/evidencias/medicoes.json"
