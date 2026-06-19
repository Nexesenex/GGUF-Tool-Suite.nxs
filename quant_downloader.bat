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
REM **   -z          Download .zbst compressed variants             **
REM **   -d          Decompress .zbst files after download          **
REM **   -o DIR      Output directory (default: current)            **
REM **   --help      Show this help                                 **
REM ******************************************************************

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "TENSOR_DOWNLOADER=%SCRIPT_DIR%\tensor_downloader.bat"
set "OUTPUT_DIR="
set "ZBST_FLAG="
set "SKIP_GPG=true"

:parse_args
if "%~1"=="" goto :check_args
if /i "%~1"=="--help" goto :show_help
if "%~1"=="-z" set "ZBST_FLAG=+" & shift & goto :parse_args
if "%~1"=="-d" set "DECOMPRESS=1" & shift & goto :parse_args
if "%~1"=="-o" set "OUTPUT_DIR=%~2" & shift & shift & goto :parse_args
if "%~1"=="--skip-gpg" set "SKIP_GPG=true" & shift & goto :parse_args
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
echo   -z           Download .zbst compressed variants
echo   -d           Decompress .zbst files after download
echo   -o DIR       Output directory
echo   --skip-gpg   Skip GPG verification
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

REM Phase 1: Download all map files for all qtypes in the recipe
echo [%DATE% %TIME%] Phase 1: Downloading map files...
for %%q in (%RECIPE_QTYPES%) do (
  echo [%DATE% %TIME%]   Map for qtype: %%q
  call "%TENSOR_DOWNLOADER%" "%%q" 0 "%OUTPUT_DIR%" "tensors.%%q.map"
)

REM Phase 2: For each recipe regex, match tensors in the designated qtype's map
echo [%DATE% %TIME%] Phase 2: Matching tensors...
for /f "usebackq tokens=1,* delims==" %%r in ("%RECIPE%") do (
  set "FIRST_CHAR=%%r"
  set "FIRST_CHAR=!FIRST_CHAR:~0,1!"
  if not "!FIRST_CHAR!"=="#" if not "!FIRST_CHAR!"=="" if not "!FIRST_CHAR!"=="[" (
    set "REGEX=%%r"
    set "QTYPE_RAW=%%s"
    set "QTYPE_RAW=!QTYPE_RAW: =!"
    if not "!QTYPE_RAW!"=="" (
      set "MAPFILE=%OUTPUT_DIR%\tensors.!QTYPE_RAW!.map"
      if exist "!MAPFILE!" (
        for /f "usebackq tokens=1,3 delims=:" %%a in ("!MAPFILE!") do (
          set "FNAME=%%a"
          set "TENSOR=%%b"
          for /f "delims=" %%m in ('echo !TENSOR!^| findstr /r "!REGEX!"') do (
            set "FNAME_SPACES=!FNAME:-= !"
            set "PREV="
            set "CHUNK="
            for %%w in (!FNAME_SPACES!) do (
              if "%%w"=="of" set "CHUNK=!PREV!"
              set "PREV=%%w"
            )
            if defined CHUNK (
              set /a "CHUNKNUM=1!CHUNK!-100000" 2>nul
              if defined CHUNKNUM (
                if not defined _S_!QTYPE_RAW!_!CHUNKNUM! (
                  set "_S_!QTYPE_RAW!_!CHUNKNUM!=1"
                  call "%TENSOR_DOWNLOADER%" "!QTYPE_RAW!" !CHUNKNUM! "%OUTPUT_DIR%"
                )
              )
            )
          )
        )
      )
    )
  )
)

REM Download shard 00001 from BF16 (base model head, not in any map)
if not defined _S_00001 (
  echo [%DATE% %TIME%] Downloading shard 00001 from BF16...
  set "_S_00001=1"
  call "%TENSOR_DOWNLOADER%" "BF16" 1 "%OUTPUT_DIR%"
)

echo [%DATE% %TIME%] All downloads complete for model %MODEL_NAME%
exit /b 0
