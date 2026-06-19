@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** create_map_file.bat - Windows port of create_map_file.sh     **
REM ** Creates tensors.map files for your GGUF models.              **
REM **                                                              **
REM ** Usage: create_map_file.bat file1.gguf [file2.gguf ...]       **
REM ******************************************************************

if "%~1"=="" (
  echo Usage: %~nx0 file1.gguf [file2.gguf ...]
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:process_files
if "%~1"=="" goto :done
set "GGFILE=%~1"
set "FNAME=%~nx1"

if not exist "%GGFILE%" (
  echo [%DATE% %TIME%] Skipping '%FNAME%': file not found.
  shift
  goto :process_files
)

if /i not "%FNAME:~-5%"==".gguf" (
  echo [%DATE% %TIME%] Skipping '%FNAME%': not a .gguf file.
  shift
  goto :process_files
)

set "DIR=%~dp1"
set "DIR=%DIR:~0,-1%"
set "MAP_FILE=%DIR%\tensors.map"

if not exist "%MAP_FILE%" (
  echo [%DATE% %TIME%] Creating map file: %MAP_FILE%
  type nul > "%MAP_FILE%"
) else (
  echo [%DATE% %TIME%] Appending to existing map: %MAP_FILE%
)

REM Compute SHA256 hash via certutil
set "FILE_HASH="
for /f "skip=1 delims=:" %%h in ('certutil -hashfile "%GGFILE%" SHA256 2^>nul') do (
  if not defined FILE_HASH set "FILE_HASH=%%h"
  set "FILE_HASH=!FILE_HASH: =!"
)

echo [%DATE% %TIME%] Running gguf_info.py on '%FNAME%'...

REM Use Python script to extract tensor info
for /f "usebackq delims=" %%t in (`python "%SCRIPT_DIR%\gguf_info.py" "%GGFILE%" 2^>nul`) do (
  set "line=%%t"
  REM Skip header/empty lines
  if not "!line!"=="" (
    set "first=!line:~0,1!"
    if not "!first!"=="=" (
      REM Parse tab-delimited: tensor_name(tab)shape(tab)dtype(tab)elements(tab)bytes
      for /f "tokens=1-5 delims=	" %%a in ("!line!") do (
        set "tensor_name=%%a"
        set "field_shape=%%b"
        set "field_dtype=%%c"
        set "field_elements=%%d"
        set "field_bytes=%%e"
        if defined tensor_name (
          echo %FNAME%:%FILE_HASH%:!tensor_name!:!field_shape!:!field_dtype!:!field_elements!:!field_bytes! >> "%MAP_FILE%"
        )
      )
    )
  )
)

echo [%DATE% %TIME%] Finished processing '%FNAME%'.
shift
goto :process_files

:done
echo [%DATE% %TIME%] All done.
exit /b 0
