Option Explicit
Dim files, shell, folder, powershell, scriptPath, command, result
Set files = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
folder = files.GetParentFolderName(WScript.ScriptFullName)
powershell = files.BuildPath(shell.ExpandEnvironmentStrings("%SystemRoot%"), "System32\WindowsPowerShell\v1.0\powershell.exe")
scriptPath = files.BuildPath(folder, "Install-Codex.ps1")
If Not files.FileExists(scriptPath) Then
  MsgBox "Extract the complete Vekha ZIP, then open Install-Vekha.vbs again.", 16, "Vekha"
  WScript.Quit 1
End If
command = Quote(powershell) & " -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Quote(scriptPath)
On Error Resume Next
' Hidden PowerShell performs setup and opens only the Vekha connection form.
' Waiting keeps the GUI alive and propagates cancellation without an error box.
result = shell.Run(command, 0, True)
If Err.Number <> 0 Then
  MsgBox "Could not start Vekha setup. Open Codex, then try again.", 16, "Vekha"
  WScript.Quit 1
End If
On Error GoTo 0
If result <> 0 And result <> 2 Then
  MsgBox "Vekha setup could not finish. Open Codex, then try Install-Vekha.vbs again.", 16, "Vekha"
End If
WScript.Quit result

Function Quote(value)
  Quote = Chr(34) & value & Chr(34)
End Function
