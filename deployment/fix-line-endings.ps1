# PowerShell script to convert CRLF to LF for bash compatibility
$scriptFiles = Get-ChildItem -Path "." -Filter "*.sh"

foreach ($file in $scriptFiles) {
    Write-Host "Converting line endings for: $($file.Name)"
    $content = Get-Content $file.FullName -Raw
    $content = $content -replace "`r`n", "`n"
    $content = $content -replace "`r", "`n"
    [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.Encoding]::UTF8)
}

Write-Host "Line ending conversion completed for all .sh files"