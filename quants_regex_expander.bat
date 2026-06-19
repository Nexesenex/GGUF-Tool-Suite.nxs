@echo off
setlocal enabledelayedexpansion enableextensions

REM ******************************************************************
REM ** quants_regex_expander.bat - Expands tensor regex patterns    **
REM ** for troubleshooting purposes. Windows port of the .sh file.  **
REM **                                                              **
REM ** Reads stdin or uses built-in recipe data.                    **
REM **                                                              **
REM ** Usage: type recipe.recipe ^| quants_regex_expander.bat        **
REM **        quants_regex_expander.bat ^< recipe.txt               **
REM ******************************************************************

REM Use PowerShell to handle the regex expansion logic
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$inputLines = @(); " ^
  "if ($host.Name -eq 'ConsoleHost' -and $MyInvocation.ExpectingInput -eq $false) { " ^
  "  $inputLines = @(" ^
  "    '^^output_norm\.weight^=f32', " ^
  "    '^^output\.weight^=q8_0', " ^
  "    '^^token_embd\.weight^=q8_0', " ^
  "    '^^blk\.([0-9]|[1-5][0-9]|60)\.attn_k_b\.weight^=q8_0', " ^
  "    '^^blk\.([0-9]|[1-5][0-9]|60)\.attn_norm\.weight^=f32', " ^
  "    '^^blk\.([0-9]|[1-5][0-9]|60)\.ffn_norm\.weight^=f32', " ^
  "    '^^blk\.([0-9]|[1-5][0-9]|60)\.ffn_gate_inp\.weight^=f32', " ^
  "    '^^blk\.([0-9]|[1-5][0-9]|60)\.exp_probs_b\.bias^=f32' " ^
  "  ); " ^
  "} else { $inputLines = @($input -split \"`n\"); } " ^
  "" ^
  "function normalizeBareRanges { " ^
  "  param([string]$s) " ^
  "  $depth = 0; $out = ''; $i = 0; " ^
  "  while ($i -lt $s.Length) { " ^
  "    $ch = $s[$i]; " ^
  "    if ($ch -eq '(') { $out += '('; $depth++; $i++ } " ^
  "    elseif ($ch -eq ')') { $out += ')'; if ($depth -gt 0) { $depth-- }; $i++ } " ^
  "    elseif ($ch -eq '[') { " ^
  "      $rest = $s.Substring($i); " ^
  "      $m = [regex]::Match($rest, '^\[([0-9]+)-([0-9]+)\]'); " ^
  "      if ($m.Success) { " ^
  "        if ($depth -eq 0) { $out += '([{0}-{1}])' -f $m.Groups[1].Value, $m.Groups[2].Value } " ^
  "        else { $out += $m.Value } " ^
  "        $i += $m.Length; " ^
  "      } else { $out += '['; $i++ } " ^
  "    } else { $out += $ch; $i++ } " ^
  "  } " ^
  "  return $out; " ^
  "} " ^
  "" ^
  "function expandRanges { " ^
  "  param([string]$line) " ^
  "  $parts = $line -split '='; " ^
  "  $regex = $parts[0]; $qtype = if ($parts.Count -gt 1) { $parts[1] } else { '' }; " ^
  "  $regex = normalizeBareRanges $regex; " ^
  "  " ^
  "  $prefix = ''; $body = $regex; $suffix = ''; " ^
  "  if ($regex -match '\((.*)\)') { " ^
  "    $prefix = $regex.Substring(0, $regex.IndexOf('(')); " ^
  "    $body = $matches[1]; " ^
  "    $suffix = $regex.Substring($regex.LastIndexOf(')') + 1); " ^
  "  } " ^
  "  " ^
  "  # Split on | and expand" ^
  "  $alts = $body -split '\|'; " ^
  "  foreach ($alt in $alts) { " ^
  "    $expanded = @(); " ^
  "    if ($alt -match '\[([0-9]+)-([0-9]+)\]') { " ^
  "      $lo = [int]$matches[1]; $hi = [int]$matches[2]; " ^
  "      for ($n = $lo; $n -le $hi; $n++) { $expanded += $n.ToString() } " ^
  "    } else { $expanded += $alt } " ^
  "    foreach ($e in $expanded) { " ^
  "      $result = $prefix + $e + $suffix; " ^
  "      if ($qtype) { $result += '^=' + $qtype } " ^
  "      $result " ^
  "    } " ^
  "  } " ^
  "} " ^
  "" ^
  "foreach ($line in $inputLines) { " ^
  "  $line = $line.Trim(); " ^
  "  if ($line -eq '' -or $line -match '^\s*#') { continue } " ^
  "  $results = expandRanges $line; " ^
  "  Write-Host $results; " ^
  "} "
