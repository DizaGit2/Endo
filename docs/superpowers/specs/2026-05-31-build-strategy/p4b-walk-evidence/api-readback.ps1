# api-readback.ps1 — read a walk account's stored state through the live API, the way the 2026-08-25 walk did.
# Password grant on the confidential `api` client, exactly as backend/tests/Lumen.IntegrationTests/TestFixtures.cs::GetUserTokenAsync.
# Windows PowerShell 5.1. Usage:
#   powershell -File api-readback.ps1 -Email you@example.com -Password '...' /me /onboarding/state /cycle/day/2026-08-26
param(
  [Parameter(Mandatory = $true)][string]$Email,
  [Parameter(Mandatory = $true)][string]$Password,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths
)
$ErrorActionPreference = 'Stop'
$tok = Invoke-RestMethod -Method Post -Uri 'http://localhost:8080/realms/lumen/protocol/openid-connect/token' -ContentType 'application/x-www-form-urlencoded' -Body @{ grant_type = 'password'; client_id = 'api'; client_secret = 'dev-api-secret'; username = $Email; password = $Password; scope = 'openid' }
$h = @{ Authorization = "Bearer $($tok.access_token)" }
foreach ($p in $Paths) {
  Write-Output "=== GET $p ==="
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:8085$p" -Headers $h -UseBasicParsing
    Write-Output ("status {0}" -f $r.StatusCode)
    Write-Output $r.Content
  } catch {
    $resp = $_.Exception.Response
    if ($resp) { $sr = New-Object IO.StreamReader($resp.GetResponseStream()); Write-Output ("status {0}" -f [int]$resp.StatusCode); Write-Output $sr.ReadToEnd() } else { Write-Output $_.Exception.Message }
  }
}
