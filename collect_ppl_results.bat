@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** collect_ppl_results.bat - Collects PPL benchmark results    **
REM ** from tensor benchmarking output and compiles ppl_results.csv**
REM ** Windows port of collect_ppl_results.sh.                     **
REM **                                                              **
REM ** Usage: collect_ppl_results.bat [results_directory]           **
REM ******************************************************************

set "RESULT_DIR=%~1"
if "%RESULT_DIR%"=="" set "RESULT_DIR=."

if not exist "%RESULT_DIR%" (
  echo Error: '%RESULT_DIR%' not found.
  exit /b 1
)

echo [%DATE% %TIME%] Collecting PPL results from: %RESULT_DIR%
echo.

REM Look for benchmark output files (*.ppl.txt, *.kld.txt)
set "OUTPUT_CSV=%RESULT_DIR%\ppl_results.csv"
if exist "%OUTPUT_CSV%" (
  echo Warning: %OUTPUT_CSV% already exists, will append.
)

REM Collect results using the Python analysis scripts
if exist "%~dp0ppl_convergence_checker.py" (
  echo [%DATE% %TIME%] Running ppl_convergence_checker.py...
  python "%~dp0ppl_convergence_checker.py" "%RESULT_DIR%"
)

echo.
echo [%DATE% %TIME%] Results collected.
echo.
echo PPL result files found:
for /r "%RESULT_DIR%" %%f in (*ppl*.txt *kld*.txt *perplexity*.txt) do (
  echo   %%f
)

echo.
echo To aggregate results into CSV, use:
echo   python "%~dp0compare_results.py" ^<input_files^>
echo.
echo See docs/Benchmarking models - How.md for details.
exit /b 0
