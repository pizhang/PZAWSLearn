 # Sample Code To Upload A Directory From Windows to S3 Bucket.
# With logging function, log file in the same directory of this script.
# With checking function, to avoid uploading files that are already uploaded.
# With folder structure kept during upload.

Clear-Host

#region Variables
$BucketName = "infra-testing-509399591785-ap-southeast-2"
$BucketPrefix = "TestPrefix/"
$LocalDirectory = "C:\Users\Administrator\Desktop\S3Source"
$OverwritePriority = "Local" # Local, S3, Manual
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

Get-ChildItem $LocalDirectory -File -Recurse | ForEach-Object {
    $LocalFile = $_.FullName
    $LocalFileLastModified = $_.LastWriteTimeUtc
    $LocalFileLastModifiedISO = $LocalFileLastModified.ToString("o")

    $LocalFileHash = (Get-FileHash $LocalFile -Algorithm MD5).Hash.ToLower()

    Write-Host "$LocalFile last modified at $LocalFileLastModifiedISO"

    # Replace back-lashes with forward-slashes
    $S3Key = $BucketPrefix + $LocalFile.Replace("\", "/")
    $S3Object = Get-S3Object -BucketName $BucketName -Key $S3Key -ErrorAction SilentlyContinue

    if ($S3Object) {
        LogWrite "$S3Key exists in bucket, skipping upload."
        Write-Host "$S3Key exists in bucket, skipping upload." -ForegroundColor Green 

        $S3ObjectMetadata = Get-S3ObjectMetadata -BucketName $BucketName -Key $S3Key -ErrorAction SilentlyContinue
        if ($S3ObjectMetadata.Metadata.Count -gt 0) {
            Write-Host "Metadata exists." -ForegroundColor Green
            $LastModifiedMeta= $S3ObjectMetadata["x-amz-meta-lastmodified"]
            Write-Host $LastModifiedMeta -ForegroundColor Yellow
        }
        $Etag = ($S3Object.ETag).Trim('"')

        if (-not $LastModifiedMeta) {
            if ($Etag -eq $LocalFileHash) {
                Write-Host "File unchanged (ETag matches). Adding MetaData." -ForegroundColor Yellow

                Copy-S3Object -BucketName $BucketName -Key $S3Key `
                    -DestinationKey $S3Key -MetadataDirective "REPLACE" `
                    -Metadata @{
                        "x-amz-meta-lastmodified" = $LocalFileLastModifiedISO
                    } `
                    -ErrorAction SilentlyContinue
            } else {
                Write-Host "File changed (ETag does not match)." -ForegroundColor Red
                if ($OverwritePriority -eq "Local") {
                    Write-Host "Overwrite Priority is local file, uploading." -ForegroundColor Yellow
                    Write-S3Object -BucketName $BucketName -Key $S3Key -File $LocalFile -CannedACLName private -Metadata @{
                        "x-amz-meta-lastmodified" = $LocalFileLastModifiedISO
                    }
                    LogWrite "$S3Key uploaded, with local file overwrite S3 object."
                } elseif ($OverwritePriority -eq "S3") {
                    Write-Host "Overwrite Priority is not S3, skipping." -ForegroundColor Yellow
                } else {
                    Write-Host "Overwrite Priority is Manual, please check." -ForegroundColor Yellow           
                }
            }
        } else {
            # Compare local file last modified time with S3 metadata last modified time
            if ($LocalFileLastModifiedISO -gt $LastModifiedMeta) {
                Write-Host "Local file is newer than S3 metadata, uploading." -ForegroundColor Yellow
                Write-S3Object -BucketName $BucketName -Key $S3Key -File $LocalFile -CannedACLName private -Metadata @{
                    "x-amz-meta-lastmodified" = $LocalFileLastModifiedISO
                }
                LogWrite "$S3Key uploaded, with local file overwrite S3 object."
                Write-Host "Local file is newer than S3 metadata, uploading." -ForegroundColor Green
            } else {
                Write-Host "Local file is not newer than S3 metadata, skipping upload." -ForegroundColor Green
            }
        }
    } else {
        Write-S3Object -BucketName $BucketName -Key $S3Key -File $LocalFile -CannedACLName private -Metadata @{
            "x-amz-meta-lastmodified" = $LocalFileLastModifiedISO
        }
        LogWrite "$S3Key uploaded."
    }
}

#endregion Upload Files

Write-Host "Directory $LocalDirectory Upload Completed." -ForegroundColor Green




 
