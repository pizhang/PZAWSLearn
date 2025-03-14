# Set the folder path
$folderPath = "C:\Temp\Logs"

# Create directory if it doesn't exist
New-Item -ItemType Directory -Force -Path $folderPath | Out-Null

# Set total size (5GB)
$totalSize = 5GB
$currentSize = 0
$start = Get-Date

# Enhanced character set (A-Z, a-z, numbers, space, and basic punctuation)
$charSet = (33..126) # All printable ASCII characters

while ($currentSize -lt $totalSize) {
    # Generate random file size between 10KB and 2MB
    $logFileSize = Get-Random -Minimum (10*1024) -Maximum (2*1024*1024 + 1)
    
    # Generate filename with milliseconds
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmssfff"
    $logFileName = "log_$timestamp.log"
    $fullPath = Join-Path $folderPath $logFileName

    # Cap final file size
    if (($currentSize + $logFileSize) -gt $totalSize) {
        $logFileSize = $totalSize - $currentSize
    }

    # Generate random content WITH REPETITION using .NET Random
    $random = [System.Random]::new()
    $logFileContent = -join (
        1..$logFileSize | ForEach-Object {
            [char]$charSet[$random.Next(0, $charSet.Count)]
        }
    )

    # Write file with ASCII encoding
    [System.IO.File]::WriteAllText($fullPath, $logFileContent, [System.Text.Encoding]::ASCII)

    $currentSize += $logFileSize
    Write-Host "Generated: $logFileName ($($logFileSize/1KB) KB) - Total: $([math]::Round($currentSize/1GB, 3)) GB"
}

Write-Host "Total time taken: $((Get-Date) - $start)"