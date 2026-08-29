@echo off
setlocal enabledelayedexpansion

rem ============================================================
rem  V+ — Auto Commit & Push
rem  Remote: https://github.com/nox1020/invest
rem  Usage:
rem    invest_push.bat
rem    invest_push.bat your commit message
rem ============================================================

set "REPO_DIR=%~dp0"
set "REMOTE=https://github.com/nox1020/invest.git"
set "CUSTOM_MSG=%*"

cd /d "%REPO_DIR%" || (
  echo [V+] مسیر پیدا نشد: %REPO_DIR%
  pause
  exit /b 1
)

git rev-parse --is-inside-work-tree >nul 2>&1 || (
  echo [V+] این مسیر یک مخزن Git نیست.
  pause
  exit /b 1
)

if exist ".git\rebase-merge" (
  echo [V+] Rebase نیمه‌تمام — abort...
  git rebase --abort
)

set "BRANCH=main"
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "BRANCH=%%b"
echo.
echo ============================================================
echo   V+ — Auto Commit ^& Push
echo   Remote: nox1020/invest
echo   Branch: %BRANCH%
echo ============================================================
echo.

git remote get-url origin >nul 2>&1
if errorlevel 1 (
  git remote add origin "%REMOTE%"
) else (
  git remote set-url origin "%REMOTE%"
)

set "EXCLUDE=nox1020 .venv __pycache__ .pytest_cache data\*.db data\logs .env .env.* *.lnk *.xlsx *.pdf"
git restore --staged %EXCLUDE% >nul 2>&1

echo [V+] pull --rebase --autostash...
git pull --rebase --autostash origin %BRANCH%
if errorlevel 1 (
  echo [V+] pull ناموفق بود. دسترسی GitHub یا conflict را بررسی کنید.
  pause
  exit /b 1
)

git add -A
git reset %EXCLUDE% >nul 2>&1

git diff --cached --quiet && (
  echo [V+] هیچ تغییری برای push نیست.
  pause
  exit /b 0
)

if defined CUSTOM_MSG (
  set "msg=!CUSTOM_MSG!"
) else (
  set "msg=Auto commit V+ !date! !time!"
)

echo [V+] تغییرات:
echo --------------------------
git status --short
echo --------------------------

git commit -m "!msg!"
if errorlevel 1 (
  echo [V+] commit ناموفق بود.
  pause
  exit /b 1
)

echo [V+] push...
git push -u origin %BRANCH%
if errorlevel 1 (
  echo [V+] push ناموفق بود. GitHub login / PAT را بررسی کنید.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   V+ — push موفق
echo   Branch: %BRANCH%
echo   Commit: !msg!
echo ============================================================
echo.
pause
exit /b 0
