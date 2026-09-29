# RF22 - execucao agendada do workflow orquestrador pelo Agendador de Tarefas do Windows.
# Uso: .\scripts\agendar_windows.ps1 [-Hora 06:00] [-Remover]
# A tarefa roda o workflow Hop e, se o OpenMetadata estiver no ar, atualiza o catalogo.
param([string]$Hora = '06:00', [switch]$Remover)

$ErrorActionPreference = 'Stop'
$nome = 'DesafioDados2-Orquestrador'
$raiz = Split-Path -Parent $PSScriptRoot

if ($Remover) {
    Unregister-ScheduledTask -TaskName $nome -Confirm:$false
    Write-Host "Tarefa $nome removida."
    return
}

$comando = "Set-Location '$raiz'; " +
           "`$id = 'agendado-' + (Get-Date -Format 'yyyyMMdd-HHmm'); " +
           "& '.\scripts\02_hop_pipeline.ps1' -ExecucaoId `$id *> 'hop\evidencias\ultima_execucao_agendada.log'; " +
           "try { & '.\scripts\07_openmetadata_catalogo.ps1' -SemIngestao:`$false *>> 'hop\evidencias\ultima_execucao_agendada.log' } catch { }"
$acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$comando`""
$gatilho = New-ScheduledTaskTrigger -Daily -At $Hora
Register-ScheduledTask -TaskName $nome -Action $acao -Trigger $gatilho -Description 'Workflow Hop Bronze>Silver>Qualidade>Gold>Metadados (Desafio 2)' -Force | Out-Null
Write-Host "Tarefa '$nome' agendada todo dia as $Hora. Ver: Get-ScheduledTask -TaskName $nome"
Write-Host "Execucao imediata para teste: Start-ScheduledTask -TaskName $nome"
