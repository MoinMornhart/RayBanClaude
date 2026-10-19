@echo off
rem RayBan Claude starten (Doppelklick genuegt)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
