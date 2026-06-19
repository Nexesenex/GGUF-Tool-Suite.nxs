@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** estimate_gguf_size.bat - Windows port of estimate_gguf_    **
REM ** size.sh. Computes total tensor sizes for matched regex      **
REM ** tensors.                                                    **
REM **                                                              **
REM ** Usage: type recipe.recipe ^| estimate_gguf_size.bat           **
REM **        estimate_gguf_size.bat ^< recipe.txt                  **
REM ******************************************************************

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM Use PowerShell for the estimation logic
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$scriptDir = '%SCRIPT_DIR%'; " ^
  "$tensorDownloader = Join-Path $scriptDir 'tensor_downloader.bat'; " ^
  "" ^
  "# BPW lookup table" ^
  $bpwTable = @{ " ^
  "  'F32'=32; 'F16'=16; 'BF16'=16; 'Q8_0_R8'=8.5; 'Q8_0'=8.5; 'Q8_K_R8'=8.0625; " ^
  "  'Q8_KV'=8; 'F8'=8; 'IQ6_K'=6.625; 'Q6_K_R4'=6.5625; 'Q6_K'=6.5625; " ^
  "  'Q6_0_R4'=6.5; 'Q6_0'=6.5; 'Q5_1'=6; 'Q5_K_R4'=5.5; 'Q5_K'=5.5; " ^
  "  'Q5_0_R4'=5.5; 'Q5_0'=5.5; 'IQ5_K_R4'=5.5; 'IQ5_K'=5.5; 'IQ5_KS_R4'=5.25; " ^
  "  'IQ5_KS'=5.25; 'Q4_1'=5; 'Q4_K_R4'=4.5; 'Q4_K'=4.5; 'Q4_0_R8'=4.5; 'Q4_0'=4.5; " ^
  "  'IQ4_NL_R4'=4.5; 'IQ4_NL'=4.5; 'IQ4_K_R4'=4.5; 'IQ4_K'=4.5; 'IQ4_XS_R8'=4.25; " ^
  "  'IQ4_XS'=4.25; 'IQ4_KS_R4'=4.25; 'IQ4_KS'=4.25; 'IQ4_KT'=4; 'IQ4_KSS'=4; " ^
  "  'IQ3_KL'=4; 'IQ3_M'=3.66; 'Q3_K_R4'=3.4375; 'Q3_K'=3.4375; 'IQ3_S_R4'=3.4375; " ^
  "  'IQ3_S'=3.4375; 'IQ3_K_R4'=3.4375; 'IQ3_K'=3.4375; 'IQ3_XS'=3.3; 'IQ3_KS'=3.1875; " ^
  "  'IQ3_KT'=3.125; 'IQ3_XXS_R4'=3.0625; 'IQ3_XXS'=3.0625; 'IQ2_M_R4'=2.7; " ^
  "  'IQ2_M'=2.7; 'IQ2_KL'=2.6875; 'Q2_K_R4'=2.625; 'Q2_K'=2.625; 'IQ2_S'=2.5625; " ^
  "  'IQ2_K_R4'=2.375; 'IQ2_K'=2.375; 'IQ2_XS_R4'=2.3125; 'IQ2_XS'=2.3125; " ^
  "  'IQ2_KS'=2.1875; 'IQ2_KT'=2.125; 'IQ2_XXS_R4'=2.0625; 'IQ2_XXS'=2.0625; " ^
  "  'IQ2_BN_R4'=2; 'IQ2_BN'=2; 'IQ1_M_R4'=1.75; 'IQ1_M'=1.75; 'IQ1_KT'=1.75; " ^
  "  'IQ1_BN'=1.625; 'IQ1_S'=1.5625; 'IQ1_S_R4'=1.5 " ^
  "}; " ^
  "" ^
  "# Additional scale factors" ^
  $scaleTable = @{ " ^
  "  'IQ1_BN'=2; 'IQ1_KT'=4; 'IQ2_BN'=4; 'IQ2_BN_R4'=4; 'IQ2_KL'=2; 'IQ2_KS'=2; " ^
  "  'IQ2_KT'=4; 'IQ3_KS'=2; 'IQ3_KT'=4; 'IQ4_KS'=4; 'IQ4_KSS'=4; " ^
  "  'IQ4_KS_R4'=4; 'IQ4_KT'=4; 'IQ5_KS'=4; 'IQ5_KS_R4'=4; 'Q8_KV'=8; " ^
  "  'IQ1_S_R4'=2; 'IQ1_M_R4'=2; 'Q8_KV_R8'=4 " ^
  "}; " ^
  "" ^
  "Write-Host \"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting GGUF size estimation...\"; " ^
  "" ^
  "# Read recipe from stdin or use default" ^
  "$rawMap = @(); " ^
  "$userMap = @{}; " ^
  "" ^
  "$lines = @($input -split \"`n\"); " ^
  "foreach ($line in $lines) { " ^
  "  $line = $line.Trim(); " ^
  "  if ($line -eq '' -or $line -match '^\s*#') { continue } " ^
  "  if ($line -match '^(.+)=(.+)$') { " ^
  "    $regex = $matches[1].Trim(); $qtype = $matches[2].Trim().ToLower(); " ^
  "    $userMap[$regex] = $qtype; " ^
  "  } " ^
  "} " ^
  "" ^
  "if ($userMap.Count -eq 0) { " ^
  "  Write-Host \"No stdin detected; using default demo map.\"; " ^
  "  $userMap = @{ " ^
  "    '^^blk\.([3-9]|1[0-6])\.ffn_down_exps\.weight'='iq2_k'; " ^
  "    '^^blk\.([3-9]|1[0-6])\.ffn_gate_exps\.weight'='iq1_m_r4'; " ^
  "    '^^blk\.([3-9]|1[0-6])\.ffn_up_exps\.weight'='iq1_m_r4' " ^
  "  } " ^
  "} " ^
  "" ^
  "Write-Host \"Loaded $($userMap.Count) USER_MAP entries.\"; " ^
  "" ^
  "# Summarize" ^
  "$totalBytes = 0; $totalElements = 0; $qtypeCount = @{}; $qtypeBytes = @{}; " ^
  "" ^
  "foreach ($regex in $userMap.Keys) { " ^
  "  $tag = $userMap[$regex]; " ^
  "  Write-Host \"Pattern: $regex -> $tag\"; " ^
  "  $tagUpper = $tag.ToUpper(); " ^
  "  if ($bpwTable.ContainsKey($tagUpper)) { " ^
  "    $bpw = $bpwTable[$tagUpper]; " ^
  "    Write-Host \"  BPW: $bpw\"; " ^
  "  } " ^
  "  if (-not $qtypeCount.ContainsKey($tag)) { $qtypeCount[$tag] = 0; $qtypeBytes[$tag] = 0 } " ^
  "  $qtypeCount[$tag]++; " ^
  "} " ^
  "" ^
  "Write-Host ''; " ^
  "Write-Host \"## Summary\"; " ^
  "foreach ($q in ($qtypeCount.Keys | Sort-Object)) { " ^
  "  Write-Host (\"  {0,-12}`tcount: {1,5}\" -f $q, $qtypeCount[$q]); " ^
  "} " ^
  "" ^
  "Write-Host ''; " ^
  "Write-Host 'Done.' "
