@echo off
setlocal enabledelayedexpansion enableextensions

set "CURRENT="
set "SHOW_CHAIN=0"
set "FALLBACKS="
set "ARGS="

:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="--current" set "CURRENT=%~2" & set "ARGS=!ARGS! --current %~2" & shift & shift & goto :parse_args
if /i "%~1"=="--fallbacks" goto :handle_fallbacks
if /i "%~1"=="--chain" set "SHOW_CHAIN=1" & set "ARGS=!ARGS! --chain" & shift & goto :parse_args
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="--help" goto :show_help
shift
goto :parse_args

:handle_fallbacks
set "ARGS=!ARGS! --fallbacks"
shift

:fallback_loop
if "%~1"=="" goto :done_args
if /i "%~1"=="--chain" set "SHOW_CHAIN=1" & set "ARGS=!ARGS! --chain" & shift & goto :parse_args
if /i "%~1"=="--current" goto :parse_args
if defined FALLBACKS (set "FALLBACKS=!FALLBACKS! %~1") else (set "FALLBACKS=%~1")
set "ARGS=!ARGS! %~1"
shift
goto :fallback_loop

:show_help
echo Usage: %~nx0 --current QTYPE --fallbacks Q1 Q2... [--chain]
echo.
echo   --current QTYPE  The qtype that just failed.
echo   --fallbacks ...  Space-separated fallback pool.
echo   --chain          Print the full ordered fallback chain.
exit /b 0

:done_args
if "%CURRENT%"=="" echo Error: --current is required. & exit /b 2
if "%FALLBACKS%"=="" echo Error: --fallbacks requires at least one qtype. & exit /b 2

python "%~dp0fallback.py" !ARGS!
exit /b 0
