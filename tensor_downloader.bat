@echo off
setlocal enabledelayedexpansion enableextensions

REM *****************************************************************
REM ** tensor_downloader.bat - Windows port of tensor_downloader.sh **
REM ** Downloads pre-quantised tensors/shards to cook recipes.     **
REM **                                                             **
REM ** Usage: tensor_downloader.bat QUANT FileID [DestDir] [Fname] **
REM **                                                             **
REM **   QUANT    - quantization tag, e.g. "BF16"                   **
REM **   FileID   - integer chunk ID; 0=>tensors.map,              **
REM **              -1=>tensors.map.sig, -2=>*-00001-of-*.gguf.sig **
REM **   DestDir  - output directory (default: .)                   **
REM **   Fname    - output filename (default: auto-detected)        **
REM *****************************************************************

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM ---- Default configuration (can be overridden in download.conf) ----
set "MODEL_NAME=DeepSeek-R1-0528"
set "MAINTAINER=THIREUS"
set "CHUNK_FIRST=2"
set "CHUNKS_TOTAL=1148"

REM ---- Load download.conf if present ----
REM Only MODEL_NAME, MAINTAINER, CHUNK_FIRST, CHUNKS_TOTAL are read
if exist "%SCRIPT_DIR%\download.conf" (
  for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%SCRIPT_DIR%\download.conf") do (
    set "_k=%%a"
    set "_v=%%b"
    if defined _k if defined _v (
      set "_k=!_k: =!"
      if not "!_k!"=="" if "!_k!"=="!_k:(=!" (
        for %%x in (MODEL_NAME MAINTAINER CHUNK_FIRST CHUNKS_TOTAL) do (
          if /i "!_k!"=="%%x" (
            set "_v=!_v:"=!"
            set "_v=!_v: =!"
            set "%%x=!_v!"
          )
        )
      )
    )
  )
)

REM ---- Parse arguments ----
if "%~1"=="" goto :show_usage

set "QUANT=%~1"
set "FILEID=%~2"
set "DEST=%~3"
set "CUSTOM_FILENAME=%~4"

if "%FILEID%"=="" goto :show_usage

goto :after_usage

:show_usage
echo Usage: %~nx0 QUANT FileID [DestinationDir] [Filename]
echo.
echo   QUANT    ^(mandatory^) quantization tag, e.g. "BF16"
echo   FileID   ^(mandatory^) integer chunk ID; 0=tensors.map, -1=tensors.map.sig
echo   DestDir  ^(optional^) default: "."
echo   Filename ^(optional^) default: auto-detected
exit /b 2

:after_usage

set "QUANT=%~1"
set "FILEID=%~2"
set "DEST=%~3"
set "CUSTOM_FILENAME=%~4"

if "%DEST%"=="" set "DEST=."
if not exist "%DEST%" mkdir "%DEST%"

REM Normalize QUANT to uppercase
for %%a in ("%QUANT%") do set "QUANT_U=%%~nxa"
call :toupper QUANT_U
set "REPO=%MODEL_NAME%-%MAINTAINER%-%QUANT_U%-SPECIAL_SPLIT"
set "CHUNKS_PAD=%CHUNKS_TOTAL%"
call :padnum CHUNKS_PAD 5

set "ZBST_FLAG=0"
if "%FILEID:~0,1%"=="+" (
  set "ZBST_FLAG=1"
  set "FILEID=!FILEID:~1!"
)

REM Build filename
if "%FILEID%"=="0" (
  set "FILENAME=tensors.map"
) else if "%FILEID%"=="-1" (
  set "FILENAME=tensors.map.sig"
) else if "%FILEID%"=="-2" (
  set "FILENAME=%MODEL_NAME%-%MAINTAINER%-%QUANT_U%-SPECIAL_TENSOR-00001-of-%CHUNKS_PAD%.gguf.sig"
) else (
  set "IDX=%FILEID%"
  call :padnum IDX 5
  set "FILENAME=%MODEL_NAME%-%MAINTAINER%-%QUANT_U%-SPECIAL_TENSOR-%IDX%-of-%CHUNKS_PAD%.gguf"
)
if "%CUSTOM_FILENAME%"=="" set "CUSTOM_FILENAME=%FILENAME%"

echo [%DATE% %TIME%] Starting download of %FILENAME% into %DEST%

REM ---- Download methods (HUGGINGFACE, CURL, COPY) ----
REM RSYNC and SYMLINK skipped (not practical on Windows)

REM ---- Common curl options ----
set "CURL_OPTS=-f -L --retry 3 --retry-delay 5 --connect-timeout 15 --ssl-no-revoke -#"
set "CURL_AUTH="
if defined HF_TOKEN set "CURL_AUTH=-H Authorization: Bearer %HF_TOKEN%"

REM ---- HuggingFace download ----
set "HF_ORG=Thireus"
set "HF_BRANCH=main"
set "HF_URL=https://huggingface.co/%HF_ORG%/%REPO%/resolve/%HF_BRANCH%/%FILENAME%?download=true"
set "DST=%DEST%\%CUSTOM_FILENAME%"

if not exist "%DST%" (
  echo [%DATE% %TIME%] Trying HuggingFace from %HF_URL%
  curl.exe %CURL_OPTS% %CURL_AUTH% "%HF_URL%" -o "%DST%" 2>&1
  if !errorlevel! equ 0 (
    call :verify_file "%DST%"
    if !errorlevel! equ 0 (
      echo [%DATE% %TIME%] ^(OK^) Downloaded via HuggingFace - %DST%
      attrib +R "%DST%" 2>nul
      exit /b 0
    ) else (
      del "%DST%" 2>nul
    )
  ) else (
    del "%DST%" 2>nul
    echo [%DATE% %TIME%] HuggingFace failed, trying alternatives...
  )
) else (
  call :verify_file "%DST%"
  if !errorlevel! equ 0 (
    echo [%DATE% %TIME%] ^(OK^) File already exists and verified - %DST%
    exit /b 0
  ) else (
    echo [%DATE% %TIME%] Verification failed, re-downloading...
    del "%DST%" 2>nul
  )
)

REM ---- CURL download from gguf.thireus.com ----
set "CURL_BASE=https://gguf5.thireus.com"
set "CURL_URL=%CURL_BASE%/%REPO%/%FILENAME%"

curl.exe %CURL_OPTS% "%CURL_URL%" -o "%DST%" 2>&1
if !errorlevel! equ 0 (
  call :verify_file "%DST%"
  if !errorlevel! equ 0 (
    echo [%DATE% %TIME%] ^(OK^) Downloaded via CURL - %DST%
    attrib +R "%DST%" 2>nul
    exit /b 0
  ) else (
    del "%DST%" 2>nul
  )
) else (
  del "%DST%" 2>nul
)

echo [%DATE% %TIME%] ERROR: All download methods failed for %FILENAME%
exit /b 1

REM ---- Helper functions ----
:toupper
for %%a in (%1) do (
  set "tmp=!%%a!"
  for %%b in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    set "tmp=!tmp:%%b=%%b!"
  )
  set "%1=!tmp!"
)
goto :eof

:padnum
set "val=%1"
set "pad=%~2"
set "padded=%val%"
for /l %%i in (1,1,%pad%) do if "!padded:~%%i,1!"=="" set "padded=0!padded!"
set "%val%=%padded%"
goto :eof

:verify_file
set "file=%~1"
if not exist "%file%" exit /b 1
if "%FILEID%"=="0" exit /b 0
if "%FILEID%"=="-1" exit /b 0
if "%FILEID%"=="-2" exit /b 0

REM Check GGUF magic bytes: first 4 bytes should be "GGUF"
for /f "skip=1 delims=:" %%a in ('certutil -encodehex "%file%" 2^>nul ^| findstr /r "^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]"') do (
  set "hex=%%a"
  goto :check_magic
)
:check_magic
if defined hex (
  if "!hex:~0,4!"=="4747" if "!hex:~4,4!"=="5546" (exit /b 0) else (exit /b 1)
)
exit /b 0
