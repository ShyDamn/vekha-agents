$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Net.Http
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
# Bound stdin before ReadLine could allocate an arbitrarily large request.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class VekhaInput {
  public static string ReadLine(TextReader reader) {
    var text = new StringBuilder();
    int value;
    while ((value = reader.Read()) != -1) {
      if (value == '\n') return text.ToString().TrimEnd('\r');
      if (text.Length >= 524288) throw new InvalidDataException("Request too large");
      text.Append((char)value);
    }
    return text.Length == 0 ? null : text.ToString();
  }
}
'@
$credentialPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Synapsea\Vekha\connections\codex.key'
try {
  $secure = Get-Content -LiteralPath $credentialPath -Raw | ConvertTo-SecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
  if ($token -cnotmatch '^vkh_[A-Za-z0-9_-]{43}$') { throw 'Invalid key' }
} catch {
  [Console]::Error.WriteLine('Vekha is not connected. Open Connect-Vekha.vbs from the Vekha plugin package, then open a new Codex chat.')
  exit 1
}
$handler = New-Object Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$client = New-Object Net.Http.HttpClient($handler)
$client.Timeout = [TimeSpan]::FromSeconds(45)
$client.MaxResponseContentBufferSize = 8388608
$client.DefaultRequestHeaders.Authorization = New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$token)
$token = $null
$client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
$client.DefaultRequestHeaders.Accept.ParseAdd('text/event-stream')
$protocol = $null
try {
  while ($null -ne ($line = [VekhaInput]::ReadLine([Console]::In))) {
    if ([Text.Encoding]::UTF8.GetByteCount($line) -gt 524288) { exit 1 }
    $message = $null; $response = $null; $requestBody = $null
    try {
      $message = $line | ConvertFrom-Json
      if ($message -is [Array] -or $message.jsonrpc -ne '2.0' -or $message.method -isnot [string] -or !$message.method) { throw 'Invalid RPC' }
      if ($protocol) { $client.DefaultRequestHeaders.Remove('MCP-Protocol-Version') | Out-Null; $client.DefaultRequestHeaders.Add('MCP-Protocol-Version',$protocol) }
      $requestBody = [Net.Http.StringContent]::new($line,[Text.Encoding]::UTF8,'application/json')
      $response = $client.PostAsync('https://vekha.synapsea.agency/api/v1/ai/mcp',$requestBody).GetAwaiter().GetResult()
      if (!$response.IsSuccessStatusCode) { throw 'Remote error' }
      if ($null -eq $message.id -or [int]$response.StatusCode -in @(202,204)) { continue }
      if ($response.Content.Headers.ContentLength -gt 8388608) { throw 'Response too large' }
      $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
      $memory = New-Object IO.MemoryStream
      try {
        $buffer = New-Object byte[] 65536
        while (($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
          if ($memory.Length+$count -gt 8388608) { throw 'Response too large' }
          $memory.Write($buffer,0,$count)
        }
        $output = [Text.Encoding]::UTF8.GetString($memory.ToArray())
      } finally { $memory.Dispose(); $stream.Dispose() }
      $parsed = $output | ConvertFrom-Json
      if ($parsed -is [Array] -or $parsed.jsonrpc -ne '2.0' -or ($parsed.id | ConvertTo-Json -Compress) -cne ($message.id | ConvertTo-Json -Compress)) { throw 'Mismatched response' }
      if ($message.method -eq 'initialize' -and $parsed.result.protocolVersion) {
        if ($parsed.result.protocolVersion -notmatch '^20\d{2}-\d{2}-\d{2}$') { throw 'Invalid protocol' }
        $protocol = [string]$parsed.result.protocolVersion
      }
      # stdio MCP requires one JSON message per line, even if HTTP was pretty-printed.
      [Console]::Out.WriteLine(($parsed | ConvertTo-Json -Compress -Depth 100))
    } catch {
      if ($null -ne $message.id) {
        $text = if ($response -and [int]$response.StatusCode -eq 401) { 'Vekha key expired or was revoked. Open Connect-Vekha.vbs to reconnect.' } else { 'Vekha request failed. Retry the same request; do not assume a write failed.' }
        [Console]::Out.WriteLine((@{jsonrpc='2.0';id=$message.id;error=@{code=-32000;message=$text}} | ConvertTo-Json -Compress -Depth 8))
      }
    } finally { if ($response) { $response.Dispose() }; if ($requestBody) { $requestBody.Dispose() } }
  }
} catch {
  [Console]::Error.WriteLine('Vekha input is invalid or too large.')
  exit 1
} finally { $client.Dispose(); $handler.Dispose() }
