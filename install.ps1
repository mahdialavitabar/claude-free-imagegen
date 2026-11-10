# Windows setup for the cloudflare-image-gen skill. The skill itself is installed by uploading
# cloudflare-image-gen.zip in Claude (Customize > Skills); this script adds nothing to the Claude
# folders. It finds the uploaded copy (or says how to upload it), checks Node.js, and asks for the
# Cloudflare Account ID and Workers AI API token and saves them for your user. Run it again any
# time to update them. Undo with uninstall.ps1. macOS/Linux: use install.sh.
# Run:  powershell -ExecutionPolicy Bypass -File D:\claude-skills\install.ps1

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path $PSScriptRoot).Path.TrimEnd('\')
. (Join-Path $source 'lib\skill-paths.ps1')

# Remove links that older versions of this script created in the Claude skills folder.
Remove-LinksInto $source | ForEach-Object { Write-Host "Removed old link: $_" }

Test-NodeVersion

# Is the skill installed in Claude (uploaded to your account and downloaded by the app)?
$copies = @(Find-AccountSkillCopies)
if ($copies.Count -gt 0) {
    Write-Host "Skill installed from your Claude account:"
    $copies | ForEach-Object { Write-Host "  $_" }
} else {
    $zip = Join-Path $source "$SkillName.zip"
    Write-Warning "The $SkillName skill isn't in Claude on this computer yet."
    Write-Host "  Upload $(if (Test-Path -LiteralPath $zip) { $zip } else { "$SkillName.zip" }) in Claude: Customize > Skills > upload, then restart Claude."
}

# ---- Cloudflare credentials --------------------------------------------------------------
$configDir = $CredentialsDir
$config = $CredentialsFile
$valid = '^[A-Za-z0-9_-]+$'

$currentId = ''
$currentToken = ''
if (Test-Path $config) {
    try {
        $existing = Get-Content -Raw $config | ConvertFrom-Json
        if ($existing.accountId) { $currentId = [string]$existing.accountId }
        if ($existing.apiToken) { $currentToken = [string]$existing.apiToken }
    } catch {
        Write-Warning "$config is not valid JSON; it will be replaced."
    }
}

Write-Host ''
if ($currentId -and $currentToken) {
    Write-Host "Cloudflare credentials found in $config"
    Write-Host "  Account ID: $currentId"
    Write-Host "  API token:  $(Hide $currentToken)"
    Write-Host 'Enter new values to update them, or press Enter to keep the current ones.'
} else {
    Write-Host 'Cloudflare setup: enter your Account ID and a Workers AI API token (see cloudflare-image-gen\README.md).'
}

while ($true) {
    $prompt = if ($currentId) { "Cloudflare Account ID [$currentId]: " } else { 'Cloudflare Account ID: ' }
    $accountId = Read-Line $prompt
    if ($null -eq $accountId) { Write-Warning 'No input; credentials left unchanged.'; return }
    $accountId = $accountId -replace '\s', ''
    if (-not $accountId) { $accountId = $currentId }
    if ($accountId -match $valid) { break }
    Write-Warning "The Account ID may contain only letters, digits, '-' and '_'. Try again."
}

while ($true) {
    $prompt = if ($currentToken) { "Workers AI API token [keep $(Hide $currentToken)] (hidden): " } else { 'Workers AI API token (hidden): ' }
    $apiToken = Read-Line $prompt -Secret
    if ($null -eq $apiToken) { Write-Warning 'No input; credentials left unchanged.'; return }
    $apiToken = $apiToken -replace '\s', ''
    if (-not $apiToken) { $apiToken = $currentToken }
    if ($apiToken -match $valid) { break }
    Write-Warning "The token may contain only letters, digits, '-' and '_'. Try again."
}

if ($accountId -ceq $currentId -and $apiToken -ceq $currentToken) {
    Write-Host 'Credentials unchanged.'
    return
}

# Check the pair against Cloudflare (lists one Workers AI model; uses no neurons).
try {
    Invoke-RestMethod -Method Get -TimeoutSec 15 -Headers @{ Authorization = "Bearer $apiToken" } `
        -Uri "https://api.cloudflare.com/client/v4/accounts/$accountId/ai/models/search?per_page=1" | Out-Null
    Write-Host 'Verified with Cloudflare.'
} catch {
    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'no response' }
    Write-Warning "Cloudflare rejected these credentials (HTTP $status)."
    $answer = Read-Line 'Save them anyway? [y/N]: '
    if ($answer -notmatch '^[Yy]') { Write-Host 'Not saved; credentials left unchanged.'; exit 1 }
}

New-Item -ItemType Directory -Force -Path $configDir | Out-Null
$json = [ordered]@{ accountId = $accountId; apiToken = $apiToken } | ConvertTo-Json
[IO.File]::WriteAllText($config, $json)   # UTF-8 without BOM
Write-Host "Saved to $config."

# User-level variables override the file, so keep any that exist in sync instead of leaving stale values.
foreach ($pair in @(@($CredentialVars[0], $accountId), @($CredentialVars[1], $apiToken))) {
    if ([Environment]::GetEnvironmentVariable($pair[0], 'User')) {
        [Environment]::SetEnvironmentVariable($pair[0], $pair[1], 'User')
        Write-Host "Updated user environment variable $($pair[0])."
    }
}
Write-Host 'Restart the Claude app to pick up the new credentials.'
