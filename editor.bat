@echo off
cd /d "%~dp0"
set "GODOT=%GODOT_BIN%"
if not defined GODOT set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
start "" "%GODOT%" -e --path "%CD%"
