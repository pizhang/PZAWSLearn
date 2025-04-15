# Sample Code To Upload A Directory From Windows to S3 Bucket.
# With logging function, log file in the same directory of this script.
# With checking function, to avoid uploading files that are already uploaded.
# With folder structure kept same during upload.
# Provide a choice to use form to collect information.

Clear-Host

#region Variables with default values
$BucketName = "infra-testing-509399591785-ap-southeast-2"
$BucketPrefix = "TestPrefix/"
$LocalPath = "C:\Users\Administrator\Desktop\S3Source" # Windows folder path
$OverwritePriority = "Local" # Local, S3, Manual
#endregion Variables

#region Logging Preparation
$LogFilePath = $PSScriptRoot + "\" + $MyInvocation.MyCommand.Name + ".log"
if (Test-Path $LogFilePath) {
    # Remove-Item $LogFilePath
} else {
    New-Item $LogFilePath -ItemType File | Out-Null
}
Function LogWrite($logString) {
    $logTimestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss").ToU
    Add-content $LogFilePath -value "$logTimestamp $logString"
}
#endregion Logging

#region Function Get-S3ObjectIfExists
function Get-S3ObjectIfExists {
    <#
    .SYNOPSIS
    Checks if an object exists in an AWS S3 bucket, and returns it if found.
    
    .DESCRIPTION
    Returns the S3 object if the object exists, $null if it does not (or the bucket is missing).
    Throws exceptions for errors like insufficient permissions.
    
    .PARAMETER BucketName
    The name of the S3 bucket.
    
    .PARAMETER Key
    The key/path of the object in the bucket.
    
    .EXAMPLE
    Get-S3Object -BucketName "my-bucket" -Key "documents/report.pdf"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BucketName,
        
        [Parameter(Mandatory)]
        [string]$Key
    )

    try {
        # Attempt to retrieve the object metadata
        $object = Get-S3Object -BucketName $BucketName -Key $Key -ErrorAction Stop
        return $object  # Returns the object if object exists
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

#region Function IsMultipartETag
function IsMultipartETag($ETag) {
    $ETag -match "-\d+$"
}
#endregion

#region Function Upload_S3
Function Upload-S3($LocalPath, $BucketName, $Key, $ISOTimeString) {
    Write-Host "Uploading $LocalPath to $BucketName/$Key"
    LogWrite "Uploading $LocalPath to $BucketName/$Key"
    Write-S3Object -BucketName $BucketName -Key $Key -File $LocalPath -CannedACLName private -Metadata @{
        "x-amz-meta-lastmodified" = $ISOTimeString
    }
    Write-Host "Uploaded $LocalPath to $BucketName/$Key"
    LogWrite "Uploaded $LocalPath to $BucketName/$Key"
}
#endregion

#region Function Update-S3Timestamp
Function Update-S3Timestamp($BucketName, $Key, $ISOTimeString) {
    Write-Host "Updating metadata timestamp of $BucketName/$Key"
    LogWrite "Updating metadata timestamp of $BucketName/$Key"
    Copy-S3Object -BucketName $BucketName -Key $Key -DestinationKey $Key -MetadataDirective "REPLACE" -Metadata @{
        "x-amz-meta-lastmodified" = $ISOTimeString
    }
    Write-Host "Updated metadata timestamp of $BucketName/$Key"
    LogWrite "Updated metadata timestamp of $BucketName/$Key"
}
#endregion

#region Upload Files

#region Prompt user for confirmation to create test structure
$confirmation = Read-Host "Do you want to create test subfolders on your desktop? (Y or else to skip)"
if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
    $testFolder = [Environment]::GetFolderPath("Desktop") + "\S3Source\TestSubFolder1\TestSubFolder2"
    if (-not (Test-Path $testFolder)) {
        New-Item -ItemType Directory -Path $testFolder | Out-Null
        Write-Host "Test subfolders created on your desktop."
        LogWrite "Test subfolders created on your desktop."
    } else {
        Write-Host "Test subfolders already exist on your desktop."
        LogWrite "Test subfolders already exist on your desktop."
    }
    # Create test text files in each subfolder, add a few random words in each file
    $testFile1 = $testFolder + "\test1.txt"
    $testFile2 = $testFolder + "\test2.txt"
    $testFile3 = $testFolder + "\test3.txt"
    $testFile4 = $testFolder + "\test4.txt"

    Add-Content -Path $testFile1  -Value "Hello World"
    Add-Content -Path $testFile2  -Value "Hello World"
    Add-Content -Path $testFile3  -Value "Hello World"
    Add-Content -Path $testFile4  -Value "Hello World"
} else {
    Write-Host "Test subfolders creation skipped."
    LogWrite "Test subfolders creation skipped."
}
#endregion

# Check if the folder path provided exists
if (-not (Test-Path $LocalPath)) {
    Write-Host "The folder path '$LocalPath' does not exist." -ForegroundColor Red
    exit
} else {
    $localDirectory = Get-Item $LocalPath
}

# Loop through the folder recursively to upload to S3 bucket
Get-ChildItem $LocalDirectory -File -Recurse | ForEach-Object {
    $UploadNeeded = $false
    $UpdateTimestampNeeded = $false

    $LocalFile = $_.FullName # This is needed for calculating the S3 object key

    $LocalFileLastModified = $_.LastWriteTimeUtc
    $LocalFileLastModifiedISO = $LocalFileLastModified.ToString("o")
    Write-Host "`n$LocalFile last modified time in ISO format: $LocalFileLastModifiedISO"

    $LocalFileHash = (Get-FileHash $LocalFile -Algorithm MD5).Hash.ToLower()

    # Replace back-lashes with forward-slashes
    $S3Key = $BucketPrefix + $LocalFile.Replace("\", "/")

    $S3Object = Get-S3ObjectIfExists -BucketName $BucketName -Key $S3Key

    if ($S3Object) {
        Write-Host "$S3Key exists in bucket." -ForegroundColor Green
        LogWrite "$S3Key exists in bucket."

        $S3ObjectMetadata = Get-S3ObjectMetadata -BucketName $BucketName -Key $S3Key -ErrorAction SilentlyContinue
        if ($S3ObjectMetadata.Metadata.Count -gt 0) {
            Write-Host "Metadata exists." -ForegroundColor Green
            $LastModifiedMeta = $S3ObjectMetadata.Metadata["x-amz-meta-lastmodified"]
            Write-Host "Last modified time in metadata: $LastModifiedMeta" -ForegroundColor Green
        } else {
            Write-Host "Metadata is not existings." -ForegroundColor Yellow
            $LastModifiedMeta = $null
        }

        $Etag = ($S3Object.ETag).Trim('"')

        if (-not $LastModifiedMeta) {
            # Trying to make sure all S3 objects have been added the last modified time of the local file
            Write-Host "S3 Object has no metadata of last modified time." -ForegroundColor Yellow
            if ($Etag -eq $LocalFileHash) {
                Write-Host "File uploaded without adding metadata, file is unchanged (ETag matches). Adding MetaData." -ForegroundColor Yellow
                $UpdateTimestampNeeded = $true
            } else {
                Write-Host "ETag does not match local file hash." -ForegroundColor Red
                if (IsMultipartETag($Etag) -eq $true) {
                    # When a large file is uploaded with multipart, the ETag has a dash.
                    Write-Host "ETag is with a dash, showing this is a multipart upload, please manually review, skipping." -ForegroundColor Yellow
                    LogWrite "$S3Key is a multipart upload, skipping."                
                } else {
                    Write-Host "ETag is not a multipart upload, try to fix." -ForegroundColor Yellow
                    LogWrite "$S3Key is not a multipart upload, try to fix according to Overwrite Priority setting."
                    if ($OverwritePriority -eq "Local") {
                        Write-Host "Overwrite Priority is 'Local', uploading." -ForegroundColor Yellow
                        Write-Host "Should I backup the S3 object, before overwritten?" -ForegroundColor Yellow
                        $UploadNeeded = $true
                    } elseif ($OverwritePriority -eq "S3") {
                        Write-Host "Overwrite Priority is 'S3', keep the S3 version, which is likely uploaded file with same name, skipping uploading, leaving the object without metadata." -ForegroundColor Yellow
                    } else {
                        Write-Host "Overwrite Priority is 'Manual', please check both local file and S3 object to understand." -ForegroundColor Yellow           
                    }
                }
            } 
        } else {
            # Compare local file last modified time with S3 metadata last modified time, local file is likely updated
            if ($LocalFileLastModifiedISO -gt $LastModifiedMeta) {
                Write-Host "Local file is newer than S3 metadata, uploading." -ForegroundColor Yellow
                $UploadNeeded = $true
            } elseif ($LocalFileLastModifiedISO -lt $LastModifiedMeta) {
                Write-Host "Local file is older than S3 metadata, indicating local file has been restored to older version, skipping upload." -ForegroundColor Yellow
            } else {
                Write-Host "Local file last modified time is matching S3 metadata, skipping upload." -ForegroundColor Green
            }
        }
    } else {
        Write-Host "$S3Key does not exist in bucket, uploading." -ForegroundColor Yellow
        $UploadNeeded = $true
    }

    If ($UploadNeeded) {
        Upload-S3 $LocalFile $BucketName $S3Key $LocalFileLastModifiedISO 
    }

    If ($UpdateTimestampNeeded) {
        Update-S3Timestamp $BucketName $S3Key $LocalFileLastModifiedISO 
    }
}

#endregion Upload Files

Write-Host "Directory $LocalPath Upload Completed." -ForegroundColor Green 
 
