param(
    [string]$Godot = $env:GODOT_BIN
)

# Permanent headless QA suite. Override the engine path with $env:GODOT_BIN or
# -Godot "C:\path\to\Godot_v4.6.3-stable_win64_console.exe".
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = "C:\portable_programs\Godot_v4.6-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
}

$repo = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repo "SandEEAlpha"

& $Godot --headless --path $project "res://tests/qa_regression.tscn"
exit $LASTEXITCODE
