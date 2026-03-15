# Скрипт для переименования записей яндекс телемост по дате из имени файла
param(
    [Parameter(Mandatory = $false)]
    [string]$folderPath = ".",
    [Parameter(Mandatory = $false)]
    [switch]$rewrite,
    [Parameter(Mandatory = $false)]
    [switch]$interactive
)

# ============================================
# Конфигурация
# ============================================
$Configuration = @{
    FolderPath  = $folderPath
    Rewrite     = $rewrite
    Interactive = $interactive
}

# ============================================
# Логирование
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
# Проверка пути
# ============================================
function Test-FolderPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Log "Папка не найдена: $Path" -Level Error
        return $false
    }
    return $true
}

# ============================================
# Получение файлов
# ============================================
function Get-FilesFromFolder {
    param([string]$Path)
    return Get-ChildItem -Path $Path -File
}

# ============================================
# Извлечение даты из имени файла
# ============================================
function Get-DateFromFileName {
    param([string]$FileName)
    
    # Поиск даты и времени в формате: DD.MM.YY HH-MM-SS
    if ($FileName -match '(\d{2})\.(\d{2})\.(\d{2})\s+(\d{2})-(\d{2})-(\d{2})') {
        return @{
            Day     = $matches[1]
            Month   = $matches[2]
            Year    = $matches[3]
            Hour    = $matches[4]
            Minute  = $matches[5]
            Second  = $matches[6]
            IsMatch = $true
        }
    }
    
    return @{ IsMatch = $false }
}

# ============================================
# Проверка корректности даты
# ============================================
function Test-ValidDate {
    param(
        [int]$Year,
        [int]$Month,
        [int]$Day,
        [int]$Hour,
        [int]$Minute,
        [int]$Second
    )
    
    try {
        $null = Get-Date -Year $Year -Month $Month -Day $Day `
            -Hour $Hour -Minute $Minute -Second $Second -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# ============================================
# Форматирование новой даты
# ============================================
function Format-NewDateTime {
    param(
        [int]$Year,
        [int]$Month,
        [int]$Day,
        [int]$Hour,
        [int]$Minute,
        [int]$Second
    )
    
    $fullYear = $Year + 2000
    $datePart = "{0:D4}{1:D2}{2:D2}" -f $fullYear, $Month, $Day
    $timePart = "{0:D2}{1:D2}{2:D2}" -f $Hour, $Minute, $Second
    
    return @{
        Date = $datePart
        Time = $timePart
    }
}

# ============================================
# Очистка имени файла от даты
# ============================================
function Remove-DateFromFileName {
    param(
        [string]$FileName,
        [string]$CustomName = ""
    )

    # Если передано пользовательское описание, используем его
    if (-not [string]::IsNullOrWhiteSpace($CustomName)) {
        return $CustomName.Trim()
    }

    # Удаление даты и времени из имени
    $nameWithoutDate = $FileName -replace '\d{2}\.\d{2}\.\d{2}\s+\d{2}-\d{2}-\d{2}', ''
    $nameWithoutDate = $nameWithoutDate.Trim()

    # Удаление лишних символов с начала и конца
    $nameWithoutDate = $nameWithoutDate.TrimStart(' ', '-', '.')
    $nameWithoutDate = $nameWithoutDate.TrimEnd(' ', '-', '.')

    # Удаление расширения, если оно осталось в имени
    $extension = [System.IO.Path]::GetExtension($FileName)
    if (-not [string]::IsNullOrEmpty($extension) -and $nameWithoutDate.ToLower().EndsWith($extension.ToLower())) {
        $nameWithoutDate = $nameWithoutDate.Substring(0, $nameWithoutDate.Length - $extension.Length)
        $nameWithoutDate = $nameWithoutDate.Trim()
        $nameWithoutDate = $nameWithoutDate.TrimStart(' ', '-', '.')
        $nameWithoutDate = $nameWithoutDate.TrimEnd(' ', '-', '.')
    }

    # Если имя пустое, используем значение по умолчанию
    if ([string]::IsNullOrWhiteSpace($nameWithoutDate)) {
        $nameWithoutDate = "file"
    }

    return $nameWithoutDate
}

# ============================================
# Создание нового имени файла
# ============================================
function Build-NewFileName {
    param(
        [string]$Date,
        [string]$Time,
        [string]$Name,
        [string]$Extension
    )
    return "{0}_{1} {2}{3}" -f $Date, $Time, $Name, $Extension
}

# ============================================
# Переименование файла
# ============================================
function Rename-FileItem {
    param(
        [string]$SourcePath,
        [string]$NewName
    )
    
    try {
        Rename-Item -Path $SourcePath -NewName $NewName -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Ошибка переименования: $_" -Level Error
        return $false
    }
}

# ============================================
# Обработка одного файла
# ============================================
function Invoke-FileRename {
    param(
        $File,
        [string]$FolderPath,
        [bool]$Rewrite,
        [bool]$Interactive,
        [ref]$Stats
    )

    # Извлечение даты из имени
    $dateInfo = Get-DateFromFileName -FileName $File.Name

    if (-not $dateInfo.IsMatch) {
        return
    }

    # Преобразование в числа
    $year = [int]$dateInfo.Year
    $month = [int]$dateInfo.Month
    $day = [int]$dateInfo.Day
    $hour = [int]$dateInfo.Hour
    $minute = [int]$dateInfo.Minute
    $second = [int]$dateInfo.Second

    # Проверка корректности даты
    if (-not (Test-ValidDate -Year $year -Month $month -Day $day `
                -Hour $hour -Minute $minute -Second $second)) {
        $timeStr = "${hour}:${minute}:${second}"
        Write-Log "Некорректная дата в файле: $($File.Name) (дата: $day.$month.$year $timeStr)" -Level Warning
        $Stats.Value.Errors++
        return
    }

    # Форматирование новой даты
    $formatted = Format-NewDateTime -Year $year -Month $month -Day $day `
        -Hour $hour -Minute $minute -Second $second

    # Запрос пользовательского описания в интерактивном режиме
    $customName = ""
    if ($Interactive) {
        $customName = Read-Host "Введите описание для файла '$($File.Name)' (Enter - без изменений)"
    }

    # Очистка имени от даты
    $nameWithoutDate = Remove-DateFromFileName -FileName $File.Name -CustomName $customName

    # Получение расширения
    $extension = $File.Extension

    # Создание нового имени
    $newName = Build-NewFileName -Date $formatted.Date -Time $formatted.Time `
        -Name $nameWithoutDate -Extension $extension

    $newPath = Join-Path -Path $FolderPath -ChildPath $newName

    # Проверка существования файла
    if ((Test-Path $newPath) -and (-not $Rewrite)) {
        Write-Log "Файл уже существует, пропускаем: $newName" -Level Warning
        $Stats.Value.Skipped++
        return
    }

    # Удаление существующего файла при режиме перезаписи
    if ((Test-Path $newPath) -and $Rewrite) {
        Remove-Item -Path $newPath -Force -ErrorAction SilentlyContinue
    }

    # Переименование
    if (Rename-FileItem -SourcePath $File.FullName -NewName $newName) {
        Write-Log "Переименовано: $($File.Name) -> $newName" -Level Success
        $Stats.Value.Renamed++
    }
    else {
        $Stats.Value.Errors++
    }
}

# ============================================
# Вывод статистики
# ============================================
function Write-Statistics {
    param($Stats)
    
    Write-Log "`nСтатистика:" -Level Info
    Write-Log "  Переименовано: $($Stats.Renamed)" -Level Success
    if ($Stats.Skipped -gt 0) {
        Write-Log "  Пропущено: $($Stats.Skipped)" -Level Warning
    }
    if ($Stats.Errors -gt 0) {
        Write-Log "  Ошибок: $($Stats.Errors)" -Level Error
    }
}

# ============================================
# Основная функция
# ============================================
function Start-FileRename {
    # Проверка пути
    if (-not (Test-FolderPath -Path $Configuration.FolderPath)) {
        exit 1
    }
    
    # Получение файлов
    $files = Get-FilesFromFolder -Path $Configuration.FolderPath
    
    if ($files.Count -eq 0) {
        Write-Log "Файлы не найдены в папке: $($Configuration.FolderPath)" -Level Warning
        exit 0
    }
    
    # Инициализация счётчиков
    $stats = @{
        Renamed = 0
        Skipped = 0
        Errors  = 0
    }
    
    # Обработка каждого файла
    foreach ($file in $files) {
        Invoke-FileRename -File $file `
            -FolderPath $Configuration.FolderPath `
            -Rewrite $Configuration.Rewrite `
            -Interactive $Configuration.Interactive `
            -Stats ([ref]$stats)
    }
    
    # Вывод статистики
    Write-Statistics -Stats $stats
}

# Запуск
Start-FileRename
