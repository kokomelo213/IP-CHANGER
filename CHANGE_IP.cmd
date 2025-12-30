@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
title IP MANAGER ELITE - made by ketazz
color 0B

:: ROOT without trailing backslash (VERY IMPORTANT)
for %%I in ("%~dp0.") do set "ROOT=%%~fI"
set "SELF=%~f0"

:: If not already in HOST mode, open a persistent console and quit the /c window.
if /I not "%~1"=="/HOST" (
  start "" "%ComSpec%" /k ""%SELF%" /HOST"
  exit /b
)

cls
call :LOGO
call :BEEP_BOOT
call :CLEAN_JUNK

:MENU
cls
call :LOGO
call :GET_STATUS
call :TOPBAR

echo [1]  VPN ON  (RANDOM / ROTATE)        (ADMIN required)
echo [2]  VPN OFF (DISCONNECT ALL)         (ADMIN required)
echo [3]  PICK CONFIG (.conf)              (ADMIN required)
echo [4]  STATUS
echo [5]  ISP / CITY INFO
echo [6]  LOCAL NETWORK RENEW              (ADMIN required)
echo [7]  EMERGENCY REPAIR                 (ADMIN required)
echo [8]  CONFIG EXPIRY (days left)
echo [9]  BEST VPN AUTO (LIVE TEST -> best)(ADMIN required)
echo [10] BEST VPN LIST (LIVE TEST -> pick)(ADMIN required)
echo [11] BENCH PING (LIVE TEST TABLE)     (ADMIN required)
echo [A]  RUN AS ADMIN (recommended)
echo [0]  EXIT (disconnect if admin)
echo.

set "sel="
set /p sel=Choose: 

if /I "%sel%"=="A" goto :ADMIN
if "%sel%"=="4"  call :DO status
if "%sel%"=="5"  call :DO info
if "%sel%"=="8"  call :DO checkconfigs

if "%sel%"=="1"  call :DO random
if "%sel%"=="2"  call :DO disconnect
if "%sel%"=="3"  call :DO pick
if "%sel%"=="6"  call :DO localrenew
if "%sel%"=="7"  call :DO repair
if "%sel%"=="9"  call :DO bestauto
if "%sel%"=="10" call :DO bestpick
if "%sel%"=="11" call :DO benchping

if "%sel%"=="0"  goto :EXIT_OK

echo Invalid option.
timeout /t 1 >nul
goto MENU

:ADMIN
echo.
echo [*] Opening ADMIN window...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -Verb RunAs -FilePath $env:ComSpec -ArgumentList @('/k','cd /d ""%ROOT%"" ^& ""%SELF%"" /HOST')"
echo.
echo If you cancelled UAC, nothing will open.
pause
goto MENU

:DO
cls
call :LOGO
echo made by ketazz — running: %1
call :LOADING 14
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\IP_MANAGER.ps1" -Action %1 -Root "%ROOT%"
set "psErr=%errorlevel%"

echo.
call :GET_STATUS
call :RESULT

if not "%psErr%"=="0" (
  echo.
  echo [ERROR] PowerShell errorlevel=%psErr%
)

echo.
pause
goto MENU

:EXIT_OK
echo.
echo [*] If you are Admin: safety disconnect...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\IP_MANAGER.ps1" -Action cleanup -Root "%ROOT%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\IP_MANAGER.ps1" -Action cleanupjunk -Root "%ROOT%" >nul 2>&1
call :CLEAN_JUNK
echo Bye.
exit

:: ================= UI =================
:LOGO
echo ================================================================================
echo   ██╗██████╗     ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
echo   ██║██╔══██╗    ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
echo   ██║██████╔╝    ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
echo   ██║██╔═══╝     ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
echo   ██║██║         ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
echo   ╚═╝╚═╝         ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
echo                         ELITE CMD TOOL  —  MADE BY KETAZZ
echo ================================================================================
echo.
goto :eof

:TOPBAR
set "cfgCount=0"
for /f %%n in ('dir /b /a-d "%ROOT%\wg-configs\*.conf" 2^>nul ^| find /c /v ""') do set "cfgCount=%%n"
echo ----------------------------------------------------------------
if not defined TUNNEL (
  set "TS=(none)"
) else (
  set "TS=%TUNNEL%"
)
echo IP: %IP%   TUNNEL: "%TS%"   CONFIGS: %cfgCount%
echo ----------------------------------------------------------------
echo.
goto :eof

:LOADING
setlocal EnableExtensions EnableDelayedExpansion
set /a loops=%1
<nul set /p "=loading: ["
for /l %%i in (1,1,!loops!) do (
  <nul set /p "=#"
  ping -n 1 -w 70 127.0.0.1 >nul
)
echo ]
endlocal
goto :eof

:GET_STATUS
set "IP=Offline"
set "TUNNEL="
for /f "usebackq tokens=1,* delims=:" %%A in (`
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\IP_MANAGER.ps1" -Action rawstatus -Root "%ROOT%" 2^>nul
`) do (
  if /i "%%A"=="IP" set "IP=%%B"
  if /i "%%A"=="TUNNEL" set "TUNNEL=%%B"
)
goto :eof

:RESULT
echo.
if not defined TUNNEL (
  echo =============================  ❌ DISCONNECTED ❌  ============================
  powershell -NoProfile -Command "[console]::Beep(220,180); Start-Sleep -Milliseconds 60; [console]::Beep(180,220)" >nul 2>&1
) else (
  echo ==============================  ✅ CONNECTED ✅  ==============================
  powershell -NoProfile -Command "[console]::Beep(880,120); Start-Sleep -Milliseconds 60; [console]::Beep(1100,150)" >nul 2>&1
)
goto :eof

:BEEP_BOOT
powershell -NoProfile -Command "[console]::Beep(600,90); Start-Sleep -Milliseconds 40; [console]::Beep(760,90)" >nul 2>&1
goto :eof

:CLEAN_JUNK
:: SAFE: only deletes known junk from old versions (never touches cmd/ps1/readme/wg-configs)
del /q "%ROOT%\ipmanager_*.log" >nul 2>&1
del /q "%ROOT%\ipmanager_*.txt" >nul 2>&1
if exist "%ROOT%\.ipmanager_state.json" del /q "%ROOT%\.ipmanager_state.json" >nul 2>&1
if exist "%ROOT%\connect" del /q "%ROOT%\connect" >nul 2>&1
if exist "%ROOT%\opening" del /q "%ROOT%\opening" >nul 2>&1
if exist "%ROOT%\choose" del /q "%ROOT%\choose" >nul 2>&1
goto :eof
