' dsh-tray-launcher - starts dsh-tray.ps1 without any console window.
'   --at-logon : called by the HKCU Run entry (tray only unless startOnLaunch is on)
'   --open     : called by the desktop shortcut (open Harness and pop the browser)
'   (no args)  : a manual double-click starts the tray normally
Option Explicit
Dim fso, sh, here, cmd, extra, i, a
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
extra = ""
For i = 0 To WScript.Arguments.Count - 1
  a = LCase(WScript.Arguments(i))
  If a = "--at-logon" Then extra = extra & " -AtLogon"
  If a = "--open" Then extra = extra & " -Open"
Next
cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\dsh-tray.ps1""" & extra
sh.Run cmd, 0, False
