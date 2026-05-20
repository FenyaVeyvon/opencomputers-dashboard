@echo off
if not exist .git (
  git init
)
git branch -M main
git remote get-url origin >nul 2>nul
if errorlevel 1 (
  git remote add origin https://github.com/FenyaVeyvon/opencomputers-dashboard.git
)
git status
pause
