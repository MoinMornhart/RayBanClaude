@echo off
rem RayBan Claude einrichten (Doppelklick genuegt)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
