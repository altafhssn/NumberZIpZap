$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Map current dark palette -> reference repo palette (deep navy + blue/purple accents)
$map = @(
    # ---- Hex strings ----
    @('"#14181E"','"#0B0B16"'),    # bg top
    @('"#181F26"','"#13132A"'),    # bg bottom
    @('"#222831"','"#16162C"'),    # panel/grid bg
    @('"#3A4250"','"#2A2A4E"'),    # border
    @('"#1F242C"','"#1C1C38"'),    # cell empty
    @('"#2D3340"','"#000000"'),    # dot fill -> black
    @('"#E8EEF2"','"#FFFFFF"'),    # body text -> white
    @('"#9DB7D6"','"#4361EE"'),    # path start -> blue
    @('"#E8B4B8"','"#7B2D8B"'),    # path end -> purple
    @('"#D4A15F"','"#FFD166"'),    # hint amber
    @('"#C76B8E"','"#EF4444"'),    # error red
    @('"#2A3140"','"#0F0F22"'),    # locked box bg
    @('"#4A5260"','"#2A2A4E"'),    # mid border
    @('"#2C323D"','"#1A1A30"'),    # progress bar bg
    @('"#243339"','"#243A8A"'),    # completed level bg
    @('"#3A4150"','"#2A2A4E"'),
    @('"#5A6270"','"#4361EE"'),
    @('"#3E8E8A"','"#4361EE"'),    # was teal accent -> blue
    @('"#4B8F8A"','"#4361EE"'),    # primary button -> blue
    @('"#C77B4A"','"#FFD166"'),    # streak rust -> amber
    @('"#9A665E"','"#EF4444"'),    # rust -> red
    @('"#7A8290"','"#9EA8DB"'),    # disabled text -> muted blue
    @('"#A89B83"','"#9EA8DB"'),
    @('"#B0A38A"','"#9EA8DB"'),
    @('"#9AA5B0"','"#9EA8DB"'),
    @('"#F0DAD3"','"#FFFFFF"'),    # toast text
    @('"#2E2A33"','"#1C1C38"'),    # toast bg
    @('"#E0A368"','"#FFD166"'),    # leftover theme color
    @('"#88C9C4"','"#06D6A0"'),
    @('"#AEB9D6"','"#8B5CF6"'),
    @('"#5B8BB0"','"#EC4899"'),

    # ---- Color() tuples used in scenes ----
    @('Color(0.137, 0.157, 0.188, 0.94)', 'Color(0.086, 0.086, 0.173, 0.94)'),
    @('Color(0.137, 0.157, 0.188, 0.98)', 'Color(0.086, 0.086, 0.173, 0.98)'),
    @('Color(0.137, 0.157, 0.188, 0.95)', 'Color(0.086, 0.086, 0.173, 0.95)'),
    @('Color(0.137, 0.157, 0.188, 0.92)', 'Color(0.086, 0.086, 0.173, 0.92)'),
    @('Color(0.184, 0.208, 0.251, 1)',    'Color(0.110, 0.110, 0.220, 1)'),
    @('Color(0.184, 0.208, 0.251, 0.95)', 'Color(0.110, 0.110, 0.220, 0.95)'),
    @('Color(0.290, 0.322, 0.376, 1)',    'Color(0.165, 0.165, 0.306, 1)'),
    @('Color(0.290, 0.322, 0.376, 0.85)', 'Color(0.165, 0.165, 0.306, 0.85)'),
    @('Color(0.910, 0.933, 0.949, 1)',    'Color(1, 1, 1, 1)'),
    @('Color(0.910, 0.933, 0.949, 0.65)', 'Color(1, 1, 1, 0.65)'),
    @('Color(0.831, 0.631, 0.373, 1)',    'Color(1.0, 0.819, 0.4, 1)'),
    @('Color(0.604, 0.647, 0.706, 1)',    'Color(0.62, 0.66, 0.86, 1)'),
    @('Color(0.91, 0.57, 0.55, 1)',       'Color(0.937, 0.267, 0.267, 1)'),
    @('Color(0.196, 0.224, 0.275, 1)',    'Color(0.110, 0.110, 0.220, 1)'),
    @('Color(0.227, 0.255, 0.302, 1)',    'Color(0.165, 0.165, 0.306, 1)'),
    @('Color(0.380, 0.420, 0.486, 1)',    'Color(0.4, 0.42, 0.55, 1)'),

    # ---- engine clear color ----
    @('Color(0.078, 0.094, 0.118, 1)', 'Color(0.043, 0.043, 0.086, 1)'),

    # ---- Backdrop grain -> accent dots (faint) ----
    @('Color(0.85, 0.78, 0.65, 0.05)',   'Color(0.263, 0.380, 0.933, 0.10)'),
    @('Color(0.45, 0.65, 0.75, 0.04)',   'Color(0.482, 0.176, 0.545, 0.10)'),
    @('Color(0.75, 0.68, 0.55, 0.035)',  'Color(0.263, 0.380, 0.933, 0.06)'),
    @('Color(0.40, 0.65, 0.70, 0.03)',   'Color(0.482, 0.176, 0.545, 0.05)'),

    # ---- HUD text colors (currently same as ref) ----
    # Color(0.55, 0.58, 0.78, 1) already matches reference normal-state fill label.
    # Color(1, 0.82, 0.4, 1) and Color(0.94, 0.27, 0.27, 1) already match.
    # Color(1, 0.82, 0.4, 1) particle, leave.
    # left as-is.

    # ---- HUD hex font colors set from previous pass ----
    @('"#5F6F73"','"#9EA8DB"'),
    @('"#8A6942"','"#FFD166"')
)

$targets = Get-ChildItem -Path $root -Recurse -Include *.gd,*.tscn,*.godot -File |
    Where-Object { $_.FullName -notmatch '\\tools\\' }

foreach ($file in $targets) {
    $orig = [System.IO.File]::ReadAllText($file.FullName)
    $txt = $orig
    foreach ($pair in $map) {
        $txt = $txt.Replace($pair[0], $pair[1])
    }
    if ($txt -ne $orig) {
        [System.IO.File]::WriteAllText($file.FullName, $txt)
        Write-Output ("updated: " + $file.FullName.Substring($root.Length + 1))
    }
}
Write-Output "done."
