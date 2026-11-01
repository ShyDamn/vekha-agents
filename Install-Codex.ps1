param([switch]$SkipConnect)
$ErrorActionPreference = 'Stop'
# The Windows adapter owns a clear connection form and CurrentUser DPAPI storage.
# No credential is written into a manifest, environment, command or Codex config.
$source = [IO.Path]::GetFullPath($PSScriptRoot)
$destination = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Synapsea\Vekha\plugins-0.7.0'
if (!(Test-Path -LiteralPath (Join-Path $source 'plugins\vekha\plugin.json'))) { throw 'Extract the complete ZIP before installing.' }
function Find-VekhaCodex {
  $command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }
  # The desktop app bundles a CLI even when it has not added it to PATH. Store
  # apps can redirect LocalApplicationData, so also check the normal user path.
  $roots = @(
    (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OpenAI\Codex\bin'),
    (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\OpenAI\Codex\bin')
  ) | Select-Object -Unique
  $candidates = @(foreach ($root in $roots) {
    if (Test-Path -LiteralPath $root -PathType Container) {
      foreach ($directory in Get-ChildItem -LiteralPath $root -Directory) {
        $path = Join-Path $directory.FullName 'codex.exe'
        if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path }
      }
    }
  })
  if ($candidates.Count) { return ($candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).FullName }
  throw 'Install or open the Codex desktop app, then run this installer again.'
}
function Get-VekhaMarketplaces {
  $json = & $cli plugin marketplace list --json
  if ($LASTEXITCODE -ne 0) { throw 'Codex could not read marketplace settings. Nothing was changed.' }
  return ($json | ConvertFrom-Json).marketplaces
}
function Same-VekhaPath([string]$Left,[string]$Right) {
  # Codex may expose the same Windows source with or without its long-path prefix.
  return [IO.Path]::GetFullPath($Left.Replace('\\?\','')).TrimEnd('\','/') -ieq [IO.Path]::GetFullPath($Right.Replace('\\?\','')).TrimEnd('\','/')
}
$cli = Find-VekhaCodex
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source '.agents'), (Join-Path $source '.claude-plugin'), (Join-Path $source 'plugins') -Destination $destination -Recurse -Force
foreach ($name in @('Connect-Vekha.ps1','Connect-Vekha.vbs','Connect-Vekha.cmd','Codex-Bridge.ps1')) {
  Copy-Item -LiteralPath (Join-Path $source $name) -Destination $destination -Force
}
# Resolve a fixed executable + script path. An installed native bridge works
# without a shell-wide API-key environment variable or unsupported remote forms.
$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$mcp = @{mcpServers=@{vekha=@{type='stdio';command=$powerShell;args=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $destination 'Codex-Bridge.ps1'))}}}
[IO.File]::WriteAllText((Join-Path $destination 'plugins\vekha\mcp.json'),($mcp|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$previous = @(Get-VekhaMarketplaces | Where-Object { $_.name -eq 'synapsea-vekha' })
if ($previous.Count -gt 1) { throw 'Several Vekha marketplaces are configured. No marketplace was changed.' }
$previousRoot = if ($previous.Count) { [string]$previous[0].root } else { $null }
$moveSource = $previousRoot -and !(Same-VekhaPath $previousRoot $destination)
$previousInstalled = $false
if ($moveSource) {
  # A rollback must be possible before detaching the old source.
  $catalog = Join-Path $previousRoot '.agents\plugins\marketplace.json'
  if (!(Test-Path -LiteralPath $catalog)) { $catalog = Join-Path $previousRoot '.claude-plugin\marketplace.json' }
  if (!(Test-Path -LiteralPath $catalog) -or ([IO.File]::ReadAllText($catalog) | ConvertFrom-Json).name -ne 'synapsea-vekha') {
    throw 'The old Vekha source cannot be restored safely. No marketplace was changed.'
  }
  $installed = & $cli plugin list --marketplace synapsea-vekha --json
  if ($LASTEXITCODE -ne 0) { throw 'Codex could not read the existing Vekha installation. No marketplace was changed.' }
  $previousInstalled = @((($installed | ConvertFrom-Json).installed) | Where-Object { $_.pluginId -eq 'vekha@synapsea-vekha' }).Count -gt 0
}
$removedPrevious = $false
try {
  if ($moveSource) {
    & $cli plugin marketplace remove synapsea-vekha
    if ($LASTEXITCODE -ne 0) { throw 'Codex could not detach the old Vekha source.' }
    $removedPrevious = $true
  }
  & $cli plugin marketplace add $destination
  if ($LASTEXITCODE -ne 0) { throw 'Codex could not register the new Vekha source.' }
  & $cli plugin add 'vekha@synapsea-vekha'
  if ($LASTEXITCODE -ne 0) { throw 'Codex could not install the new Vekha plugin.' }
} catch {
  if ($removedPrevious) {
    try {
      $current = @(Get-VekhaMarketplaces | Where-Object { $_.name -eq 'synapsea-vekha' })
      if ($current.Count -and !(Same-VekhaPath ([string]$current[0].root) $destination)) {
        throw 'The Vekha source changed in another process.'
      }
      if ($current.Count) {
        & $cli plugin marketplace remove synapsea-vekha
        if ($LASTEXITCODE -ne 0) { throw 'Could not detach the failed Vekha source.' }
      }
      & $cli plugin marketplace add $previousRoot
      if ($LASTEXITCODE -ne 0) { throw 'Could not restore the previous Vekha source.' }
      if ($previousInstalled) {
        & $cli plugin add 'vekha@synapsea-vekha'
        if ($LASTEXITCODE -ne 0) { throw 'Could not restore the previous Vekha plugin.' }
      }
    } catch {
      throw "Vekha update failed and automatic rollback was incomplete. The previous source remains at: $previousRoot. Other marketplaces were not changed."
    }
    throw 'Vekha update failed. The previous Vekha source and plugin were restored; other marketplaces were not changed.'
  }
  throw
}
if (!$SkipConnect) { & (Join-Path $destination 'Connect-Vekha.ps1') }
Write-Host 'Vekha installed. Connect-Vekha.vbs opens only the key form. After connecting, open a new Codex chat; restart only if tools do not appear.'
