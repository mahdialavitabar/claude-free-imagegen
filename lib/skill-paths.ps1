# Shared helpers for install.ps1 and uninstall.ps1 (dot-sourced; not meant to be run directly).

$SkillName = 'cloudflare-image-gen'
$ClaudeSkillsDir = Join-Path $env:USERPROFILE '.claude\skills'
$CredentialsDir = Join-Path $env:USERPROFILE '.config\cloudflare-image-gen'
$CredentialsFile = Join-Path $CredentialsDir 'config.json'
$CredentialVars = @('CLOUDFLARE_ACCOUNT_ID', 'CLOUDFLARE_API_TOKEN')

# Folders where the Claude app keeps a skill uploaded to your account (Customize > Skills).
# Seen on Windows: %LOCALAPPDATA%\Claude-Data\claude_<id>\local-agent-mode-sessions\skills-plugin\<id>\<id>\skills\<name>
function Find-AccountSkillCopies([string]$name = $SkillName) {
    $patterns = @(Join-Path $ClaudeSkillsDir "synced\*\$name")
    foreach ($root in @($env:LOCALAPPDATA, $env:APPDATA) | Where-Object { $_ }) {
        $patterns += "$root\Claude*\local-agent-mode-sessions\skills-plugin\*\*\skills\$name"
        $patterns += "$root\Claude*\*\local-agent-mode-sessions\skills-plugin\*\*\skills\$name"
    }
    $patterns |
        ForEach-Object { Get-Item -Path $_ -Force -ErrorAction SilentlyContinue } |
        Where-Object { $_.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')) } |
        Select-Object -ExpandProperty FullName -Unique
}

# Removes junctions/symlinks in ~/.claude/skills that point into $source (left by older installers).
# Only the links are removed, never the files they point to. Returns the removed link paths.
function Remove-LinksInto([string]$source) {
    if (-not (Test-Path -LiteralPath $ClaudeSkillsDir)) { return }
    $source = $source.TrimEnd('\')
    Get-ChildItem -LiteralPath $ClaudeSkillsDir -Force |
        Where-Object { $_.LinkType -eq 'Junction' -or $_.LinkType -eq 'SymbolicLink' } |
        ForEach-Object {
            $linkTarget = [string]($_.Target | Select-Object -First 1)
            if ($linkTarget -and $linkTarget.TrimEnd('\').StartsWith($source, [StringComparison]::OrdinalIgnoreCase)) {
                $_.Delete()
                $_.FullName
            }
        }
}

# Reads one line; $null at end of input. Hidden input in a console, plain lines when piped.
function Read-Line([string]$prompt, [switch]$Secret) {
    if ([Console]::IsInputRedirected) {
        Write-Host -NoNewline $prompt
        $line = [Console]::In.ReadLine()
        Write-Host ''
        return $line
    }
    if (-not $Secret) { return Read-Host $prompt.TrimEnd(': ') }
    $secure = Read-Host $prompt.TrimEnd(': ') -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Asks a yes/no question (default No). Always yes when $assumeYes is set.
function Confirm-Action([string]$question, [bool]$assumeYes = $false) {
    if ($assumeYes) { Write-Host "$question [y/N]: y"; return $true }
    $answer = Read-Line "$question [y/N]: "
    return ($answer -match '^[Yy]')
}

function Hide([string]$value) { if ($value.Length -le 4) { '****' } else { '****' + $value.Substring($value.Length - 4) } }

# Warns when Node.js is missing or older than 18.
function Test-NodeVersion {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warning 'Node.js 18+ is required. Install it from https://nodejs.org (or: winget install OpenJS.NodeJS.LTS).'
        return
    }
    $major = [int](& $node.Source -p "process.versions.node.split('.')[0]")
    if ($major -lt 18) { Write-Warning "Node.js $major found; version 18 or newer is required (https://nodejs.org)." }
}
