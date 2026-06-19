@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** quant_downloader.bat - Windows port of quant_downloader.sh   **
REM ** Downloads GGUF shards from a recipe file containing tensor   **
REM ** regex entries.                                               **
REM **                                                              **
REM ** Usage: quant_downloader.bat [options] <recipe_file>           **
REM **                                                              **
REM ** Options:                                                     **
REM **   -z                   Download .zbst compressed variants    **
REM **   -d                   Decompress .zbst files after download **
REM **   -o DIR               Output directory (default: current)   **
REM **   --bf16-temp-dir DIR  Temp directory for BF16 shards        **
REM **                        (default: Z:\Temp\)                   **
REM **   --imatrix FILE       Importance matrix file for quantize   **
REM **   --no-imatrix         Skip importance matrix                **
REM **   --force-requantize   Skip download, quantize all from BF16 **
REM **   --help               Show this help                        **
REM ******************************************************************

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TENSOR_DOWNLOADER=%SCRIPT_DIR%\tensor_downloader.bat"
set "OUTPUT_DIR="
set "ZBST_FLAG="
set "SKIP_GPG=true"
set "BF16_TEMP_DIR=Z:\Temp\"
set "USE_IMATRIX=0"
set "IMATRIX_FILE="
set "FORCE_REQUANTIZE=0"
set "REQUANTIZE=0"

:parse_args
if "%~1"=="" goto :check_args
if /i "%~1"=="--help" goto :show_help
if "%~1"=="-z" set "ZBST_FLAG=+" & shift & goto :parse_args
if "%~1"=="-d" set "DECOMPRESS=1" & shift & goto :parse_args
if "%~1"=="-o" set "OUTPUT_DIR=%~2" & shift & shift & goto :parse_args
if "%~1"=="--skip-gpg" set "SKIP_GPG=true" & shift & goto :parse_args
if /i "%~1"=="--bf16-temp-dir" set "BF16_TEMP_DIR=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--imatrix" set "USE_IMATRIX=1" & set "IMATRIX_FILE=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--no-imatrix" set "USE_IMATRIX=0" & set "IMATRIX_FILE=" & shift & goto :parse_args
if /i "%~1"=="--force-requantize" set "FORCE_REQUANTIZE=1" & shift & goto :parse_args
if /i "%~1"=="--requantize" set "REQUANTIZE=1" & shift & goto :parse_args
REM Positional argument - recipe file
if not defined RECIPE set "RECIPE=%~1" & shift & goto :parse_args
goto :show_help

:check_args
if not defined RECIPE goto :show_help
goto :done_args

:show_help
echo Usage: %~nx0 [options] ^<recipe_file^>
echo.
echo Download GGUF model shards from a recipe file.
echo.
echo Options:
echo   -z                   Download .zbst compressed variants
echo   -d                   Decompress .zbst files after download
echo   -o DIR               Output directory
echo   --skip-gpg           Skip GPG verification
echo   --bf16-temp-dir DIR  Temp directory for BF16 shards ^(default: Z:\Temp\^)
echo   --imatrix FILE       Importance matrix file for quantize fallback
echo   --no-imatrix         Skip importance matrix ^(default^)
echo   --force-requantize   Skip download, quantize all shards from BF16
echo   --requantize         Quantize only missing/corrupt shards from BF16
echo.
echo Example:
echo   %~nx0 recipe_examples/my_model.recipe
echo   %~nx0 recipe_examples/my_model.txt
echo   %~nx0 recipe_examples/my_model.recipe.txt
exit /b 2

:done_args
if "%ZBST_FLAG%"=="" set "ZBST_FLAG="

if not exist "%RECIPE%" (
  echo Error: Recipe file not found: %RECIPE%
  exit /b 1
)

REM Validate recipe file extension (.recipe, .recipe.txt, .txt)
for %%f in ("%RECIPE%") do set "fname=%%~nxf"
echo %fname%| findstr /i /e /c:".recipe" >nul 2>&1
if errorlevel 1 (
  echo %fname%| findstr /i /e /c:".txt" >nul 2>&1
  if errorlevel 1 (
    echo Warning: Unrecognized recipe extension. Expected .recipe, .recipe.txt, or .txt.
    echo Accepted: %fname%
  )
)

if not exist "%TENSOR_DOWNLOADER%" (
  echo Error: tensor_downloader.bat not found at %TENSOR_DOWNLOADER%
  exit /b 1
)

REM Parse recipe file
set "SECTION_HEADER="
set "RECIPE_QTYPES="
echo [%DATE% %TIME%] Loading recipe: %RECIPE%

REM Extract model name from recipe (first # Model name: line)
set "MODEL_NAME="
for /f "usebackq tokens=1,* delims=:" %%a in (`findstr /b /l /c:"# Model name:" "%RECIPE%"`) do (
  if not "%%b"=="" set "MODEL_NAME=%%b"
)
if defined MODEL_NAME if "!MODEL_NAME:~0,1!"==" " set "MODEL_NAME=!MODEL_NAME:~1!"
if defined MODEL_NAME if "!MODEL_NAME:~-1!"==" " set "MODEL_NAME=!MODEL_NAME:~0,-1!"

REM Default output dir: SCRIPT_ROOT\MODEL_NAME\ when -o not given
if "%OUTPUT_DIR%"=="" if defined MODEL_NAME set "OUTPUT_DIR=%SCRIPT_DIR%\%MODEL_NAME%"
if "%OUTPUT_DIR%"=="" set "OUTPUT_DIR=%SCRIPT_DIR%\output"

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM Read recipe and extract qtypes
for /f "usebackq tokens=1,* delims==" %%a in ("%RECIPE%") do (
  set "line=%%a=%%b"
  set "line=!line: =!"
  if "!line!"=="" (set "SECTION_HEADER=")
  if not "!line:~0,1!"=="#" if not "!line:~0,1!"=="" (
    set "qtype_only=%%b"
    if not "!qtype_only!"=="" (
      for %%q in (!qtype_only!) do (
        if not defined _QT_%%q (
          set "_QT_%%q=1"
          set "RECIPE_QTYPES=!RECIPE_QTYPES! %%q"
        )
      )
    )
  )
)

REM Ensure BF16 is in RECIPE_QTYPES (always use BF16 map as master list)
if not defined _QT_BF16 (
  set "_QT_BF16=1"
  set "RECIPE_QTYPES=!RECIPE_QTYPES! BF16"
)

REM Auto-detect llama-quantize.exe from IKL directory
if not defined LLAMA_QUANTIZE (
  if exist "%SCRIPT_DIR%\IKL\llama-quantize.exe" set "LLAMA_QUANTIZE=%SCRIPT_DIR%\IKL\llama-quantize.exe"
)
if defined LLAMA_QUANTIZE if exist "!LLAMA_QUANTIZE!" (
  echo [%DATE% %TIME%] Found llama-quantize: !LLAMA_QUANTIZE!
  set "HAVE_LLAMA_QUANTIZE=1"
  if !USE_IMATRIX! equ 1 if not defined IMATRIX_FILE (
    if exist "imatrix_ubergarm.dat" set "IMATRIX_FILE=imatrix_ubergarm.dat"
  )
) else (
  set "HAVE_LLAMA_QUANTIZE=0"
)

REM Build imatrix args for llama-quantize
set "IMATRIX_ARGS="
if !USE_IMATRIX! equ 1 if defined IMATRIX_FILE if exist "!IMATRIX_FILE!" (
  set "IMATRIX_ARGS=--imatrix !IMATRIX_FILE! --ignore-imatrix-rules"
  echo [%DATE% %TIME%] Using imatrix: !IMATRIX_FILE!
)

REM Download shard 00001 from BF16 first (base model head, not in any map)
echo [%DATE% %TIME%] Downloading shard 00001 from BF16...
set "_S_BF16_1=1"
call "%TENSOR_DOWNLOADER%" "BF16" 1 "%OUTPUT_DIR%"

REM Phase 1: Download all map files
echo [%DATE% %TIME%] Phase 1: Downloading map files...
for %%q in (%RECIPE_QTYPES%) do (
  echo [%DATE% %TIME%]   Map for qtype: %%q
  call "%TENSOR_DOWNLOADER%" "%%q" 0 "%OUTPUT_DIR%" "tensors.%%q.map"
)

REM Phase 2: Use Python regex matching to determine qtype per tensor from BF16 master map
echo [%DATE% %TIME%] Phase 2: Matching tensors against recipe patterns...
set "MASTER_MAP=%OUTPUT_DIR%\tensors.BF16.map"
if not exist "!MASTER_MAP!" (
  for %%q in (%RECIPE_QTYPES%) do (
    if not exist "!MASTER_MAP!" (
      set "CANDIDATE=%OUTPUT_DIR%\tensors.%%q.map"
      if exist "!CANDIDATE!" set "MASTER_MAP=!CANDIDATE!"
    )
  )
)
if exist "!MASTER_MAP!" (
  where python >nul 2>&1
  if !errorlevel! equ 0 (set "PYTHON=python"
  ) else (
    where python3 >nul 2>&1
    if !errorlevel! equ 0 (set "PYTHON=python3"
    ) else (
      where py >nul 2>&1
      if !errorlevel! equ 0 (set "PYTHON=py"
      ) else (
        echo Error: Python not found. Required for regex matching.
        exit /b 1
      )
    )
  )
  set "MATCH_OUTPUT=%TEMP%\_qm_!RANDOM!.txt"
  "!PYTHON!" "%SCRIPT_DIR%\match_tensors.py" "%RECIPE%" "!MASTER_MAP!" "!MATCH_OUTPUT!"
  if exist "!MATCH_OUTPUT!" (
    if !FORCE_REQUANTIZE! equ 1 (
      if !HAVE_LLAMA_QUANTIZE! equ 1 (
        echo [%DATE% %TIME%]   --force-requantize: quantizing all shards from BF16...
        for /f "usebackq tokens=1,*" %%x in ("!MATCH_OUTPUT!") do (
          set "QT=%%x"
          set "CH=%%y"
          call :quantize_from_bf16 "!QT!" !CH!
        )
      ) else (
        echo [%DATE% %TIME%]   ERROR: --force-requantize requires llama-quantize
      )
    ) else if !REQUANTIZE! equ 1 (
      if !HAVE_LLAMA_QUANTIZE! equ 1 (
        REM Extract TOTAL from BF16 shard 00001; CHUNK_PREFIX = MODEL_NAME-MAINTAINER
        set "CHUNK_PREFIX=%MODEL_NAME%-THIREUS"
        set "TOTAL_PADDED="
        for %%f in ("%OUTPUT_DIR%\!CHUNK_PREFIX!-BF16-SPECIAL_TENSOR-00001-of-*.gguf") do set "TOTAL_PADDED=%%~nf"
        set "TOTAL_PADDED=!TOTAL_PADDED:*-of-=!"
        echo [%DATE% %TIME%]   --requantize: verifying and re-quantizing missing/corrupt shards...
        for /f "usebackq tokens=1,*" %%x in ("!MATCH_OUTPUT!") do (
          set "QT=%%x"
          set "CH=%%y"
          set "PADDED=00000%%y"
          set "PADDED=!PADDED:~-5!"
          set "FILEPATH=%OUTPUT_DIR%\!CHUNK_PREFIX!-BF16-SPECIAL_TENSOR-!PADDED!-of-!TOTAL_PADDED!.gguf"
          if exist "!FILEPATH!" (
            call :check_gguf_file "!FILEPATH!"
            if !errorlevel! equ 0 (
              echo [%DATE% %TIME%]     Shard !CH! ^(!QT!^) OK, skipping
            ) else (
              echo [%DATE% %TIME%]     Shard !CH! ^(!QT!^) corrupt or invalid, re-quantizing...
              call :quantize_from_bf16 "!QT!" !CH!
            )
          ) else (
            echo [%DATE% %TIME%]     Shard !CH! ^(!QT!^) missing, quantizing...
            call :quantize_from_bf16 "!QT!" !CH!
          )
        )
      ) else (
        echo [%DATE% %TIME%]   ERROR: --requantize requires llama-quantize
      )
    ) else (
      echo [%DATE% %TIME%]   Downloading matched shards...
      for /f "usebackq tokens=1,*" %%x in ("!MATCH_OUTPUT!") do (
        set "QT=%%x"
        set "CH=%%y"
        call "%TENSOR_DOWNLOADER%" "!QT!" !CH! "%OUTPUT_DIR%"
        if errorlevel 1 (
          REM Retry once
          call "%TENSOR_DOWNLOADER%" "!QT!" !CH! "%OUTPUT_DIR%"
          if errorlevel 1 (
            if !HAVE_LLAMA_QUANTIZE! equ 1 (
              echo [%DATE% %TIME%]   Download failed for chunk !CH! (qtype !QT!^), trying BF16 fallback...
              call :quantize_from_bf16 "!QT!" !CH!
            ) else (
              echo [%DATE% %TIME%]   WARNING: Download failed for chunk !CH! (qtype !QT!^) and no llama-quantize available
            )
          )
        )
      )
    )
    del "!MATCH_OUTPUT!" 2>nul
  ) else (
    echo [%DATE% %TIME%]   WARNING: Python matching failed to produce output
  )
) else (
  echo [%DATE% %TIME%]   WARNING: No master map available for tensor matching
)

echo [%DATE% %TIME%] All downloads complete for model %MODEL_NAME%
exit /b 0

:quantize_from_bf16
set "QTYPE=%~1"
set "CHUNK=%~2"

REM Shard 00001 is metadata header, never quantized
if "!CHUNK!"=="1" (
  echo [%DATE% %TIME%]     Shard 00001 is metadata header, skipping
  exit /b 0
)

REM Ensure BF16 temp dir exists
if not exist "%BF16_TEMP_DIR%" mkdir "%BF16_TEMP_DIR%"

REM Download BF16 shard to temp dir
echo [%DATE% %TIME%]     Downloading BF16 chunk !CHUNK! to !BF16_TEMP_DIR!...

REM Build a temp download config that forces the correct output name
call "%TENSOR_DOWNLOADER%" "BF16" !CHUNK! "%BF16_TEMP_DIR%"
if errorlevel 1 (
  echo [%DATE% %TIME%]     ERROR: Failed to download BF16 chunk !CHUNK!
  exit /b 1
)

REM Find first shard in OUTPUT_DIR and copy to BF16_TEMP_DIR
set "FIRST_SHARD_FILE="
for %%f in ("%OUTPUT_DIR%\*-BF16-SPECIAL_TENSOR-00001-of-*.gguf") do (
  if not defined FIRST_SHARD_FILE set "FIRST_SHARD_FILE=%%~nxf"
)
if not defined FIRST_SHARD_FILE (
  echo [%DATE% %TIME%]     ERROR: First shard ^(00001^) not found in !OUTPUT_DIR!
  exit /b 1
)
copy "%OUTPUT_DIR%\!FIRST_SHARD_FILE!" "%BF16_TEMP_DIR%\!FIRST_SHARD_FILE!" >nul

REM Extract CHUNKS_TOTAL from first shard filename
REM Format: *-BF16-SPECIAL_TENSOR-00001-of-TOTAL.gguf
REM Use batch * pat: remove everything up to and including "-of-"
set "PADDED_TOTAL=!FIRST_SHARD_FILE:*-of-=!"
set "PADDED_TOTAL=!PADDED_TOTAL:.gguf=!"
REM Strip leading zeros
set "CHUNKS_TOTAL=!PADDED_TOTAL!"
for /f "tokens=* delims=0" %%z in ("!CHUNKS_TOTAL!") do set "CHUNKS_TOTAL=%%z"
if "!CHUNKS_TOTAL!"=="" set "CHUNKS_TOTAL=0"

REM Build output prefix for llama-quantize --keep-split
REM Use THIREUS as maintainer (hardcoded in tensor_downloader.bat)
set "OUTPUT_PREFIX=%OUTPUT_DIR%\%MODEL_NAME%-THIREUS-BF16-SPECIAL_TENSOR"
set "CHUNK_PREFIX=%MODEL_NAME%-THIREUS"

REM Passthrough types: skip quantization, copy BF16 directly
for %%t in (f32 bf16 f16) do (
  if /i "!QTYPE!"=="%%t" (
    set "PADDED_CHUNK=00000!CHUNK!"
    set "PADDED_CHUNK=!PADDED_CHUNK:~-5!"
    copy "%BF16_TEMP_DIR%\!CHUNK_PREFIX!-BF16-SPECIAL_TENSOR-!PADDED_CHUNK!-of-!PADDED_TOTAL!.gguf" "%OUTPUT_DIR%\!CHUNK_PREFIX!-BF16-SPECIAL_TENSOR-!PADDED_CHUNK!-of-!PADDED_TOTAL!.gguf" >nul
    echo [%DATE% %TIME%]     Copied BF16 shard !CHUNK! to output as !QTYPE! (passthrough)
    REM Clean up all temp files
    del "%BF16_TEMP_DIR%\!CHUNK_PREFIX!-BF16-SPECIAL_TENSOR-!PADDED_CHUNK!-of-!PADDED_TOTAL!.gguf" >nul 2>&1
    del "%BF16_TEMP_DIR%\!FIRST_SHARD_FILE!" >nul 2>&1
    exit /b 0
  )
)

echo [%DATE% %TIME%]     Running: "!LLAMA_QUANTIZE!" --individual-tensors !CHUNK! --keep-split --pure --skip-first-shard !IMATRIX_ARGS! "%BF16_TEMP_DIR%\!FIRST_SHARD_FILE!" "!OUTPUT_PREFIX!.gguf" "!QTYPE!"
"!LLAMA_QUANTIZE!" --individual-tensors !CHUNK! --keep-split --pure --skip-first-shard !IMATRIX_ARGS! "%BF16_TEMP_DIR%\!FIRST_SHARD_FILE!" "!OUTPUT_PREFIX!.gguf" "!QTYPE!"
if errorlevel 1 (
  echo [%DATE% %TIME%]     ERROR: llama-quantize failed for chunk !CHUNK!
  exit /b 1
)

REM Clean up all BF16 shards from temp dir (quiet)
for %%f in ("%BF16_TEMP_DIR%\*-BF16-SPECIAL_TENSOR-*.gguf") do del "%%f" >nul 2>&1

echo [%DATE% %TIME%]     Quantized chunk !CHUNK! to !QTYPE! successfully
exit /b 0

:check_gguf_file
set "FILE=%~1"
if not exist "%FILE%" exit /b 1
< "%FILE%" set /p "magic=" 2>nul
if defined magic if "!magic:~0,4!"=="GGUF" exit /b 0
exit /b 1
