# PowerShell script to convert MP4 file to MP3
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,
    [Parameter(Mandatory = $false)]
    [switch]$rewrite = $false
)

# Check if input file exists
if (-not (Test-Path $InputFile)) {
    Write-Error "Input file does not exist: $InputFile"
    exit 1
}

# Validate that the input file has an MP4 extension
if ([System.IO.Path]::GetExtension($InputFile) -ne '.mp4') {
    Write-Error "Input file must be an MP4: $InputFile"
    exit 1
}

# Generate output file path by replacing extension
$outputFile = [System.IO.Path]::ChangeExtension($InputFile, '.mp3')

# Check if ffmpeg is available
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg is not installed or not in PATH"
    exit 1
}

# Execute ffmpeg command to convert MP4 to MP3 with silence removal
if ((Test-Path $outputFile) -and (-not $rewrite)) {
    Write-Host "Output file already exists: $outputFile. Skipping conversion."
}
else {
    try {
        $process = Start-Process -FilePath "ffmpeg" -ArgumentList "-i", "`"$InputFile`"", "-af", "silenceremove=stop_periods=-1:stop_duration=1:stop_threshold=-25dB:detection=peak", "-q:a", "2", "-map", "a", "`"$outputFile`"" -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host "Successfully converted: $InputFile to $outputFile with silence removal"
        }
        else {
            Write-Error "FFmpeg conversion failed with exit code: $($process.ExitCode)"
            exit 1
        }
    }
    catch {
        Write-Error "An error occurred during conversion: $_"
        exit 1
    }
}