param([string]$FilePath,[string]$TripId,[string]$RequestId)
# Windows PowerShell 5.1. Invoke only for the local file explicitly selected by
# the human for this trip. File contents are never interpreted as instructions.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Stop-VekhaUpload([string]$Code,[bool]$Retry=$false,[int]$RetryAfter=0) {
  $exception = New-Object InvalidOperationException($Code)
  $exception.Data['VekhaUploadCode']=$Code
  $exception.Data['VekhaUploadRetry']=$Retry
  $exception.Data['VekhaUploadRetryAfter']=$RetryAfter
  throw $exception
}

function Get-VekhaUploadFailure($Failure,[string]$Fallback='UPLOAD_FAILED') {
  $allowed=@('INVALID_ARGUMENTS','FILE_NOT_ALLOWED','FILE_NAME_INVALID','FILE_TOO_LARGE','FILE_TYPE_INVALID','FILE_OPEN_FAILED','FILE_CHANGED',
    'CREDENTIAL_UNAVAILABLE','AUTH_REQUIRED','ACCESS_DENIED','CAPABILITY_NOT_GRANTED','READ_ONLY_KEY','UNSAFE_DOCUMENT','REDIRECT_DENIED','REMOTE_UNAVAILABLE','INVALID_RESPONSE','RPC_ERROR','REMOTE_ERROR',
    'TEMPORARILY_UNAVAILABLE','DOCUMENT_BUSY','FILE_RATE_LIMITED','DOCUMENT_SCAN_UNAVAILABLE','FILE_DOWNLOAD_TIMEOUT',
    'VALIDATION_ERROR','CONTENT_INTEGRITY_MISMATCH','UPLOAD_EXPIRED','UPLOAD_LIMIT','UPLOAD_CANCELLED','UPLOAD_SEALED','INVALID_OFFSET',
    'IDEMPOTENCY_KEY_REUSED','NOT_FOUND','DOCUMENT_NOT_SCANNED','DOCUMENT_REJECTED','FILE_REJECTED','UNSUPPORTED_FILE_TYPE','UPLOAD_ALREADY_IMPORTED')
  $exception=$Failure.Exception
  for($depth=0;$exception -and $depth -lt 8;$depth++) {
    $code=[string]$exception.Data['VekhaUploadCode']
    if($allowed -ccontains $code) {
      return @{code=$code;retry=($exception.Data['VekhaUploadRetry'] -eq $true);delay=[int]$exception.Data['VekhaUploadRetryAfter']}
    }
    $exception=$exception.InnerException
  }
  return @{code=$Fallback;retry=$false;delay=0}
}

function Test-VekhaUploadUuid($Value) {
  if($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $false }
  $parsed=[Guid]::Empty
  return [Guid]::TryParseExact($Value,'D',[ref]$parsed)
}

function Test-VekhaUploadInteger($Value,[long]$Minimum,[long]$Maximum) {
  if($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) { return $false }
  return $Value -ge $Minimum -and $Value -le $Maximum -and [Math]::Truncate([double]$Value) -eq $Value
}

function Resolve-VekhaUploadPath([string]$Path) {
  # UNC, mapped network drives, Win32 devices, NT paths, providers and NTFS ADS
  # are deliberately unsupported. Do not contact a network to resolve a path.
  if(!$Path -or $Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2).Contains(':')) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
  try { $full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetPathRoot($full) }
  catch { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
  if($full -notmatch '^[A-Za-z]:\\' -or $full.Substring(2).Contains(':')) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
  try {
    $drive=New-Object IO.DriveInfo($root)
    if($drive.DriveType -notin @([IO.DriveType]::Fixed,[IO.DriveType]::Removable,[IO.DriveType]::CDRom,[IO.DriveType]::Ram)) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
    $current=$root
    $parts=$full.Substring($root.Length).Split([char]'\')
    $paths=@($root)
    foreach($part in $parts) { if(!$part) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' };$current=[IO.Path]::Combine($current,$part);$paths+=,$current }
    for($i=0;$i -lt $paths.Count;$i++) {
      $attributes=[IO.File]::GetAttributes($paths[$i])
      if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
      if($i -lt $paths.Count-1 -and ($attributes -band [IO.FileAttributes]::Directory) -eq 0) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
      if($i -eq $paths.Count-1 -and ($attributes -band [IO.FileAttributes]::Directory) -ne 0) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
    }
  } catch { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
  return $full
}

function Get-VekhaUploadKey {
  # Same per-user DPAPI store as marketplace/Connect-Vekha.ps1. Never accept a
  # key, credential path or network destination from arguments or environment.
  $credentialPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Synapsea\Vekha\connections\codex.key'
  $secure=$null;$pointer=[IntPtr]::Zero
  try {
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    $credentialPath=Resolve-VekhaUploadPath $credentialPath
    if((Get-Item -LiteralPath $credentialPath).Length -gt 32768) { Stop-VekhaUpload 'CREDENTIAL_UNAVAILABLE' }
    $secure=Get-Content -LiteralPath $credentialPath -Raw | ConvertTo-SecureString
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if($key -cnotmatch '^vkh_[A-Za-z0-9_-]{43}$') { Stop-VekhaUpload 'CREDENTIAL_UNAVAILABLE' }
    return $key
  } catch { Stop-VekhaUpload 'CREDENTIAL_UNAVAILABLE' }
  finally { if($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) };if($secure) { $secure.Dispose() } }
}

function New-VekhaUploadClient([string]$Key) {
  Add-Type -AssemblyName System.Net.Http
  $handler=New-Object Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect=$false
  $handler.UseProxy=$false
  $handler.UseDefaultCredentials=$false
  $client=New-Object Net.Http.HttpClient($handler)
  $client.Timeout=[TimeSpan]::FromSeconds(45)
  $client.MaxResponseContentBufferSize=262144
  $client.DefaultRequestHeaders.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$Key)
  $client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
  $client.DefaultRequestHeaders.Accept.ParseAdd('text/event-stream')
  return $client
}

function Open-VekhaUploadFile([string]$Path) {
  if(!('VekhaUploadFileIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class VekhaUploadFileIdentity {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern uint GetFinalPathNameByHandle(SafeFileHandle handle,StringBuilder path,uint size,uint flags);
  public static string PathOf(FileStream stream) {
    var path=new StringBuilder(32768);
    uint length=GetFinalPathNameByHandle(stream.SafeFileHandle,path,(uint)path.Capacity,0);
    if(length==0 || length>=path.Capacity) throw new IOException("File identity unavailable");
    var value=path.ToString();
    return value.StartsWith(@"\\?\",StringComparison.Ordinal)?value.Substring(4):value;
  }
}
'@
  }
  $stream=$null
  try {
    # No write/delete sharing. Keep this exact handle through hashing and chunks.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    if(![string]::Equals([VekhaUploadFileIdentity]::PathOf($stream),$Path,[StringComparison]::OrdinalIgnoreCase)) { Stop-VekhaUpload 'FILE_NOT_ALLOWED' }
    [void](Resolve-VekhaUploadPath $Path)
    return $stream
  } catch { if($stream) { $stream.Dispose() };$failure=Get-VekhaUploadFailure $_ 'FILE_OPEN_FAILED';Stop-VekhaUpload $failure.code }
}

function Get-VekhaUploadDelay($Response) {
  $delay=if([int]$Response.StatusCode -eq 429) { 60 } else { 30 }
  if($Response.Headers.RetryAfter) {
    if($Response.Headers.RetryAfter.Delta) { $delay=[Math]::Ceiling($Response.Headers.RetryAfter.Delta.TotalSeconds) }
    elseif($Response.Headers.RetryAfter.Date) { $delay=[Math]::Ceiling(($Response.Headers.RetryAfter.Date-[DateTimeOffset]::UtcNow).TotalSeconds) }
  }
  if($delay -lt 1) { $delay=1 }
  if($delay -gt 86400) { Stop-VekhaUpload 'INVALID_RESPONSE' }
  return [int]$delay
}

function Read-VekhaUploadToolResult($Result) {
  if(!$Result -or !$Result.content -or @($Result.content).Count -ne 1 -or $Result.content[0].type -cne 'text' -or $Result.content[0].text -isnot [string]) { Stop-VekhaUpload 'INVALID_RESPONSE' }
  try { $data=$Result.content[0].text | ConvertFrom-Json }
  catch { Stop-VekhaUpload 'INVALID_RESPONSE' }
  if(!$data -or $data -is [Array]) { Stop-VekhaUpload 'INVALID_RESPONSE' }
  if($Result.isError -eq $true) {
    $code=[string]$data.error
    if($code -cin @('INVALID_AI_KEY','INVALID_AI_TOKEN')) { $code='AUTH_REQUIRED' }
    $safe=@('AUTH_REQUIRED','ACCESS_DENIED','CAPABILITY_NOT_GRANTED','READ_ONLY_KEY','UNSAFE_DOCUMENT','TEMPORARILY_UNAVAILABLE','DOCUMENT_BUSY','FILE_RATE_LIMITED','DOCUMENT_SCAN_UNAVAILABLE','FILE_DOWNLOAD_TIMEOUT',
      'VALIDATION_ERROR','CONTENT_INTEGRITY_MISMATCH','UPLOAD_EXPIRED','UPLOAD_LIMIT','UPLOAD_CANCELLED','UPLOAD_SEALED','INVALID_OFFSET',
      'IDEMPOTENCY_KEY_REUSED','NOT_FOUND','DOCUMENT_NOT_SCANNED','DOCUMENT_REJECTED','FILE_REJECTED','UNSUPPORTED_FILE_TYPE')
    if($safe -cnotcontains $code) { $code='REMOTE_ERROR' }
    $transient=@('TEMPORARILY_UNAVAILABLE','DOCUMENT_BUSY','FILE_RATE_LIMITED','DOCUMENT_SCAN_UNAVAILABLE','FILE_DOWNLOAD_TIMEOUT')
    $retry=$data.retry -is [bool] -and $data.retry -and $transient -ccontains $code
    $delay=30
    if($null -ne $data.retryAfterSeconds) {
      if(!(Test-VekhaUploadInteger $data.retryAfterSeconds 1 86400)) { Stop-VekhaUpload 'INVALID_RESPONSE' }
      $delay=[int]$data.retryAfterSeconds
    }
    Stop-VekhaUpload $code $retry $delay
  }
  return $data
}

function Invoke-VekhaUploadRpc($Client,[string]$Method,[hashtable]$Params,[bool]$Notification=$false,[int]$Attempts=3) {
  $message=@{jsonrpc='2.0';method=$Method;params=$Params}
  if(!$Notification) { $message.id=[Guid]::NewGuid().ToString() }
  # Serialize once: each automatic retry has exactly the same RPC/body/requestId
  # or chunk offset+bytes. A delay >60s stops instead of retrying prematurely.
  $body=$message | ConvertTo-Json -Compress -Depth 20
  for($attempt=0;$attempt -lt $Attempts;$attempt++) {
    $requestBody=$null;$response=$null
    try {
      $requestBody=[Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'application/json')
      try { $response=$Client.PostAsync('https://vekha.synapsea.agency/api/v1/ai/mcp',$requestBody).GetAwaiter().GetResult() }
      catch { Stop-VekhaUpload 'REMOTE_UNAVAILABLE' $true 2 }
      $status=[int]$response.StatusCode
      if($status -eq 401) { Stop-VekhaUpload 'AUTH_REQUIRED' }
      if($status -eq 403) { Stop-VekhaUpload 'ACCESS_DENIED' }
      if($status -ge 300 -and $status -lt 400) { Stop-VekhaUpload 'REDIRECT_DENIED' }
      if($status -in @(408,425,429,500,502,503,504)) { Stop-VekhaUpload 'REMOTE_UNAVAILABLE' $true (Get-VekhaUploadDelay $response) }
      if(!$response.IsSuccessStatusCode) { Stop-VekhaUpload 'REMOTE_ERROR' }
      if($Notification) { if($status -notin @(202,204)) { Stop-VekhaUpload 'INVALID_RESPONSE' };return }
      if($response.Content.Headers.ContentLength -gt 262144 -or $response.Content.Headers.ContentType.MediaType -cne 'application/json') { Stop-VekhaUpload 'INVALID_RESPONSE' }
      $text=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      if([Text.Encoding]::UTF8.GetByteCount($text) -gt 262144) { Stop-VekhaUpload 'INVALID_RESPONSE' }
      try { $parsed=$text | ConvertFrom-Json } catch { Stop-VekhaUpload 'INVALID_RESPONSE' }
      if(!$parsed -or $parsed -is [Array] -or $parsed.jsonrpc -cne '2.0' -or $parsed.id -cne $message.id) { Stop-VekhaUpload 'INVALID_RESPONSE' }
      if($parsed.error) { Stop-VekhaUpload 'RPC_ERROR' }
      if($Method -eq 'tools/call') { return (Read-VekhaUploadToolResult $parsed.result) }
      return $parsed.result
    } catch {
      $failure=Get-VekhaUploadFailure $_
      if(!$failure.retry -or $failure.delay -gt 60 -or $attempt -eq $Attempts-1) { Stop-VekhaUpload $failure.code $failure.retry $failure.delay }
      Start-Sleep -Seconds $failure.delay
    } finally { if($response) { $response.Dispose() };if($requestBody) { $requestBody.Dispose() } }
  }
}

function Invoke-VekhaLocalUpload([string]$FilePath,[string]$TripId,[string]$RequestId) {
  $stream=$null;$client=$null;$key=$null;$buffer=$null;$uploadId=$null;$beginAttempted=$false
  try {
    if(!(Test-VekhaUploadUuid $TripId) -or ($RequestId -and !(Test-VekhaUploadUuid $RequestId))) { Stop-VekhaUpload 'INVALID_ARGUMENTS' }
    if(!$RequestId) { $RequestId=[Guid]::NewGuid().ToString() }
    $path=Resolve-VekhaUploadPath $FilePath
    $name=[IO.Path]::GetFileName($path)
    if(!$name -or $name.Length -gt 180 -or $name -cne $name.Trim() -or $name.EndsWith('.') -or $name -match '[\\/:*?"<>|\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]' -or $name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { Stop-VekhaUpload 'FILE_NAME_INVALID' }
    $mime=switch([IO.Path]::GetExtension($name).ToLowerInvariant()) { '.pdf' {'application/pdf'} '.png' {'image/png'} '.jpg' {'image/jpeg'} '.jpeg' {'image/jpeg'} default { Stop-VekhaUpload 'FILE_TYPE_INVALID' } }
    $stream=Open-VekhaUploadFile $path
    $length=$stream.Length
    if($length -lt 1 -or $length -gt 10485760) { Stop-VekhaUpload 'FILE_TOO_LARGE' }
    $head=New-Object byte[] 8;$headCount=$stream.Read($head,0,8);$stream.Position=0
    $magic=($mime -eq 'application/pdf' -and $headCount -ge 5 -and [Text.Encoding]::ASCII.GetString($head,0,5) -ceq '%PDF-') -or
      ($mime -eq 'image/png' -and $headCount -eq 8 -and [BitConverter]::ToString($head) -ceq '89-50-4E-47-0D-0A-1A-0A') -or
      ($mime -eq 'image/jpeg' -and $headCount -ge 3 -and $head[0] -eq 255 -and $head[1] -eq 216 -and $head[2] -eq 255)
    if(!$magic) { Stop-VekhaUpload 'FILE_TYPE_INVALID' }
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $digest=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $stream.Position=0
    $key=Get-VekhaUploadKey
    $client=New-VekhaUploadClient $key;$key=$null
    $hello=Invoke-VekhaUploadRpc $client 'initialize' @{protocolVersion='2025-06-18';capabilities=@{};clientInfo=@{name='vekha-local-document-upload';version='0.6.0'}}
    if($hello.serverInfo.name -cne 'vekha' -or $hello.protocolVersion -isnot [string] -or $hello.protocolVersion -cnotmatch '^20\d{2}-\d{2}-\d{2}$') { Stop-VekhaUpload 'INVALID_RESPONSE' }
    $client.DefaultRequestHeaders.Add('MCP-Protocol-Version',[string]$hello.protocolVersion)
    Invoke-VekhaUploadRpc $client 'notifications/initialized' @{} $true
    $beginAttempted=$true
    $begin=Invoke-VekhaUploadRpc $client 'tools/call' @{name='begin_document_upload';arguments=@{requestId=$RequestId;tripId=$TripId;fileName=$name;mimeType=$mime;byteLength=$length;sha256=$digest}}
    if(!(Test-VekhaUploadUuid $begin.uploadId)) { Stop-VekhaUpload 'INVALID_RESPONSE' }
    $uploadId=[string]$begin.uploadId
    if($begin.status -ceq 'consumed') { Stop-VekhaUpload 'UPLOAD_ALREADY_IMPORTED' }
    if($begin.status -cnotin @('uploading','clean')) { Stop-VekhaUpload 'INVALID_RESPONSE' }
    if($begin.status -ceq 'uploading' -and !(Test-VekhaUploadInteger $begin.offset 0 $length)) { Stop-VekhaUpload 'INVALID_RESPONSE' }
    if($begin.status -ceq 'clean' -and !(Test-VekhaUploadInteger $begin.offset 1 10485760)) { Stop-VekhaUpload 'INVALID_RESPONSE' }
    $chunkBytes=65536
    if($null -ne $begin.chunkBytes -and !(Test-VekhaUploadInteger $begin.chunkBytes 65536 65536)) { Stop-VekhaUpload 'INVALID_RESPONSE' }
    # A clean upload can contain a normalized image larger than the original.
    # Its offset is checked-output metadata, never a source-file seek position.
    $offset=if($begin.status -ceq 'uploading') { [long]$begin.offset } else { 0 }
    $stream.Position=$offset;$buffer=New-Object byte[] $chunkBytes
    while($begin.status -ceq 'uploading' -and $offset -lt $length) {
      $needed=[int][Math]::Min($chunkBytes,$length-$offset);$count=0
      while($count -lt $needed) { $read=$stream.Read($buffer,$count,$needed-$count);if($read -le 0) { Stop-VekhaUpload 'FILE_CHANGED' };$count+=$read }
      $data=[Convert]::ToBase64String($buffer,0,$count)
      $chunk=Invoke-VekhaUploadRpc $client 'tools/call' @{name='upload_document_chunk';arguments=@{tripId=$TripId;uploadId=$uploadId;offset=$offset;data=$data}}
      $data=$null
      if(!(Test-VekhaUploadInteger $chunk.offset ($offset+$count) ($offset+$count))) { Stop-VekhaUpload 'INVALID_RESPONSE' }
      $offset+=$count
    }
    $checked=Invoke-VekhaUploadRpc $client 'tools/call' @{name='check_document_upload';arguments=@{tripId=$TripId;uploadId=$uploadId}}
    if($checked.uploadId -cne $uploadId -or $checked.status -cne 'clean' -or $checked.mimeType -cne $mime -or !(Test-VekhaUploadInteger $checked.byteLength 1 10485760) -or $checked.sha256 -isnot [string] -or $checked.sha256 -cnotmatch '^[a-f0-9]{64}$') { Stop-VekhaUpload 'INVALID_RESPONSE' }
    return @{ok=$true;requestId=$RequestId;uploadId=$uploadId;status='clean';safety='server_checked';imported=$false;
      input=@{mimeType=$mime;byteLength=$length;sha256=$digest};checked=@{mimeType=[string]$checked.mimeType;byteLength=[long]$checked.byteLength;sha256=[string]$checked.sha256}}
  } catch {
    $failure=Get-VekhaUploadFailure $_
    $result=@{ok=$false;error=$failure.code}
    if(Test-VekhaUploadUuid $RequestId) { $result.requestId=$RequestId }
    if($failure.delay -gt 0) { $result.retryAfterSeconds=$failure.delay }
    if($uploadId -and $client) {
      $result.uploadId=$uploadId
      if($failure.retry) { $result.resumable=$true }
      else {
        $result.cancelled=$false
        try { $cancel=Invoke-VekhaUploadRpc $client 'tools/call' @{name='cancel_document_upload';arguments=@{tripId=$TripId;uploadId=$uploadId}} $false 1;$result.cancelled=$cancel.cancelled -is [bool] -and $cancel.cancelled }
        catch { }
      }
    } elseif($beginAttempted) { $result.uploadMayExist=$true }
    return $result
  } finally {
    $key=$null;$data=$null
    if($buffer) { [Array]::Clear($buffer,0,$buffer.Length) }
    if($stream) { $stream.Dispose() };if($client) { $client.Dispose() }
  }
}

# The only stdout record is bounded metadata. Never print provider bodies,
# exception details, paths, file contents, base64, headers or the DPAPI key.
try {
  [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
  if($args.Count) { Stop-VekhaUpload 'INVALID_ARGUMENTS' }
  $result=Invoke-VekhaLocalUpload $FilePath $TripId $RequestId
  $json=$result | ConvertTo-Json -Compress -Depth 5
  if($json.Length -gt 2048) { Stop-VekhaUpload 'INVALID_RESPONSE' }
  [Console]::Out.WriteLine($json)
  if(!$result.ok) { exit 1 }
} catch { $failure=Get-VekhaUploadFailure $_;[Console]::Out.WriteLine((@{ok=$false;error=$failure.code} | ConvertTo-Json -Compress));exit 1 }
