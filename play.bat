@echo off
rem Kana Run 2.0 - double-click to play (ASCII only on purpose)
cd /d "%~dp0"
set "GODOT=%GODOT_BIN%"
if not defined GODOT set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" ( echo [ERROR] Godot not found. Set GODOT_BIN. & pause & exit /b 1 )
"%GODOT%" --headless --path "%CD%" --import >nul 2>&1
"%GODOT%" --path "%CD%" %*
