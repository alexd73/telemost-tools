# Script to rename files by date from filename
param(
    [Parameter(Mandatory = $false)]
    [string]$folderPath = ".",
    [Parameter(Mandatory = $false)]
    [switch]$rewrite
)

# Check if folder exists
if (-not (Test-Path $folderPath)) {
    Write-Host "Folder not found: $folderPath" -ForegroundColor Red
    exit 1
}

# Get all files in folder
$files = Get-ChildItem -Path $folderPath -File

if ($files.Count -eq 0) {
    Write-Host "No files found in folder: $folderPath" -ForegroundColor Yellow
    exit 0
}

$renamedCount = 0
$skippedCount = 0
$errorCount = 0

foreach ($file in $files) {
    # Look for date and time in filename (format: DD.MM.YY HH-MM-SS)
    if ($file.Name -match '(\d{2})\.(\d{2})\.(\d{2})\s+(\d{2})-(\d{2})-(\d{2})') {
        $day = $matches[1]
        $month = $matches[2]
        $year = $matches[3]
        $hour = $matches[4]
        $minute = $matches[5]
        $second = $matches[6]
        
        # Validate date
        $fullYear = [int]$year + 2000
        try {
            $null = Get-Date -Year $fullYear -Month ([int]$month) -Day ([int]$day) -Hour ([int]$hour) -Minute ([int]$minute) -Second ([int]$second) -ErrorAction Stop
        }
        catch {
            $timeStr = "${hour}:${minute}:${second}"
            Write-Host "Invalid date in file: $($file.Name) (date: $day.$month.$year $timeStr)" -ForegroundColor Yellow
            $errorCount++
            continue
        }
        
        # Format new date and time as YYYYMMDD_HHMMSS
        $newDate = "{0:D4}{1:D2}{2:D2}" -f $fullYear, [int]$month, [int]$day
        $newTime = "{0:D2}{1:D2}{2:D2}" -f [int]$hour, [int]$minute, [int]$second
        
        # Remove date and time from original filename
        $nameWithoutDate = $file.Name -replace '\d{2}\.\d{2}\.\d{2}\s+\d{2}-\d{2}-\d{2}', ''
        $nameWithoutDate = $nameWithoutDate.Trim()
        
        # Remove extra spaces, dashes and dots from start and end
        $nameWithoutDate = $nameWithoutDate.TrimStart(' ', '-', '.')
        $nameWithoutDate = $nameWithoutDate.TrimEnd(' ', '-', '.')
        
        # Get file extension
        $extension = $file.Extension
        
        # If extension remains in nameWithoutDate, remove it
        if ($nameWithoutDate.ToLower().EndsWith($extension.ToLower())) {
            $nameWithoutDate = $nameWithoutDate.Substring(0, $nameWithoutDate.Length - $extension.Length)
            $nameWithoutDate = $nameWithoutDate.Trim()
            $nameWithoutDate = $nameWithoutDate.TrimStart(' ', '-', '.')
            $nameWithoutDate = $nameWithoutDate.TrimEnd(' ', '-', '.')
        }
        
        # If filename is empty after removing date, use "file"
        if ([string]::IsNullOrWhiteSpace($nameWithoutDate)) {
            $nameWithoutDate = "file"
        }
        
        # Build new name: YYYYMMDD_HHMMSS name.extension
        $newName = "{0}_{1} {2}{3}" -f $newDate, $newTime, $nameWithoutDate, $extension
        
        # Check if file with this name already exists
        $newPath = Join-Path -Path $folderPath -ChildPath $newName
        if ((Test-Path $newPath) -and (-not $rewrite)) {
            Write-Host "File already exists, skipping: $newName" -ForegroundColor Yellow
            $skippedCount++
            continue
        }
        
        # If file exists and rewrite is enabled, remove old file
        if ((Test-Path $newPath) -and $rewrite) {
            Remove-Item -Path $newPath -Force -ErrorAction SilentlyContinue
        }
        
        # Rename file
        try {
            Rename-Item -Path $file.FullName -NewName $newName -ErrorAction Stop
            Write-Host "Renamed: $($file.Name) -> $newName" -ForegroundColor Green
            $renamedCount++
        }
        catch {
            Write-Host "Error renaming file: $($file.Name) -> $newName`nError: $_" -ForegroundColor Red
            $errorCount++
        }
    }
}

# Output statistics
Write-Host "`nStatistics:" -ForegroundColor Cyan
Write-Host "  Renamed: $renamedCount" -ForegroundColor Green
if ($skippedCount -gt 0) {
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
}
if ($errorCount -gt 0) {
    Write-Host "  Errors: $errorCount" -ForegroundColor Red
}
