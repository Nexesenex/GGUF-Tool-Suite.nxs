@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** monitor_and_split.bat - Monitors a directory for new .gguf  **
REM ** files and organizes them into split directories.            **
REM ** Windows port of monitor_and_split.sh.                       **
REM **                                                              **
REM ** Usage: monitor_and_split.bat [directory]                     **
REM ******************************************************************

set "BASE_DIR=%~1"
if "%BASE_DIR%"=="" set "BASE_DIR=."

if not exist "%BASE_DIR%" (
  echo Error: '%BASE_DIR%' is not a valid directory.
  exit /b 1
)

echo [%DATE% %TIME%] Monitoring for GGUF shards in: %BASE_DIR%
echo Polling every 60 seconds...
echo.

REM Regex pattern for shard filenames: -MMMMM-of-NNNNN.gguf
set "_pattern=*-of-*.gguf"

:poll_loop
echo [%DATE% %TIME%] Scanning for new GGUF files...

for %%f in ("%BASE_DIR%\%_pattern%") do (
  if exist "%%f" (
    set "FNAME=%%~nf%%~xf"
    
    REM Extract model prefix (everything before -00001-of- or similar)
    set "MODEL_PREFIX=!FNAME:-SPECIAL_TENSOR-=-SPLIT!"
    for /f "tokens=1 delims=-" %%a in ("!MODEL_PREFIX!") do set "MODEL=%%a"
    
    if defined MODEL (
      set "SPLIT_DIR=%BASE_DIR%\!MODEL!_split"
      if not exist "!SPLIT_DIR!" mkdir "!SPLIT_DIR!"
      
      if not exist "!SPLIT_DIR!\!FNAME!" (
        echo [%DATE% %TIME%] Moving %%f to !SPLIT_DIR!
        move "%%f" "!SPLIT_DIR!" >nul 2>&1
      )
    )
  )
)

echo [%DATE% %TIME%] Scan complete. Waiting 60 seconds...
timeout /t 60 /nobreak >nul
goto :poll_loop
