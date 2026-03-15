# Объединенный скрипт для конвертации .webm в .mp4 и .mp3
param(
    [Parameter(Mandatory = $false)]
    [switch]$rewrite,
    [Parameter(Mandatory = $false)]
    [switch]$skipMp3
)

# Корневая папка проекта
$rootPath = $PSScriptRoot

# Вызываем скрипт для переименования файлов по дате
$fixFileNameDateScript = Join-Path $rootPath "fixfilenamedate.ps1"
if (Test-Path $fixFileNameDateScript) {
    Write-Host "Запускаю переименование файлов по дате..." -ForegroundColor Cyan
    & $fixFileNameDateScript
}
else {
    Write-Host "Скрипт fixfilenamedate.ps1 не найден, пропускаем переименование." -ForegroundColor Yellow
}

# Проверяем, установлен ли ffmpeg
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
    Write-Host "FFmpeg не найден. Убедитесь, что FFmpeg установлен и доступен в PATH." -ForegroundColor Red
    exit 1
}

# Создаем папку del, если её нет
$delFolder = Join-Path $rootPath "del"
if (-not (Test-Path $delFolder)) {
    New-Item -ItemType Directory -Path $delFolder | Out-Null
    Write-Host "Создана папка: $delFolder" -ForegroundColor Green
}

# Создаем папку out, если её нет
$outFolder = Join-Path $rootPath "out"
if (-not (Test-Path $outFolder)) {
    New-Item -ItemType Directory -Path $outFolder | Out-Null
    Write-Host "Создана папка: $outFolder" -ForegroundColor Green
}

# Получаем все файлы .webm в корневой папке
$files = Get-ChildItem -Path $rootPath -File -Filter *.webm

if ($files.Count -eq 0) {
    Write-Host "Файлы с расширением .webm не найдены в корневой папке." -ForegroundColor Yellow
    exit
}

foreach ($file in $files) {
    # Определяем имя выходного файла для MP4 в папке out
    $outputMp4File = Join-Path $outFolder ([System.IO.Path]::ChangeExtension($file.Name, ".mp4"))

    # Определяем имя выходного файла для MP3 в папке out
    $outputMp3File = Join-Path $outFolder ([System.IO.Path]::ChangeExtension($file.Name, ".mp3"))
    
    $skipMp4Conversion = $false
    $skipMp3Conversion = $false
    $mp3Created = $false
    
    # Проверяем, существует ли уже выходной файл MP4
    if ((Test-Path $outputMp4File) -and (-not $rewrite)) {
        Write-Host "Файл $outputMp4File уже существует. Пропускаем конвертацию в MP4: $($file.Name)" -ForegroundColor Yellow
        $skipMp4Conversion = $true
    }
    
    # Проверяем, нужно ли пропустить конвертацию в MP3 (параметр skipMp3 или файл уже существует)
    if ($skipMp3) {
        $skipMp3Conversion = $true
    }
    elseif ((Test-Path $outputMp3File) -and (-not $rewrite)) {
        Write-Host "Файл $outputMp3File уже существует. Пропускаем конвертацию в MP3: $($file.Name)" -ForegroundColor Yellow
        $skipMp3Conversion = $true
    }
    
    # Если оба файла существуют и rewrite не включен, пропускаем файл полностью
    if ($skipMp4Conversion -and $skipMp3Conversion) {
        continue
    }
    
    # Этап 1: Конвертация в MP4
    if (-not $skipMp4Conversion) {
        Write-Host "Конвертирую в MP4: $($file.Name) -> $([System.IO.Path]::GetFileName($outputMp4File))" -ForegroundColor Cyan
        
        try {
            # Формируем аргументы как строку для правильной обработки путей с пробелами
            $arguments = "-i `"$($file.FullName)`" -c:v libx265 -preset slow -crf 26 -c:a aac -b:a 96k `"$outputMp4File`""
            $process = Start-Process -FilePath "ffmpeg" -ArgumentList $arguments -Wait -NoNewWindow -PassThru

            # Проверяем код возврата процесса
            if ($process.ExitCode -ne 0) {
                Write-Host "Ошибка при конвертации в MP4: $($file.Name)" -ForegroundColor Red
                continue
            }

            Write-Host "Конвертация в MP4 завершена успешно: $($file.Name)" -ForegroundColor Green
        }
        catch {
            Write-Host "Ошибка при конвертации в MP4: $_" -ForegroundColor Red
            continue
        }
    }
    
    # Этап 2: Конвертация исходного файла в MP3 (если не пропущено)
    if (-not $skipMp3Conversion) {
        Write-Host "Конвертирую в MP3: $($file.Name) -> $([System.IO.Path]::GetFileName($outputMp3File))" -ForegroundColor Cyan
        
        try {
            # Формируем аргументы как строку для правильной обработки путей с пробелами
            $arguments = "-i `"$($file.FullName)`" -af silenceremove=start_periods=1:start_duration=0:start_threshold=-25dB:stop_periods=-1:stop_duration=1:stop_threshold=-25dB:detection=peak -ac 1 -ar 44100 -c:a libmp3lame -b:a 80k -q:a 4 -map a `"$outputMp3File`""
            $process = Start-Process -FilePath "ffmpeg" -ArgumentList $arguments -Wait -NoNewWindow -PassThru
            
            # Проверяем код возврата процесса (стандартный способ проверки успешности)
            if ($process.ExitCode -ne 0) {
                Write-Host "Ошибка при конвертации в MP3: $($file.Name)" -ForegroundColor Red
            }
            else {
                Write-Host "Конвертация в MP3 завершена успешно с удалением тишины: $([System.IO.Path]::GetFileName($outputMp3File))" -ForegroundColor Green
                $mp3Created = $true
            }
        }
        catch {
            # Перехватываем исключения при запуске процесса (файл заблокирован, недостаточно памяти и т.д.)
            Write-Host "Ошибка при конвертации в MP3: $_" -ForegroundColor Red
        }
    }
    
    # Перемещаем оригинальный файл в папку del если создан требуемый выходной файл
    # Если skipMp3 - перемещаем при успешном MP4, иначе при успешном MP3
    $shouldMove = $false
    
    if ($skipMp3) {
        # Если MP3 пропущен, перемещаем только если MP4 успешно создан в этом запуске
        $shouldMove = (-not $skipMp4Conversion)
    }
    else {
        # Если MP3 требуется, перемещаем если MP3 успешно создан в этом запуске
        $shouldMove = $mp3Created
    }
    
    if ($shouldMove) {
        Move-Item -Path $file.FullName -Destination $delFolder -ErrorAction SilentlyContinue
        Write-Host "Оригинальный файл перемещен в папку del: $($file.Name)" -ForegroundColor Green
    }
}

Write-Host "Обработка завершена." -ForegroundColor Green
