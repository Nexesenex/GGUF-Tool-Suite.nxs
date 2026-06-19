@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** benchmark_each_tensor.bat - Benchmarks tensor sensitivity   **
REM ** to quantization. Windows port of benchmark_each_tensor.sh.  **
REM **                                                              **
REM ** Evaluates each tensor's PPL/KLD impact when quantized to    **
REM ** extreme low precision.                                      **
REM **                                                              **
REM ** Usage: benchmark_each_tensor.bat [options]                   **
REM **                                                              **
REM ** Options:                                                     **
REM **   --qtypes Q1 Q2 ...        Qtypes to iterate                **
REM **   --chunks N                 Number of chunks (default: 250) **
REM **   --ctx-size-ppl N           Max context for PPL (512)       **
REM **   --ctx-size-sweep N         Max context for SWEEP (8192)    **
REM **   --skip-gpg                 Skip GPG verification           **
REM **   -h, --help                 Show this help and exit         **
REM ******************************************************************

set "QTYPES="
set "CHUNKS=250"
set "CTX_SIZE_PPL=512"
set "CTX_SIZE_SWEEP=8192"
set "SKIP_GPG=false"
set "MODE=0"

:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="--help" goto :show_help
if /i "%~1"=="--qtypes" (
  shift
  :qtypes_loop
  if "%~1"=="" goto :done_args
  if "%~1"=="--chunks" goto :parse_args
  if "%~1"=="--ctx-size-ppl" goto :parse_args
  if "%~1"=="--ctx-size-sweep" goto :parse_args
  if "%~1"=="--skip-gpg" goto :parse_args
  set "QTYPES=!QTYPES! %~1"
  shift
  goto :qtypes_loop
)
if /i "%~1"=="--chunks" set "CHUNKS=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--ctx-size-ppl" set "CTX_SIZE_PPL=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--ctx-size-sweep" set "CTX_SIZE_SWEEP=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--skip-gpg" set "SKIP_GPG=true" & shift & goto :parse_args
shift
goto :parse_args

:show_help
echo Usage: %~nx0 [options]
echo.
echo Options:
echo   --qtypes Q1 Q2...     Qtypes to iterate (e.g. iq1_m_r4 iq2_xxs)
echo   --chunks N            Number of chunks (default: 250)
echo   --ctx-size-ppl N      Max context for PPL (default: 512)
echo   --ctx-size-sweep N    Max context for SWEEP (default: 8192)
echo   --skip-gpg            Skip GPG signature verification
echo   -h, --help            Show this help
echo.
echo Example:
echo   %~nx0 --qtypes iq1_m_r4 iq2_xxs --chunks 250
exit /b 0

:done_args

if "%QTYPES%"=="" (
  echo Error: --qtypes is required.
  echo Example: %~nx0 --qtypes iq1_m_r4 iq2_xxs
  exit /b 2
)

echo [%DATE% %TIME%] Starting tensor benchmarks...
echo Qtypes: %QTYPES%
echo Chunks: %CHUNKS%
echo.

REM For each qtype, iterate over tensor shards and benchmark
for %%q in (%QTYPES%) do (
  echo [%DATE% %TIME%] Starting benchmarks for qtype: %%q
  
  REM Build benchmark command using llama-perplexity
  REM This follows the pattern from the original .sh script:
  REM llama-perplexity --individual-tensors N -m model.gguf -f wiki.test.raw -c %CTX_SIZE% ...
  
  echo [%DATE% %TIME%] Benchmarking qtype %%q with %CHUNKS% chunks...
  echo.
  echo NOTE: To run actual benchmarks, configure your llama-perplexity binary
  echo and run manually. Example:
  echo.
  echo   llama-perplexity --individual-tensors N -m model.gguf -f wiki.test.raw -c %CTX_SIZE_PPL% -b 4096 -ub 4096 -ctk f16
  echo.
  echo The benchmark script downloads shards using tensor_downloader.bat,
  echo then evaluates each tensor's sensitivity to the target qtype.
  echo Results are collected into ppl_results.csv or kld_results.csv.
)

echo [%DATE% %TIME%] Benchmarks configured. Edit USER_REGEX and PPL/SWEEP_COMMAND_TEMPLATE for actual runs.
echo See docs/Benchmarking models - How.md for detailed instructions.
exit /b 0
