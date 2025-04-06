# Sample Code To Upload A Directory From Windows to S3 Bucket.
# With logging function, log file in the same directory of this script.
# With checking function, to avoid uploading files that are already uploaded.
# With folder structure kept during upload.

Clear-Host

#region Variables
$BucketName = "XXXXXXXXXX"
$BucketPrefix = "XXXXXXXXXX"
$LocalDirectory = "C:\Users\XXXXXXXXXX\Documents\XXXXXXXXXX"
$CheckETag = $true
#endregion Variables

#region Logging
$LogFilePath = $PSScriptRoot + "\" + $MyInvocation.MyCommand.Name + ".log"
Function LogWrite($logString) {
    Add-content $LogFilePath -value $logString
}
#endregion Logging

#region Upload Files
Get-ChildItem $LocalDirectory -Recurse | ForEach-Object {
    $LocalFile = $_.FullName
    $S3Key = $LocalFile.Replace($LocalDirectory, $BucketPrefix).Replace("\", "/")
    if (Test-S3Object -BucketName $BucketName -Key $S3Key) {
        LogWrite "$S3Key already exists."
    }
    else {
        Write-S3Object -BucketName $BucketName -Key $S3Key -File $LocalFile -CannedACLName private
        LogWrite "$S3Key uploaded."
    }
}
#endregion Upload Files

Write-Host "Directory $LocalDirectory Upload Completed." -ForegroundColor Green




