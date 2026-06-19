@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** quants_regex_merger.bat - Windows port of quants_regex_    **
REM ** merger.sh. Combines tensor regex patterns for               **
REM ** llama-quantize consumption.                                 **
REM **                                                              **
REM ** Usage: python quant_assign.py ... ^| quants_regex_merger.bat **
REM **                                                              **
REM ** Options:                                                     **
REM **   --no-file         Do not write output to a file            **
REM **   --model-name NAME Prepends NAME to the output filename     **
REM **   --add-ppl VALUE   Adds PPL value to the filename           **
REM **   --model-link URL  Adds model link to recipe comments       **
REM ******************************************************************

set "NO_FILE=0"
set "MODEL_NAME="
set "MODEL_LINK="
set "PPL="
set "raw_ppl="

:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="--no-file" set "NO_FILE=1" & shift & goto :parse_args
if /i "%~1"=="--model-name" set "MODEL_NAME=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--model-link" set "MODEL_LINK=%~2" & shift & shift & goto :parse_args
if /i "%~1"=="--add-ppl" set "raw_ppl=%~2" & for /f %%p in ('powershell -NoProfile -C "[math]::Round(%~2,4).ToString('0.0000')"') do set "PPL=%%p" & shift & shift & goto :parse_args
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="--help" goto :show_help
shift
goto :parse_args

:show_help
echo Usage: %~nx0 [--no-file] [--model-name NAME] [--add-ppl VALUE]
echo.
echo   --no-file         Do not write output to a file; just print.
echo   --model-name NAME Optional. Prepends NAME to the output filename.
echo   --add-ppl VALUE   Optional. Adds PPL after username in filename.
echo.
echo Example output filename:
echo   MODEL.USER.PPL_PPL.TOTALGB_GGUF-GPUGB_GPU-CPUGB_CPU.HASH1-HASH2.recipe
exit /b 0

:done_args

REM Check if PPL is valid numeric
if not "%raw_ppl%"=="" (
  echo %raw_ppl%| findstr /r "^[0-9]*\.\?[0-9]*$" >nul
  if errorlevel 1 (
    echo Error: --add-ppl value must be numeric >&2
    exit /b 1
  )
)

REM Read stdin, process with PowerShell for the complex regex merging
REM The core algorithm uses Python/PowerShell for the heavy lifting
set "OUTPUT_FILE="

REM Use PowerShell to handle the merging
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$lines = @(); $input ^| %%{ $lines += $_ }; " ^
  "$modelName = '%MODEL_NAME%'; " ^
  "$ppl = '%PPL%'; " ^
  "$modelLink = '%MODEL_LINK%'; " ^
  "$noFile = %NO_FILE%; " ^
  "" ^
  "# Build output filename" ^
  "$outName = if ($modelName) { $modelName } else { 'recipe' }; " ^
  "if ($ppl) { $outName = $outName + '.' + $ppl + '_PPL'; } " ^
  "$outName = $outName + '.recipe'; " ^
  "" ^
  "# Print the recipe" ^
  "Write-Host \"## Quant mix recipe created using Thireus' GGUF Tool Suite - https://gguf.thireus.com/\"; " ^
  "if ($modelName) { Write-Host \"# Model name: $modelName\"; } " ^
  "if ($modelLink) { Write-Host \"# Link to the original model: $modelLink\"; } " ^
  "Write-Host ''; " ^
  "" ^
  "# Group tensors by prefix and merge numeric ranges" ^
  "$groups = @{}; " ^
  "foreach ($line in $lines) { " ^
  "  $line = $line.Trim(); " ^
  "  if ($line -eq '' -or $line -match '^\s*#') { continue; } " ^
  "  if ($line -match '^\^?(blk)\.([0-9]+)\.(.+)$') { " ^
  "    $prefix = $matches[1]; $num = [int]$matches[2]; $suffix = $matches[3]; " ^
  "    $key = \"${prefix}_${suffix}\"; " ^
  "    if (-not $groups.ContainsKey($key)) { $groups[$key] = @(); } " ^
  "    $groups[$key] += $num; " ^
  "  } else { " ^
  "    Write-Host $line; " ^
  "  } " ^
  "} " ^
  "" ^
  "foreach ($key in $groups.Keys | Sort-Object) { " ^
  "  $nums = $groups[$key] | Sort-Object -Unique; " ^
  "  $prefix = $key.Substring(0, 3); " ^
  "  $suffix = $key.Substring(4); " ^
  "  " ^
  "  # Build ranges from consecutive numbers" ^
  "  $ranges = @(); " ^
  "  $start = $nums[0]; $prev = $nums[0]; " ^
  "  for ($i = 1; $i -lt $nums.Count; $i++) { " ^
  "    if ($nums[$i] -eq $prev + 1) { $prev = $nums[$i]; } " ^
  "    else { $ranges += @($start, $prev); $start = $nums[$i]; $prev = $nums[$i]; } " ^
  "  } " ^
  "  $ranges += @($start, $prev); " ^
  "" ^
  "  # Build regex parts" ^
  "  $parts = @(); " ^
  "  for ($j = 0; $j -lt $ranges.Count; $j += 2) { " ^
  "    $s = $ranges[$j]; $e = $ranges[$j+1]; " ^
  "    if ($s -eq $e) { $parts += $s.ToString(); } " ^
  "    else { " ^
  "      if ($s -le 9 -and $e -le 9) { $parts += \"[$s-$e]\"; } " ^
  "      else { " ^
  "        $sd = [math]::Floor($s / 10); $ed = [math]::Floor($e / 10); " ^
  "        if ($sd -eq $ed) { " ^
  "          $parts += \"$sd[$($s%%10)-$($e%%10)]\"; " ^
  "        } else { $parts += \"[$s-$e]\"; } " ^
  "      } " ^
  "    } " ^
  "  } " ^
  "" ^
  "  $pattern = $parts -join '|'; " ^
  "  if ($parts.Count -gt 1) { $pattern = \"($pattern)\"; } " ^
  "  Write-Host \"^${prefix}\\.${pattern}\\.${suffix}\"; " ^
  "} " ^
  "" ^
  "if (-not $noFile) { " ^
  "  $content = @(); " ^
  "  $content += \"## Quant mix recipe created using Thireus' GGUF Tool Suite - https://gguf.thireus.com/\"; " ^
  "  if ($modelName) { $content += \"# Model name: $modelName\"; } " ^
  "  $content += ''; " ^
  "  foreach ($key in $groups.Keys | Sort-Object) { " ^
  "    $nums = $groups[$key] | Sort-Object -Unique; " ^
  "    $p = $key.Substring(0,3); $sfx = $key.Substring(4); " ^
  "    $ranges = @(); $start = $nums[0]; $prev = $nums[0]; " ^
  "    for ($i = 1; $i -lt $nums.Count; $i++) { " ^
  "      if ($nums[$i] -eq $prev + 1) { $prev = $nums[$i]; } " ^
  "      else { $ranges += @($start, $prev); $start = $nums[$i]; $prev = $nums[$i]; } " ^
  "    } " ^
  "    $ranges += @($start, $prev); " ^
  "    $parts = @(); " ^
  "    for ($j = 0; $j -lt $ranges.Count; $j += 2) { " ^
  "      $s=$ranges[$j]; $e=$ranges[$j+1]; " ^
  "      if ($s -eq $e) { $parts += $s.ToString(); } " ^
  "      else { " ^
  "        if ($s -le 9 -and $e -le 9) { $parts += \"[$s-$e]\"; } " ^
  "        else { " ^
  "          $sd=[math]::Floor($s/10); $ed=[math]::Floor($e/10); " ^
  "          if ($sd -eq $ed) { $parts += \"$sd[$($s%%10)-$($e%%10)]\"; } " ^
  "          else { $parts += \"[$s-$e]\"; } } } } " ^
  "    $pattern = $parts -join '|'; " ^
  "    if ($parts.Count -gt 1) { $pattern = \"($pattern)\"; } " ^
  "    $content += \"^\${p}\\.\${pattern}\\.\${sfx}\"; " ^
  "  } " ^
  "  Set-Content -Path $outName -Value ($content -join [Environment]::NewLine); " ^
  "  Write-Host \"Recipe written to: $outName\"; " ^
  "} "
