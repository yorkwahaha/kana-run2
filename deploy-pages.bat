@echo off
cd /d "%~dp0"

echo [1/3] Building Web Export...
call export-web.bat
if errorlevel 1 (
    echo Export failed!
    exit /b %ERRORLEVEL%
)

echo [2/3] Preparing gh-pages branch...
cd build\web
if not exist .git (
    git init
    git remote add origin https://github.com/yorkwahaha/kana-run2.git
)
git checkout -B gh-pages
git add -A
git commit -m "Deploy Kana Run 2.0 Web to GitHub Pages"

echo [3/3] Pushing to GitHub Pages...
git push -f origin gh-pages
cd /d "%~dp0"

echo.
echo ========================================================
echo Deployment pushed to https://yorkwahaha.github.io/kana-run2/
echo ========================================================
