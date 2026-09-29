# RF27-RF29 / RF32 - ingestao de metadados e governanca no OpenMetadata.
# Pre-requisitos: 01_openmetadata_up.ps1 (servidor no ar), 02 (camadas) e 05 (papel om_catalogo).
# Uso: .\scripts\07_openmetadata_catalogo.ps1 [-SemIngestao]
param([switch]$SemIngestao)

. "$PSScriptRoot\_comum.ps1"

if (-not (Wait-Http 'http://localhost:8585/api/v1/system/version' 30)) {
    throw "OpenMetadata fora do ar. Rode .\scripts\01_openmetadata_up.ps1"
}
Write-Etapa "Ingestao e governanca (openmetadata/configurar_catalogo.py)"
$argumentos = @('openmetadata/configurar_catalogo.py')
if ($SemIngestao) { $argumentos += '--sem-ingestao' }
$ErrorActionPreference = 'Continue'
& $Py @argumentos
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw "configurar_catalogo.py falhou" }
