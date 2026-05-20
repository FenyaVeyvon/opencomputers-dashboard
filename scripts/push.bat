@echo off
set MSG=%~1
if "%MSG%"=="" set MSG=update eonlink

if not exist .git (
  git init
)
git branch -M main
git remote get-url origin >nul 2>nul
if errorlevel 1 (
  git remote add origin https://github.com/FenyaVeyvon/opencomputers-dashboard.git
)

git status
git add .
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "%MSG%"
) else (
  echo Nothing to commit.
)
git push -u origin main
pause
