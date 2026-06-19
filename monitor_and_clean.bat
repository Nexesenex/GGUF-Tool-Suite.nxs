@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** monitor_and_clean.bat - Windows port of monitor_and_clean.sh** 
REM ** Auto-creates tensors.map files and optionally deletes       **
REM ** unused shards.                                              **
REM **                                                              **
REM ** Usage: monitor_and_clean.bat [directory]                     **
REM ******************************************************************

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "CREATE_MAP=%SCRIPT_DIR%\create_map_file.bat"
set "DELETE_UNMATCHED=false"

if exist "%CREATE_MAP%" (
  echo [%DATE% %TIME%] Found create_map_file.bat
) else (
  echo Error: create_map_file.bat not found.
  exit /b 1
)

set "BASE_DIR=%~1"
if "%BASE_DIR%"=="" set "BASE_DIR=."

if not exist "%BASE_DIR%" (
  echo Error: '%BASE_DIR%' is not a valid directory.
  exit /b 1
)

echo [%DATE% %TIME%] Monitoring for GGUF shards in: %BASE_DIR%
echo Polling every 60 seconds...
echo DELETE_UNMATCHED_SHARDS is set to: %DELETE_UNMATCHED%
echo.

:poll_loop
echo [%DATE% %TIME%] Scanning for GGUF files...

REM Find all GGUF files in subdirectories
for /r "%BASE_DIR%" %%f in (*.gguf) do (
  set "GGFILE=%%f"
  set "GGDIR=%%~dpf"
  set "GGDIR=!GGDIR:~0,-1!"
  
  REM Check if tensors.map exists; if so, check if it has this file's entries
  if exist "!GGDIR!\tensors.map" (
    findstr /m "%%~nxf" "!GGDIR!\tensors.map" >nul 2>&1
    if errorlevel 1 (
      echo [%DATE% %TIME%] New shard found: %%f
      call "%CREATE_MAP%" "%%f"
    )
  ) else (
    echo [%DATE% %TIME%] New shard found (no tensors.map): %%f
    call "%CREATE_MAP%" "%%f"
  )
)

echo [%DATE% %TIME%] Scan complete. Waiting 60 seconds...
timeout /t 60 /nobreak >nul
goto :poll_loop
