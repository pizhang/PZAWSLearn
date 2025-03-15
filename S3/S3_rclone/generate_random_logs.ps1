# Set the folder path
$folderPath = "C:\Temp\Logs"

# Create directory if needed
[System.IO.Directory]::CreateDirectory($folderPath) | Out-Null

# Set total size (5GB as Int64)
$totalSize = [Int64]5 * 1024 * 1024 * 1024
$currentSize = [Int64]0
$start = [System.Diagnostics.Stopwatch]::StartNew()

# Configuration (using explicit numeric types)
$bufferSize = [Int32]64KB
$minFileSize = [Int32](10 * 1024)    # 10KB
$maxFileSize = [Int32](2 * 1024KB)   # 2MB

# Pre-generated text blocks
$charSet = [char[]](33..126)
$random = [System.Random]::new()
$textBlock = [System.Text.StringBuilder]::new()
1..$bufferSize | ForEach-Object { 
    [void]$textBlock.Append($charSet[$random.Next(0, $charSet.Length)])
}
$reusableBlock = $textBlock.ToString()

# Main loop with 64-bit math
while ($currentSize -lt $totalSize) {
    # Generate target size within remaining capacity
    $remaining = $totalSize - $currentSize
    $targetSize = [Math]::Min(
        [Int64]$random.Next($minFileSize, $maxFileSize + 1),
        [Int64]$remaining
    )

    # Generate filename with timestamp and GUID
    $fileName = "log_{0:yyyyMMdd_HHmmssfff}_{1}.log" -f [DateTime]::Now, [Guid]::NewGuid().ToString("N").Substring(0, 6)
    $filePath = [System.IO.Path]::Combine($folderPath, $fileName)

    # Generate content using buffer blocks
    $buffer = [System.Text.StringBuilder]::new()
    $bytesWritten = [Int64]0
    
    while ($bytesWritten -lt $targetSize) {
        $chunkSize = [Math]::Min([Int32]($targetSize - $bytesWritten), $reusableBlock.Length)
        [void]$buffer.Append($reusableBlock, 0, $chunkSize)
        $bytesWritten += $chunkSize
    }

    # Write to file
    [System.IO.File]::WriteAllText($filePath, $buffer.ToString(), [System.Text.Encoding]::ASCII)
    $currentSize += $bytesWritten

    # Progress every 100MB
    if ($currentSize % 100MB -eq 0) {
        Write-Progress -Activity "Generating" -Status "$([Math]::Round($currentSize/1GB, 2)) GB" -PercentComplete ($currentSize/$totalSize*100)
    }
}

Write-Host "Completed in $($start.Elapsed.ToString('hh\:mm\:ss')) - Final size: $([Math]::Round($currentSize/1GB, 2)) GB"