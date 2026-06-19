@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** quantize_model.bat - Windows port of quantize_model.sh      **
REM ** Produces quantized shard repositories from BF16 shards.     **
REM **                                                              **
REM ** Usage: quantize_model.bat --model MODEL --qtype QTYPE        **
REM **                                                              **
REM ** Required:                                                    **
REM **   --model NAME        Model name for repo prefixes           **
REM **   --qtype QTYPE       Target GGUF quantization dtype         **
REM **                                                              **
REM ** Options:                                                     **
REM **   --maintainer NAME   Maintainer tag (default: THIREUS)      **
REM **   --llama-quantize PATH   llama-quantize binary path         **
REM **   --source-dir PATH   BF16 source shard directory            **
REM **   --destination-dir PATH   Output directory                  **
REM **   --imatrix PATH      Imatrix file (default: imatrix_ubergarm.dat) **
REM **   --no-imatrix        Skip importance matrix                 **
REM **   --ik-fallback       Use ik_llama.cpp fallback pool         **
REM **   -h, --help          Show this help                        **
REM ******************************************************************

set "MODEL="
set "TARGET_QTYPE="
set "MAINTAINER=THIREUS"
set "LLAMA_QUANTIZE_BIN=llama-quantize.exe"
set "IMATRIX_FILE=imatrix_ubergarm.dat"
set "USE_IMATRIX=1"
set "SOURCE_DIR="
set "TARGET_DIR="
set "USE_IK_FALLBACK=0"

:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="--help" goto :show_help
if /i "%~1"=="--model" set "MODEL=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--qtype" set "TARGET_QTYPE=%~2" & call :toupper TARGET_QTYPE & shift & shift & goto :parse_args
if /i "%~1"=="--maintainer" set "MAINTAINER=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--llama-quantize" set "LLAMA_QUANTIZE_BIN=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--source-dir" set "SOURCE_DIR=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--destination-dir" set "TARGET_DIR=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--imatrix" set "IMATRIX_FILE=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--no-imatrix" set "USE_IMATRIX=0" & shift & goto :parse_args
if /i "%~1"=="--ik-fallback" set "USE_IK_FALLBACK=1" & shift & goto :parse_args
shift
goto :parse_args

:show_help
echo Usage: %~nx0 --model MODEL --qtype QTYPE [options]
echo.
echo Required:
echo   --model NAME       Model name used to derive repo prefixes.
echo   --qtype QTYPE      Target GGUF quantization dtype.
echo.
echo Options:
echo   --maintainer NAME  Maintainer tag (default: THIREUS)
echo   --llama-quantize PATH  llama-quantize binary to use
echo   --source-dir PATH  BF16 source shard directory
echo   --destination-dir PATH  Output directory
echo   --imatrix PATH     Imatrix file (default: imatrix_ubergarm.dat)
echo   --no-imatrix       Do not use imatrix
echo   --ik-fallback      Use ik_llama.cpp fallback pool
echo   -h, --help         Show this help
exit /b 0

:done_args

if "%MODEL%"=="" ( echo Error: --model is required. & exit /b 20 )
if "%TARGET_QTYPE%"=="" ( echo Error: --qtype is required. & exit /b 20 )
if /i "%TARGET_QTYPE%"=="BF16" ( echo Error: BF16 is reserved. & exit /b 24 )

REM Set up directories
if "%SOURCE_DIR%"=="" set "SOURCE_DIR=%MODEL%-%MAINTAINER%-BF16-SPECIAL_SPLIT"
if "%TARGET_DIR%"=="" set "TARGET_DIR=%MODEL%-%MAINTAINER%-%TARGET_QTYPE%-SPECIAL_SPLIT"

set "SOURCE_PREFIX=%MODEL%-%MAINTAINER%-BF16-SPECIAL_TENSOR"
set "TARGET_PREFIX=%MODEL%-%MAINTAINER%-%TARGET_QTYPE%-SPECIAL_TENSOR"

REM Find first shard to determine chunk total
set "FIRST_SHARD="
for %%f in ("%SOURCE_DIR%\%SOURCE_PREFIX%-00001-of-*.gguf") do set "FIRST_SHARD=%%f"
if "%FIRST_SHARD%"=="" ( echo Error: First source shard not found. & exit /b 27 )

for /f "tokens=4 delims=-" %%a in ("%FIRST_SHARD%") do set "CHUNKS_TOTAL=%%~na"

REM Build output directory
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

REM Count existing shards for resume
set "RESUME_START=2"
set "HIGHEST_ID=0"
for %%f in ("%TARGET_DIR%\%TARGET_PREFIX%-*-of-%CHUNKS_TOTAL%.gguf") do (
  set "fname=%%~nf"
  for /f "tokens=3 delims=-" %%a in ("!fname!") do (
    set "sid=%%a"
    REM Remove leading zeros
    for /f "tokens=* delims=0" %%b in ("!sid!") do set "sid=%%b"
    if "!sid!"=="" set "sid=0"
    if !sid! gtr !HIGHEST_ID! set "HIGHEST_ID=!sid!"
  )
)

if !HIGHEST_ID! gtr 0 (
  set /a "RESUME_START=HIGHEST_ID"
  echo [%DATE% %TIME%] Resuming from shard !RESUME_START!^(found !HIGHEST_ID! existing shards^)
)

REM Main quantization loop
for /l %%i in (!RESUME_START!,1,%CHUNKS_TOTAL%) do (
  set "CHUNK_ID=%%i"
  call :padnum CHUNK_ID 5
  
  set "SOURCE_SHARD=%SOURCE_DIR%\%SOURCE_PREFIX%-!CHUNK_ID!-of-%CHUNKS_TOTAL%.gguf"
  set "OUTPUT_SHARD=%TARGET_DIR%\%TARGET_PREFIX%.gguf"
  set "OUTPUT_ACTUAL=%TARGET_DIR%\%TARGET_PREFIX%-!CHUNK_ID!-of-%CHUNKS_TOTAL%.gguf"
  
  if not exist "!SOURCE_SHARD!" (
    echo Error: Source shard %%i not found: !SOURCE_SHARD!
    exit /b 29
  )
  
  if exist "!OUTPUT_ACTUAL!" (
    echo [%DATE% %TIME%] Shard %%i already exists, skipping.
    continue
  )
  
  echo [%DATE% %TIME%] Quantizing shard %%i/%CHUNKS_TOTAL% to %TARGET_QTYPE%...
  
  REM Build llama-quantize arguments
  set "IMATRIX_ARGS="
  if !USE_IMATRIX! equ 1 if exist "%IMATRIX_FILE%" set "IMATRIX_ARGS=--imatrix %IMATRIX_FILE%"
  
  if %%i leq 2 (set "SKIP_FIRST=") else (set "SKIP_FIRST=--skip-first-shard")
  
  "%LLAMA_QUANTIZE_BIN%" !SKIP_FIRST! --keep-split --pure !IMATRIX_ARGS! --ignore-imatrix-rules --individual-tensors %%i "%SOURCE_DIR%\%SOURCE_PREFIX%-00001-of-%CHUNKS_TOTAL%.gguf" "!OUTPUT_SHARD!" "%TARGET_QTYPE%"
  
  if errorlevel 1 (
    echo [%DATE% %TIME%] Shard %%i failed. Cleaning up partial output.
    del "!OUTPUT_ACTUAL!" 2>nul
  ) else (
    echo [%DATE% %TIME%] Shard %%i completed successfully.
    attrib +R "!OUTPUT_ACTUAL!" 2>nul
  )
)

echo [%DATE% %TIME%] Quantization complete.
exit /b 0

:padnum
set "val=%~1"
set "padded=%val%"
for /l %%i in (1,1,5) do if "!padded:~%%i,1!"=="" set "padded=0!padded!"
set "%val%=%padded%"
goto :eof

:toupper
for %%a in (%1) do (
  set "tmp=!%%a!"
  for %%b in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    set "tmp=!tmp:%%b=%%b!"
  )
  set "%1=!tmp!"
)
goto :eof
