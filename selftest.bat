@echo off
cd /d "%~dp0"
set "GODOT=%GODOT_BIN%"
if not defined GODOT set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
"%GODOT%" --headless --path "%CD%" --import
if errorlevel 1 exit /b %ERRORLEVEL%
"%GODOT%" --headless --path "%CD%" --fixed-fps 60 -s res://tools/smoke_test.gd
if errorlevel 1 exit /b %ERRORLEVEL%
"%GODOT%" --headless --path "%CD%" -s res://tools/report_regression.gd
exit /b %ERRORLEVEL%
