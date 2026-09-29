# RF16-RF18 / RF26 - Superset sobre a Gold: datasets fisicos e virtuais, os 3 graficos
# do estudante 3, filtros globais, filtro cruzado e alerta.
# Uso: .\scripts\06_superset.ps1 [-AguardarAlerta] [-DemonstrarDisparo]
#   -AguardarAlerta     espera a primeira avaliacao do alerta pelo Celery beat (ate 6 min)
#   -DemonstrarDisparo  cria um alerta temporario com limite de 12% (acima do valor atual),
#                       espera o e-mail chegar no Mailpit e remove o alerta temporario
param([switch]$AguardarAlerta, [switch]$DemonstrarDisparo)

. "$PSScriptRoot\_comum.ps1"

Write-Etapa "Subindo Superset, worker, beat, Redis e Mailpit"
Invoke-Docker compose up -d redis mailpit superset superset_worker superset_beat
if (-not (Wait-Http 'http://localhost:8088/health' 300)) { throw "Superset nao respondeu em http://localhost:8088" }

Write-Etapa "Provisionando datasets, graficos, filtros e alerta"
$ErrorActionPreference = 'Continue'
$saida = docker exec desafio_superset python /app/setup_superset_internal.py 2>&1
$codigo = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$saida | Where-Object { $_ -notmatch 'WARNING|DeprecationWarning|warnings.warn|^\s*$|logging' } | ForEach-Object { Write-Host $_ }
if ($codigo -ne 0) { throw "setup_superset_internal.py falhou" }

$avaliacao = $saida | Select-String 'AVALIACAO_ALERTA' | Select-Object -Last 1
New-Item -ItemType Directory -Force superset/exportacao_e_evidencias | Out-Null
"$(Get-Date -Format s) $($avaliacao.Line)" | Add-Content superset/exportacao_e_evidencias/avaliacao_alerta.log -Encoding utf8

if ($AguardarAlerta) {
    Write-Etapa "Aguardando o Celery beat avaliar o alerta"
    $py = @"
from superset.app import create_app
app = create_app()
with app.app_context():
    from superset import db
    from superset.reports.models import ReportExecutionLog, ReportSchedule
    a = db.session.query(ReportSchedule).filter_by(name='Convers\u00e3o de recomenda\u00e7\u00e3o abaixo de 8%').one()
    for l in db.session.query(ReportExecutionLog).filter_by(report_schedule_id=a.id).order_by(ReportExecutionLog.id.desc()).limit(3):
        print('LOG_ALERTA', l.scheduled_dttm, l.state, l.value, l.error_message)
"@
    $limite = (Get-Date).AddMinutes(6)
    do {
        Start-Sleep -Seconds 30
        $ErrorActionPreference = 'Continue'
        $logs = docker exec desafio_superset python -c $py 2>&1 | Select-String 'LOG_ALERTA'
        $ErrorActionPreference = 'Stop'
    } until ($logs -or (Get-Date) -gt $limite)
    $logs | ForEach-Object { Write-Host $_.Line }
    $logs | ForEach-Object { $_.Line } | Add-Content superset/exportacao_e_evidencias/avaliacao_alerta.log -Encoding utf8
}

if ($DemonstrarDisparo) {
    Write-Etapa "Demonstracao de disparo: alerta temporario com limite de 12%"
    $destinatario = ([regex]'destinatario=(\S+)').Match(($saida -join "`n")).Groups[1].Value
    $inicio = (Get-Date).ToUniversalTime()
    $ErrorActionPreference = 'Continue'
    docker exec -e ALERTA_DEMO_LIMITE=12 desafio_superset python /app/setup_superset_internal.py 2>&1 |
        Select-String 'ALERTA_DEMO' | ForEach-Object { Write-Host $_.Line }
    $ErrorActionPreference = 'Stop'
    $limite = (Get-Date).AddMinutes(4)
    $msg = $null
    do {
        Start-Sleep -Seconds 20
        $msg = (Invoke-RestMethod 'http://localhost:8025/api/v1/messages').messages |
            Where-Object { ($_.To | ForEach-Object { $_.Address }) -contains $destinatario -and ([datetime]$_.Created).ToUniversalTime() -gt $inicio } |
            Select-Object -First 1
    } until ($msg -or (Get-Date) -gt $limite)
    $ErrorActionPreference = 'Continue'
    docker exec desafio_superset python /app/setup_superset_internal.py *> $null
    $ErrorActionPreference = 'Stop'
    if (-not $msg) { throw "Nenhum e-mail para $destinatario chegou ao Mailpit em 4 minutos (veja: docker logs desafio_superset_worker)" }
    $linha = "$(Get-Date -Format s) EMAIL_ALERTA: para=$($msg.To[0].Address) assunto='$($msg.Subject)' enviado=$($msg.Created)"
    Write-Host $linha
    $linha | Add-Content superset/exportacao_e_evidencias/avaliacao_alerta.log -Encoding utf8
    Write-Host "Alerta temporario removido. E-mail visivel em http://localhost:8025"
}

Write-Host ""
Write-Host "Dashboard: http://localhost:8088/superset/dashboard/plataforma-educacional-kpis/"
Write-Host "SQL Lab:   http://localhost:8088/sqllab/  (consultas em sql/sql_lab.sql)"
Write-Host "Alertas:   http://localhost:8088/alert/list/"
Write-Host "E-mails:   http://localhost:8025 (Mailpit, SMTP ficticio)"
