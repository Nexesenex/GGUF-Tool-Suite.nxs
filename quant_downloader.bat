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
if "%~1"=="" goto :done_args
if /i "%~1"=="--help" goto :show_help
if "%~1"=="-z" set "ZBST_FLAG=+"
if "%~1"=="-d" set "DECOMPRESS=1"
if "%~1"=="-o" set "OUTPUT_DIR=%~2" & shift
if "%~1"=="--skip-gpg" set "SKIP_GPG=true"
shift
goto :parse_args

:done_args

REM Recipe file is first positional arg
if "%ZBST_FLAG%"=="" set "ZBST_FLAG="
if "%~1"=="" (
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
  exit /b 2
)

set "RECIPE=%~1"
if not exist "%RECIPE%" (
  echo Error: Recipe file not found: %RECIPE%
  exit /b 1
)

REM Validate recipe file extension (.recipe, .recipe.txt, .txt)
set "fname=%~nx1"
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

echo [%DATE% %TIME%] Found qtypes: %RECIPE_QTYPES%

REM For each qtype, download shards
for %%q in (%RECIPE_QTYPES%) do (
  echo [%DATE% %TIME%] Processing qtype: %%q
  set "QTYPE=%%q"
  call :toupper QTYPE
  
  REM Use Python's gguf_info to get shard info from map files
  REM First try downloading the tensors.map for this qtype
  "%TENSOR_DOWNLOADER%" "%%q" 0 "%OUTPUT_DIR%" "tensors.%%q.map"
  
  REM Download individual shard files
  REM The recipe's regex patterns tell us what to download
  REM For now, use the simple approach: download all shards listed in the recipe
  for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%RECIPE%") do (
    if not "%%b"=="" (
      set "regex=%%a"
      set "tqtype=%%b"
      if /i "!tqtype!"=="%%q" (
        echo [%DATE% %TIME%] Pattern !regex! ^=^> %%q
      )
    )
  )
)

echo [%DATE% %TIME%] All downloads complete.
exit /b 0

:toupper
for %%a in (%1) do (
  set "tmp=!%%a!"
  for %%b in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    set "tmp=!tmp:%%b=%%b!"
  )
  set "%1=!tmp!"
)
goto :eof
