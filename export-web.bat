@echo off
cd /d "%~dp0"
set "GODOT=%GODOT_BIN%"
if not defined GODOT set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist build\web mkdir build\web
"%GODOT%" --headless --path "%CD%" --import
if errorlevel 1 exit /b %ERRORLEVEL%
"%GODOT%" --headless --path "%CD%" --export-release "Web" build/web/index.html
if errorlevel 1 exit /b %ERRORLEVEL%
python tools\cachebust.py
if errorlevel 1 exit /b %ERRORLEVEL%
for %%F in (build\web\kr2_*.pck) do echo pck size: %%~zF bytes
exit /b %ERRORLEVEL%
