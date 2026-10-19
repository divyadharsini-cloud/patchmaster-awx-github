$ErrorActionPreference = "Stop"
$root = "C:\Program Files\EndpointAgent"
$data = "C:\ProgramData\EndpointAgent"
$api = if ($env:PATCHMASTER_API_URL) { $env:PATCHMASTER_API_URL } else { "http://172.17.6.142:5000" }
$bootstrap = $env:PATCHMASTER_BOOTSTRAP_TOKEN
if ([string]::IsNullOrWhiteSpace($bootstrap)) { throw "Set PATCHMASTER_BOOTSTRAP_TOKEN in the deployment process before running this installer." }
if (-not $api.StartsWith("http://172.17.6.142:5000", [StringComparison]::OrdinalIgnoreCase) -and -not $api.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected API URL. Use the approved test API URL or HTTPS." }
New-Item -ItemType Directory -Force -Path $root,$data,(Join-Path $data "logs") | Out-Null
Copy-Item ".\endpoint-agent.exe" (Join-Path $root "endpoint-agent.exe") -Force
$configPath = Join-Path $data "config.json"
if (-not (Test-Path $configPath)) { Copy-Item ".\config.windows.example.json" $configPath }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$config.api_base_url = $api
$config.allow_insecure_http = $api.StartsWith("http://", [StringComparison]::OrdinalIgnoreCase)
$config.bootstrap_token = $bootstrap
$configJson = $config | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($configPath, $configJson, ([System.Text.UTF8Encoding]::new($false)))
# Restrict the bootstrap secret to SYSTEM and local Administrators until enrollment completes.
& icacls $data /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
$exe = Join-Path $root "endpoint-agent.exe"
$action = New-ScheduledTaskAction -Execute $exe -Argument "-config `"$configPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName "EndpointAgentV1" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "PatchMaster controlled-test endpoint agent" -Force | Out-Null
Write-Host "Installed PatchMaster test agent. Starting enrollment/check-in..."
Start-ScheduledTask -TaskName "EndpointAgentV1"
