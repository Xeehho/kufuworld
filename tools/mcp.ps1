# Minimal MCP streamable-HTTP client for the godot-ai server (http://127.0.0.1:8000/mcp)
# Usage:
#   powershell -File tools\mcp.ps1 -Tool tools/list
#   powershell -File tools\mcp.ps1 -Tool tools/call -ToolName editor_screenshot -ArgumentsJson '{"session_id":"..."}'
param(
  [Parameter(Mandatory=$true)][string]$Method,     # e.g. tools/list | tools/call | initialize
  [string]$ToolName = "",
  [string]$ArgumentsJson = "{}",
  [string]$BaseUrl = "http://127.0.0.1:8000/mcp",
  [int]$TimeoutSec = 90
)
$ErrorActionPreference = "Stop"
$stateDir = Join-Path $PSScriptRoot "_mcp_state"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$sessFile = Join-Path $stateDir "session_id.txt"
$idFile   = Join-Path $stateDir "next_id.txt"

function Get-NextId {
  $id = 1
  if (Test-Path $idFile) { $id = [int](Get-Content $idFile -Raw) + 1 }
  Set-Content -Path $idFile -Value $id
  return $id
}

function Post-Mcp($bodyObj) {
  $json = $bodyObj | ConvertTo-Json -Depth 16 -Compress
  $tmp = Join-Path $stateDir "req.json"
  [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
  $hdrFile = Join-Path $stateDir "resp_headers.txt"
  $outFile = Join-Path $stateDir "resp_body.txt"
  $extra = @()
  if (Test-Path $sessFile) {
    $sid = (Get-Content $sessFile -Raw).Trim()
    if ($sid) { $extra += @("-H", "Mcp-Session-Id: $sid") }
  }
  curl.exe -s -S -X POST $BaseUrl -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" @extra -o $outFile -D $hdrFile -m $TimeoutSec --data-binary "@$tmp"
  if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" }
  $hdrLines = Get-Content $hdrFile
  $sid = $null
  foreach ($h in $hdrLines) { if ($h -match '(?i)^mcp-session-id:\s*(.+?)\s*$') { $sid = $Matches[1] } }
  if ($sid -and -not (Test-Path $sessFile)) { Set-Content -Path $sessFile -Value $sid }
  $body = Get-Content $outFile -Raw
  if ($body -match '(?m)^data:') {
    $datas = @()
    foreach ($line in ($body -split "`r?`n")) {
      if ($line -match '^data:\s*(.*)$') { $datas += $Matches[1] }
    }
    return ($datas -join "`n")
  }
  return $body
}

# Initialize once per state dir
if (-not (Test-Path $sessFile)) {
  $initResp = Post-Mcp @{ jsonrpc="2.0"; id=(Get-NextId); method="initialize"; params=@{
    protocolVersion="2025-03-26"; capabilities=@{}; clientInfo=@{ name="dsh-agent"; version="1.0" } } }
  Write-Output "=== INIT RESPONSE ==="
  Write-Output $initResp
  Post-Mcp @{ jsonrpc="2.0"; method="notifications/initialized" } | Out-Null
}

if ($Method -eq "initialize") {
  Write-Output "(already initialized; session id: $(Get-Content $sessFile -Raw))"
  return
}

if ($Method -eq "tools/call") {
  $args = ConvertFrom-Json $ArgumentsJson
  $resp = Post-Mcp @{ jsonrpc="2.0"; id=(Get-NextId); method="tools/call"; params=@{ name=$ToolName; arguments=$args } }
} else {
  $resp = Post-Mcp @{ jsonrpc="2.0"; id=(Get-NextId); method=$Method; params=@{} }
}
Write-Output "=== RESPONSE ==="
Write-Output $resp
