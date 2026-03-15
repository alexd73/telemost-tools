# Объединенный скрипт для конвертации .webm в .mp4 и .mp3
param(
    [Parameter(Mandatory = $false)]
    [switch]$rewrite,
    [Parameter(Mandatory = $false)]
    [switch]$skipMp3,
    [Parameter(Mandatory = $false)]
    [switch]$skipRename
)

# ============================================
# Конфигурация
# ============================================
$Configuration = @{
    RootPath      = $PSScriptRoot
    OutFolder     = 'out'
    DelFolder     = 'del'
    SkipMp3       = $skipMp3
    Rewrite       = $rewrite
    Interactive   = $true
    SkipRename    = $skipRename
    FfmpegCommand = 'ffmpeg'
}

# ============================================
# Логгер
# ============================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    $colors = @{
        Info    = 'White'
        Success = 'Green'
        Warning = 'Yellow'
        Error   = 'Red'
    }
    Write-Host $Message -ForegroundColor $colors[$Level]
}

# ============================================
# Проверка зависимостей
# ============================================
function Test-FfmpegInstalled {
    param([string]$Command = 'ffmpeg')
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# ============================================
# Управление папками
# ============================================
function New-ItemIfNotExists {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
        Write-Log "Создана папка: $Path" -Level Success
    }
}

# ============================================
# Конвертер
# ============================================
function Invoke-FfmpegConvert {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [string]$Arguments,
        [string]$FormatName
    )

    Write-Log "Конвертирую в $FormatName`: $(Split-Path $InputFile -Leaf) -> $(Split-Path $OutputFile -Leaf)" -Level Info

    try {
        $process = Start-Process -FilePath $Configuration.FfmpegCommand `
            -ArgumentList $Arguments `
            -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -ne 0) {
            Write-Log "Ошибка при конвертации в $FormatName" -Level Error
            return $false
        }

        Write-Log "Конвертация в $FormatName завершена успешно" -Level Success
        return $true
    }
    catch {
        Write-Log "Ошибка при конвертации в $FormatName`: $_" -Level Error
        return $false
    }
}

# ============================================
# Получение аргументов для конвертации
# ============================================
function Get-Mp4Arguments {
    param([string]$InputFile, [string]$OutputFile)
    return "-i `"$InputFile`" -c:v libx265 -preset slow -crf 26 -c:a aac -b:a 96k `"$OutputFile`""
}

function Get-Mp3Arguments {
    param([string]$InputFile, [string]$OutputFile)
    return "-i `"$InputFile`" -af silenceremove=start_periods=1:start_duration=0:start_threshold=-25dB:stop_periods=-1:stop_duration=1:stop_threshold=-25dB:detection=peak -ac 1 -ar 44100 -c:a libmp3lame -b:a 80k -q:a 4 -map a `"$OutputFile`""
}

# ============================================
# Проверка необходимости конвертации
# ============================================
function Test-ShouldConvert {
    param(
        [string]$OutputFile,
        [bool]$Rewrite,
        [bool]$SkipConversion
    )

    if ($SkipConversion) { return $false }
    if ($Rewrite) { return $true }
    if (Test-Path $OutputFile) {
        Write-Log "Файл $(Split-Path $OutputFile -Leaf) уже существует. Пропускаем." -Level Warning
        return $false
    }
    return $true
}

# ============================================
# Перемещение файлов
# ============================================
function Move-OriginalToDel {
    param(
        [string]$SourceFile,
        [string]$DestFolder
    )
    Move-Item -Path $SourceFile -Destination $DestFolder -ErrorAction SilentlyContinue
    Write-Log "Оригинальный файл перемещен: $(Split-Path $SourceFile -Leaf)" -Level Success
}

# ============================================
# Основная логика
# ============================================
function Start-Conversion {
    # Проверка зависимостей
    if (-not (Test-FfmpegInstalled -Command $Configuration.FfmpegCommand)) {
        Write-Log "FFmpeg не найден. Убедитесь, что установлен и доступен в PATH." -Level Error
        exit 1
    }
    
    # Создание папок
    $outPath = Join-Path $Configuration.RootPath $Configuration.OutFolder
    $delPath = Join-Path $Configuration.RootPath $Configuration.DelFolder
    New-ItemIfNotExists -Path $outPath
    New-ItemIfNotExists -Path $delPath
    
    # Запуск переименования
    if (-not $Configuration.SkipRename) {
        $fixScript = Join-Path $Configuration.RootPath "fixfilenamedate.ps1"
        if (Test-Path $fixScript) {
            Write-Log "Запускаю переименование файлов по дате..." -Level Info
            & $fixScript -interactive
        }
    }
    else {
        Write-Log "Переименование файлов пропущено." -Level Info
    }
    
    # Получение файлов
    $files = Get-ChildItem -Path $Configuration.RootPath -File -Filter *.webm
    if ($files.Count -eq 0) {
        Write-Log "Файлы .webm не найдены." -Level Warning
        exit
    }
    
    # Обработка каждого файла
    foreach ($file in $files) {
        $mp4File = Join-Path $outPath ([System.IO.Path]::ChangeExtension($file.Name, ".mp4"))
        $mp3File = Join-Path $outPath ([System.IO.Path]::ChangeExtension($file.Name, ".mp3"))
        
        $convertMp4 = Test-ShouldConvert -OutputFile $mp4File -Rewrite $Configuration.Rewrite -SkipConversion $false
        $convertMp3 = Test-ShouldConvert -OutputFile $mp3File -Rewrite $Configuration.Rewrite -SkipConversion $Configuration.SkipMp3
        
        if (-not $convertMp4 -and -not $convertMp3) { continue }
        
        $mp4Success = $true
        $mp3Success = $true
        
        # Конвертация в MP4
        if ($convertMp4) {
            $mp4Args = Get-Mp4Arguments -InputFile $file.FullName -OutputFile $mp4File
            $mp4Success = Invoke-FfmpegConvert -InputFile $file.FullName -OutputFile $mp4File -Arguments $mp4Args -FormatName 'MP4'
        }
        
        # Конвертация в MP3
        if ($convertMp3) {
            $mp3Args = Get-Mp3Arguments -InputFile $file.FullName -OutputFile $mp3File
            $mp3Success = Invoke-FfmpegConvert -InputFile $file.FullName -OutputFile $mp3File -Arguments $mp3Args -FormatName 'MP3'
        }
        
        # Перемещение оригинала
        $shouldMove = if ($Configuration.SkipMp3) { $convertMp4 -and $mp4Success } else { $convertMp3 -and $mp3Success }
        if ($shouldMove) {
            Move-OriginalToDel -SourceFile $file.FullName -DestFolder $delPath
        }
    }
    
    Write-Log "Обработка завершена." -Level Success
}

# Запуск
Start-Conversion
