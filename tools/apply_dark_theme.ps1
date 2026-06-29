$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$map = @(
    # ---- Hex strings used in GDScript ----
    @('"#F4EFE6"','"#14181E"'),  # bg top cream -> deep slate
    @('"#EAF1F2"','"#181F26"'),  # bg bottom pale -> slate
    @('"#F9F5EE"','"#222831"'),  # panel cream
    @('"#F9F2E8"','"#222831"'),
    @('"#D8CDBF"','"#3A4250"'),  # border tan
    @('"#ECE4D8"','"#1F242C"'),  # cell empty
    @('"#F7F2EA"','"#2D3340"'),  # dot fill
    @('"#344047"','"#E8EEF2"'),  # dot text
    @('"#EFE7DB"','"#2A3140"'),  # locked box bg
    @('"#C9B9A2"','"#4A5260"'),  # border
    @('"#28343B"','"#E8EEF2"'),  # body text
    @('"#6B6258"','"#7A8290"'),  # disabled text
    @('"#DED3C3"','"#2C323D"'),  # bar bg
    @('"#F7E6DF"','"#2E2A33"'),  # toast bg
    @('"#654A44"','"#F0DAD3"'),  # toast text
    @('"#2A3438"','"#E8EEF2"'),  # card title
    @('"#7A6A52"','"#A89B83"'),  # subtitle
    @('"#9A8B72"','"#B0A38A"'),  # muted
    @('"#8A9499"','"#9AA5B0"'),  # caption
    @('"#F2EADF"','"#2A3140"'),  # secondary button bg
    @('"#CAB9A4"','"#4A5260"'),
    @('"#3A4044"','"#E8EEF2"'),  # button text
    @('"#F4EEE4"','"#222831"'),
    @('"#D8E6E3"','"#243339"'),  # completed level bg
    @('"#E5DBCD"','"#2A3140"'),
    @('"#8A7C6C"','"#7A8290"'),
    @('"#D7C9B8"','"#3A4150"'),
    @('"#BCA98F"','"#5A6270"'),
    @('"#F7E6DF"','"#2E2A33"'),

    # ---- Color() tuples used in scripts AND scenes ----
    # cream panel #F9F2E8 with various alphas
    @('Color(0.976471, 0.94902, 0.909804, 0.94)', 'Color(0.137, 0.157, 0.188, 0.94)'),
    @('Color(0.976471, 0.94902, 0.909804, 0.98)', 'Color(0.137, 0.157, 0.188, 0.98)'),
    @('Color(0.976471, 0.94902, 0.909804, 0.85)', 'Color(0.137, 0.157, 0.188, 0.92)'),
    # cream button #ECE2D5
    @('Color(0.92549, 0.890196, 0.835294, 1)', 'Color(0.184, 0.208, 0.251, 1)'),
    @('Color(0.92549, 0.890196, 0.835294, 0.95)', 'Color(0.184, 0.208, 0.251, 0.95)'),
    # tan border #CABAA5
    @('Color(0.792157, 0.729412, 0.647059, 1)', 'Color(0.290, 0.322, 0.376, 1)'),
    @('Color(0.792157, 0.729412, 0.647059, 0.75)', 'Color(0.290, 0.322, 0.376, 0.85)'),
    # dark text #28343B -> light text
    @('Color(0.156863, 0.203922, 0.231373, 1)', 'Color(0.910, 0.933, 0.949, 1)'),
    @('Color(0.156863, 0.203922, 0.231373, 0.45)', 'Color(0.910, 0.933, 0.949, 0.65)'),
    # amber-brown #8A6942 -> brighter amber on dark
    @('Color(0.541176, 0.411765, 0.258824, 1)', 'Color(0.831, 0.631, 0.373, 1)'),
    # tan #DBD0C0
    @('Color(0.858824, 0.815686, 0.752941, 1)', 'Color(0.196, 0.224, 0.275, 1)'),
    # tan #E3D8C8
    @('Color(0.890196, 0.847059, 0.784314, 1)', 'Color(0.227, 0.255, 0.302, 1)'),
    # tan #B09D85
    @('Color(0.690196, 0.615686, 0.517647, 1)', 'Color(0.380, 0.420, 0.486, 1)'),
    # muted blue-gray #5F6F73 -> lighter muted on dark
    @('Color(0.372549, 0.435294, 0.45098, 1)', 'Color(0.604, 0.647, 0.706, 1)'),
    # rust #9A665E -> brighter
    @('Color(0.603922, 0.4, 0.368627, 1)', 'Color(0.91, 0.57, 0.55, 1)'),
    # font shadow white -> dark
    @('Color(1, 1, 1, 0.7)', 'Color(0, 0, 0, 0.45)'),
    @('Color(1, 1, 1, 0.65)', 'Color(0, 0, 0, 0.45)'),
    # brown shadow -> black shadow
    @('Color(0.32, 0.25, 0.18, 0.22)', 'Color(0, 0, 0, 0.45)'),
    @('Color(0.32, 0.25, 0.18, 0.12)', 'Color(0, 0, 0, 0.35)'),
    # dim overlay (slightly stronger on dark)
    @('Color(0.18, 0.14, 0.10, 0.32)', 'Color(0, 0, 0, 0.55)'),
    # backdrop grain on light -> tuned for dark
    @('Color(0.55, 0.48, 0.38, 0.045)', 'Color(0.85, 0.78, 0.65, 0.05)'),
    @('Color(0.18, 0.42, 0.45, 0.035)', 'Color(0.45, 0.65, 0.75, 0.04)'),
    @('Color(0.45, 0.38, 0.30, 0.035)', 'Color(0.75, 0.68, 0.55, 0.035)'),
    @('Color(0.20, 0.45, 0.48, 0.03)', 'Color(0.40, 0.65, 0.70, 0.03)'),
    # particle warm yellow stays
    # transition rect already dark; leave
    # daily card dim
    @('Color(0.05, 0.06, 0.08, 0.0)', 'Color(0, 0, 0, 0.0)')
)

$targets = Get-ChildItem -Path $root -Recurse -Include *.gd,*.tscn -File |
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
