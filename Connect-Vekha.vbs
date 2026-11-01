Option Explicit
Dim files, shell, folder, powershell, scriptPath, command, result
Set files = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
folder = files.GetParentFolderName(WScript.ScriptFullName)
powershell = files.BuildPath(shell.ExpandEnvironmentStrings("%SystemRoot%"), "System32\WindowsPowerShell\v1.0\powershell.exe")
scriptPath = files.BuildPath(folder, "Connect-Vekha.ps1")
If Not files.FileExists(scriptPath) Then
  MsgBox "Extract the complete Vekha ZIP, then open Connect-Vekha.vbs again.", 16, "Vekha"
  WScript.Quit 1
End If
command = Quote(powershell) & " -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Quote(scriptPath)
On Error Resume Next
' Keep this invisible launcher alive until the independent key form closes.
' No API key is read by this launcher or included in process arguments.
result = shell.Run(command, 0, True)
If Err.Number <> 0 Then
  MsgBox "Could not open the Vekha connection window. Please try again.", 16, "Vekha"
  WScript.Quit 1
End If
On Error GoTo 0
If result <> 0 And result <> 2 Then
  MsgBox "Could not finish connecting Vekha. Please try Connect-Vekha.vbs again.", 16, "Vekha"
End If
WScript.Quit result

Function Quote(value)
  Quote = Chr(34) & value & Chr(34)
End Function
