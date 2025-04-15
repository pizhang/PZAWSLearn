 # Sample Code To Upload A Directory From Windows to S3 Bucket.
# With logging function, log file in the same directory of this script.
# With checking function, to avoid uploading files that are already uploaded.
# With folder structure kept during upload.

Clear-Host

#region Variables
$BucketName = "infra-testing-509399591785-ap-southeast-2"
$BucketPrefix = "TestPrefix/"
$LocalDirectory = "C:\Users\Administrator\Desktop\S3Source\SubFolder1"
$CheckETag = $true
#endregion Variables

#region Logging
$LogFilePath = $PSScriptRoot + "\" + $MyInvocation.MyCommand.Name + ".log"
Function LogWrite($logString) {
    Add-content $LogFilePath -value $logString
}
#endregion Logging

function Sync-S3ObjectAdvanced {
    <#
    .SYNOPSIS
    Uploads a local file to S3 only if it has changed, using hybrid checks (hash, metadata, and multipart handling).
    
    .DESCRIPTION
    - Compares local file hash with S3 ETag (for non-multipart uploads).
    - Uses metadata-stored hash and last modified time for multipart uploads.
    - Updates metadata on upload for future comparisons.
    
    .PARAMETER LocalPath
    Path to the local file.
    
    .PARAMETER BucketName
    Name of the S3 bucket.
    
    .PARAMETER Key
    S3 object key/path.
    
    .EXAMPLE
    Sync-S3ObjectAdvanced -LocalPath "C:\data\report.pdf" -BucketName "my-bucket" -Key "reports/report.pdf"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,
        
        [Parameter(Mandatory)]
        [string]$BucketName,
        
        [Parameter(Mandatory)]
        [string]$Key
    )

    # Validate local file
    if (-not (Test-Path $LocalPath)) {
        throw "Local file '$LocalPath' not found."
    }

    # Calculate local file hash (MD5) and last modified time (UTC)
    $localFile = Get-Item $LocalPath
    $localHash = (Get-FileHash $LocalPath -Algorithm MD5).Hash.ToLower()
    $localLastModified = $localFile.LastWriteTimeUtc.ToString("o")  # ISO 8601

    # Check if S3 object exists
    $s3Object = Get-S3Object -BucketName $BucketName -Key $Key -ErrorAction SilentlyContinue
    $etag = $s3Object.ETag.Trim('"').ToLower() -replace("-","")  # Normalize for comparison
    $isMultipart = $s3Object.ETag -match "-\d+$"  # Detect multipart uploads (ETag format: "hash-partcount")

    # Retrieve metadata
    $metadataHash = $s3Object.Metadata["x-amz-meta-content-hash"]
    $metadataTime = $s3Object.Metadata["x-amz-meta-lastmodified"]

    # Decision logic
    $uploadNeeded = $false
    $warningMessage = ""

    if (-not $s3Object) {
        Write-Host "Object does not exist. Uploading..."
        $uploadNeeded = $true
    }
    else {
        # Case 1: Non-multipart upload (ETag = MD5)
        if (-not $isMultipart) {
            if ($etag -ne $localHash) {
                Write-Host "Hash mismatch (non-multipart). Uploading..."
                $uploadNeeded = $true
            }
            else {
                Write-Host "File unchanged (non-multipart). Skipping."
            }
        }
        # Case 2: Multipart upload (ETag ≠ MD5)
        else {
            $warningMessage = "WARNING: S3 object uses multipart upload (ETag unreliable). Using metadata checks."
            Write-Warning $warningMessage

            # Check metadata hash first
            if ($metadataHash -eq $localHash) {
                Write-Host "Metadata hash matches. Skipping."
            }
            else {
                # Fallback to last modified time
                if (-not $metadataTime) {
                    Write-Host "Metadata missing. Uploading to repair..."
                    $uploadNeeded = $true
                }
                else {
                    try {
                        $s3Time = [DateTime]::Parse($metadataTime, [CultureInfo]::InvariantCulture, [DateTimeStyles]::RoundtripKind)
                        if ($localFile.LastWriteTimeUtc -gt $s3Time) {
                            Write-Host "Local file is newer. Uploading..."
                            $uploadNeeded = $true
                        }
                        else {
                            Write-Host "Local file is older or unchanged. Skipping."
                        }
                    }
                    catch {
                        Write-Host "Invalid metadata timestamp. Uploading to fix..."
                        $uploadNeeded = $true
                    }
                }
            }
        }
    }

    # Upload if needed
    if ($uploadNeeded) {
        Write-S3Object -BucketName $BucketName -Key $Key -File $LocalPath -Metadata @{
            "x-amz-meta-content-hash" = $localHash
            "x-amz-meta-lastmodified" = $localLastModified
        }
        Write-Host "Uploaded. Metadata updated with hash and timestamp."
    }

    # Output warnings (if any)
    if ($warningMessage) {
        Write-Warning $warningMessage
    }
}

#region Function Test-S3Object
function Test-S3Object {
    <#
    .SYNOPSIS
    Checks if an object exists in an AWS S3 bucket.
    
    .DESCRIPTION
    Returns $true if the object exists, $false if it does not (or the bucket is missing).
    Throws exceptions for errors like insufficient permissions.
    
    .PARAMETER BucketName
    The name of the S3 bucket.
    
    .PARAMETER Key
    The key/path of the object in the bucket.
    
    .EXAMPLE
    Test-S3Object -BucketName "my-bucket" -Key "documents/report.pdf"
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$BucketName,
        
        [Parameter(Mandatory)]
        [string]$Key
    )

    try {
        # Attempt to retrieve the object metadata
        $object = Get-S3Object -BucketName $BucketName -Key $Key -ErrorAction Stop
        return [bool]$object  # Returns $true if object exists
    }
    catch [Amazon.S3.AmazonS3Exception] {
        # Handle cases where the bucket or object doesn't exist
        if ($_.Exception.ErrorCode -in 'NoSuchBucket', 'NoSuchKey') {
            return $false
        }
        # Re-throw for other S3 errors (e.g., access denied)
        throw $_
    }
    catch {
        # Propagate all other errors
        throw $_
    }
}
#endregion

#region Upload Files
if (1 -eq 1) {
    Get-ChildItem $LocalDirectory -File -Recurse | ForEach-Object {
        $LocalFile = $_.FullName
        $LocalFileLastModified = $_.LastWriteTimeUtc
        $LocalFileLastModifiedISO = $LocalFileLastModified.ToString("o")

        Write-Host "$LocalFile last modified at $LocalFileLastModifiedISO"

        # Replace back-lashes with forward-slashes
        $S3Key = $LocalFile.Replace("\", "/")
        Write-Host "S3 Key Round 1: $S3Key"

        if ($BucketPrefix) {
            $S3Key = $BucketPrefix + $S3Key
        }

        if (Test-S3Object -BucketName $BucketName -Key $S3Key) {
            LogWrite "$S3Key already exists."
        }
        else {
            Write-S3Object -BucketName $BucketName -Key $S3Key -File $LocalFile -CannedACLName private
            LogWrite "$S3Key uploaded."
        }
    }
}
#endregion Upload Files

Write-Host "Directory $LocalDirectory Upload Completed." -ForegroundColor Green




 
