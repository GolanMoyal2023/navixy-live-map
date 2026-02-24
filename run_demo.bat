@echo off
title Navixy Live Map - Demo Runner
cd /d "%~dp0"

echo ============================================
echo   Navixy Live Map - Starting Demo
echo ============================================
echo.

:: Kill any existing python on our ports
echo [1/5] Cleaning up old processes...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8767 " ^| findstr "LISTENING"') do taskkill /F /PID %%a >nul 2>&1
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8768 " ^| findstr "LISTENING"') do taskkill /F /PID %%a >nul 2>&1
timeout /t 1 /nobreak >nul

:: Start server.py (Navixy API) on :8767
echo [2/5] Starting Navixy API server on :8767...
set PORT=8767
start "NavixyAPI-8767" /MIN .venv\Scripts\python.exe server.py

:: Start teltonika_broker.py on :8768
echo [3/5] Starting Teltonika Broker on :8768...
start "Broker-8768" /MIN .venv\Scripts\python.exe teltonika_broker.py

:: Wait for servers to boot
echo [4/5] Waiting for servers to start...
timeout /t 4 /nobreak >nul

:: Check endpoints
echo [5/5] Checking endpoints...
echo.

curl -s -o nul -w "  :8767 Navixy API  -> HTTP %%{http_code}" http://localhost:8767/data
echo.
curl -s -o nul -w "  :8768 Broker       -> HTTP %%{http_code}" http://localhost:8768/data
echo.
echo.

:: Open HTML pages
echo Opening map and troubleshoot pages...
start "" "%~dp0index.html"
start "" "%~dp0troubleshoot.html"

echo.
echo ============================================
echo   Demo is running! Close this window to
echo   keep servers alive in background.
echo ============================================
echo.
pause
