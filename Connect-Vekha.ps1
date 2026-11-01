param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
# Codex can inherit PSModulePath from PowerShell 7. Load Windows' own DPAPI
# cmdlets explicitly instead of accidentally importing another runtime's module.
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$credentialDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Synapsea\Vekha\connections'
$credentialPath = Join-Path $credentialDirectory 'codex.key'

function Test-VekhaConnection([string]$Key) {
  if ($Key -cnotmatch '^vkh_[A-Za-z0-9_-]{43}$') { throw 'Скопируйте полный ключ из Vekha. Он начинается с vkh_ и не содержит пробелов.' }
  $handler = New-Object Net.Http.HttpClientHandler
  $handler.AllowAutoRedirect = $false
  $client = New-Object Net.Http.HttpClient($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(20)
  $client.MaxResponseContentBufferSize = 1048576
  try {
    $client.DefaultRequestHeaders.Authorization = New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Key)
    $client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
    $client.DefaultRequestHeaders.Accept.ParseAdd('text/event-stream')
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"vekha-connect","version":"0.7.0"}}}'
    $requestBody = [Net.Http.StringContent]::new($body,[Text.Encoding]::UTF8,'application/json')
    try { $response = $client.PostAsync('https://vekha.synapsea.agency/api/v1/ai/mcp', $requestBody).GetAwaiter().GetResult() }
    finally { $requestBody.Dispose() }
    try {
      if ([int]$response.StatusCode -eq 401) { throw 'Ключ отозван или истёк. Создайте новый в Vekha → Настройки → AI-помощники.' }
      if (!$response.IsSuccessStatusCode) { throw 'Сервер сейчас недоступен. Проверьте интернет и повторите подключение.' }
      $data = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
      if ($data.jsonrpc -ne '2.0' -or $data.id -ne 1 -or $data.result.serverInfo.name -ne 'vekha' -or $data.error -or $data.result.protocolVersion -notmatch '^20\d{2}-\d{2}-\d{2}$') { throw 'Не удалось подтвердить подключение к Vekha.' }
    } finally { $response.Dispose() }
  } finally { $client.Dispose(); $handler.Dispose() }
}

if ($CheckOnly) {
  if (!(Test-Path -LiteralPath $credentialPath)) { throw 'Vekha key is not connected.' }
  $secure = Get-Content -LiteralPath $credentialPath -Raw | ConvertTo-SecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { Test-VekhaConnection ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)); Write-Output 'Vekha connection is valid.' }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Подключить Vekha к Codex'
$form.ClientSize = New-Object Drawing.Size(560,300)
$form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.MinimizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI',11)
$intro = New-Object Windows.Forms.Label
$intro.Location = New-Object Drawing.Point(24,20); $intro.Size = New-Object Drawing.Size(510,65)
$intro.Text = 'Откройте Vekha → Настройки → AI-помощники. Скопируйте ключ выбранных поездок и вставьте его сюда.'
$inputBox = New-Object Windows.Forms.TextBox
$inputBox.Location = New-Object Drawing.Point(24,96); $inputBox.Size = New-Object Drawing.Size(510,32); $inputBox.UseSystemPasswordChar = $true; $inputBox.MaxLength = 100
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(24,143); $status.Size = New-Object Drawing.Size(510,77)
$status.Text = 'Ключ хранится зашифрованным в вашей учётной записи Windows. В чат и файлы проекта он не попадёт.'
$connect = New-Object Windows.Forms.Button
$connect.Location = New-Object Drawing.Point(334,238); $connect.Size = New-Object Drawing.Size(200,40); $connect.Text = 'Подключить'
$form.AcceptButton = $connect
$script:connected = $false
$connect.Add_Click({
  if ($script:connected) { $form.Close(); return }
  $connect.Enabled = $false; $status.Text = 'Проверяем ключ…'; $form.Refresh()
  try {
    $keyText = $inputBox.Text.Trim()
    Test-VekhaConnection $keyText
    $secure = ConvertTo-SecureString $keyText -AsPlainText -Force
    $temporary = $null
    try {
      New-Item -ItemType Directory -Path $credentialDirectory -Force | Out-Null
      $encrypted = ConvertFrom-SecureString $secure
      $temporary = Join-Path $credentialDirectory ([Guid]::NewGuid().ToString()+'.tmp')
      [IO.File]::WriteAllText($temporary,$encrypted,[Text.UTF8Encoding]::new($false))
      if ([IO.File]::Exists($credentialPath)) { [IO.File]::Replace($temporary,$credentialPath,$null) }
      else { [IO.File]::Move($temporary,$credentialPath) }
      $temporary = $null
    } finally {
      if ($temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
      $secure.Dispose(); $keyText = $null; $inputBox.Clear()
    }
    $script:connected = $true
    $status.Text = 'Подключено. Откройте новый чат Codex и попросите: «Покажи мои поездки Vekha». Если инструменты не появились, перезапустите Codex один раз.'
    $connect.Text = 'Готово'; $connect.Enabled = $true
  } catch {
    $known = @('Скопируйте полный ключ из Vekha. Он начинается с vkh_ и не содержит пробелов.','Ключ отозван или истёк. Создайте новый в Vekha → Настройки → AI-помощники.','Сервер сейчас недоступен. Проверьте интернет и повторите подключение.','Не удалось подтвердить подключение к Vekha.')
    $status.Text = if ($known -contains $_.Exception.Message) { $_.Exception.Message } else { 'Не удалось подключиться. Проверьте интернет и повторите. Ключ не сохранён.' }
    $connect.Enabled = $true
  } finally {
    $keyText = $null
  }
})
$form.Controls.AddRange(@($intro,$inputBox,$status,$connect))
[void]$form.ShowDialog()
$form.Dispose()
if (!$script:connected) { exit 2 }
