@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** collect_sweep_results.bat - Collects SWEEP benchmark results*
REM ** Windows port of collect_sweep_results.sh.                    **
REM **                                                              **
REM ** Usage: collect_sweep_results.bat [results_directory]         **
REM ******************************************************************

set "RESULT_DIR=%~1"
if "%RESULT_DIR%"=="" set "RESULT_DIR=."

if not exist "%RESULT_DIR%" (
  echo Error: '%RESULT_DIR%' not found.
  exit /b 1
)

echo [%DATE% %TIME%] Collecting SWEEP results from: %RESULT_DIR%
echo.

REM Look for sweep output files (*.sweep.txt, *sweep*.txt)
set "OUTPUT_CSV=%RESULT_DIR%\sweep_results.csv"
if exist "%OUTPUT_CSV%" (
  echo Warning: %OUTPUT_CSV% already exists, will append.
)

echo [%DATE% %TIME%] Searching for sweep result files...
for /r "%RESULT_DIR%" %%f in (*sweep*.txt) do (
  echo   Processing: %%f
  set "DATA="
  for /f "usebackq delims=" %%a in ("%%f") do (
    if not defined DATA (
      set "DATA=1"
      REM Parse header from sweep output
      echo %%a
    )
  )
)

echo.
echo [%DATE% %TIME%] Sweep results collected.
echo.
echo To visualize results:
echo   python "%~dp0plot_llama_sweep.py" ^<sweep_files^>
echo   python "%~dp0plot_recipes.py" ^<recipe_files^>
echo.
echo See docs/Benchmarking models - How.md for details.
exit /b 0
