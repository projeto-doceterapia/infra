' Starts the launcher window with no console: the desktop shortcut and a
' double click on doceterapia.cmd come through here.
Option Explicit
Dim sistemaArquivos, pasta, comando
Set sistemaArquivos = CreateObject("Scripting.FileSystemObject")
pasta = sistemaArquivos.GetParentFolderName(WScript.ScriptFullName)
comando = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & pasta & "\scripts\doceterapia.ps1"""
CreateObject("WScript.Shell").Run comando, 0, False
