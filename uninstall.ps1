# Windows uninstall for the cloudflare-image-gen skill. Finds and removes, after asking:
#   - links to this folder left in %USERPROFILE%\.claude\skills by older installers (no prompt; files stay)
#   - a manually copied skill folder in %USERPROFILE%\.claude\skills
#   - the saved Cloudflare keys (%USERPROFILE%\.config\cloudflare-image-gen)
#   - CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN user environment variables
# The copy uploaded to your Claude account is managed by the app: the script shows where it is and
# tells you to remove it in Claude (Customize > Skills); deleting it here would just re-download it.
# This claude-skills folder is never touched.
# Run:  powershell -ExecutionPolicy Bypass -File D:\claude-skills\uninstall.ps1 [-Yes]
param([switch]$Yes)   # -Yes answers yes to every question

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path $PSScriptRoot).Path.TrimEnd('\')
. (Join-Path $source 'lib\skill-paths.ps1')
$removed = 0

# 1. Links left by older installers (only the links; the files they point to stay).
Remove-LinksInto $source | ForEach-Object { Write-Host "Removed old link: $_"; $removed++ }

# 2. A real (copied) skill folder in the global Claude skills folder.
$localCopy = Join-Path $ClaudeSkillsDir $SkillName
$item = Get-Item -LiteralPath $localCopy -Force -ErrorAction SilentlyContinue
if ($item -and $item.PSIsContainer -and -not $item.LinkType -and (Test-Path -LiteralPath (Join-Path $localCopy 'SKILL.md'))) {
    if (Confirm-Action "Delete the copied skill folder $localCopy ?" $Yes) {
        Remove-Item -LiteralPath $localCopy -Recurse -Force
        Write-Host "Deleted $localCopy"; $removed++
    }
}

# 3. Saved Cloudflare keys.
if (Test-Path -LiteralPath $CredentialsDir) {
    if (Confirm-Action "Delete the saved Cloudflare keys in $CredentialsDir ?" $Yes) {
        Remove-Item -LiteralPath $CredentialsDir -Recurse -Force
        Write-Host "Deleted $CredentialsDir"; $removed++
    }
}

# 4. User environment variables (other tools may use them too, so ask).
$setVars = @($CredentialVars | Where-Object { [Environment]::GetEnvironmentVariable($_, 'User') })
if ($setVars.Count -gt 0) {
    if (Confirm-Action "Remove user environment variables $($setVars -join ', ') (other tools may use them)?" $Yes) {
        $setVars | ForEach-Object { [Environment]::SetEnvironmentVariable($_, $null, 'User'); Write-Host "Removed $_"; $removed++ }
    }
}

# 5. The copy from your Claude account: report only.
$copies = @(Find-AccountSkillCopies)
Write-Host ''
if ($copies.Count -gt 0) {
    Write-Host 'The skill is still installed from your Claude account:'
    $copies | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Remove it in Claude: Customize > Skills > cloudflare-image-gen > ... > Delete (or switch it off).'
    Write-Host 'That removes it from every computer signed in to your account.'
} else {
    Write-Host 'The skill is not installed from your Claude account on this computer.'
}

Write-Host ''
Write-Host $(if ($removed -gt 0) { "Done: removed $removed item(s). Restart Claude to apply." } else { 'Nothing removed.' })
