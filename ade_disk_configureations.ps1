# Ensuring Azure PowerShell module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
}
Import-Module Az

Connect-AzAccount

$subscriptions = Get-AzSubscription
$outputContent = [System.Collections.Concurrent.ConcurrentBag[Object]]::new()

$nullCount = 0
$total_disk_number = 0

function Get-ValueOrStringNull {
    param (
        [Parameter(Mandatory=$true)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return "Null"
    } else {
        return $InputObject
    }
}

foreach ($subscription in $subscriptions) {

    Set-AzContext -SubscriptionId $subscription.SubscriptionId

    # Getting all VMs in the subscription
    $getAllVMInSubscription = Get-AzVM

    # Getting all disks in the subscription
    $disks = Get-AzDisk
    $total_disk_number += $disks.Count

    # Initialize the collection to store the results
    $vmDiskCollection = @()

    foreach ($vm in $getAllVMInSubscription) {
        # Getting the VM details
        $vmDetails = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
        $encryptionStatus = Get-AzVMDiskEncryptionStatus -ResourceGroupName $vmDetails.ResourceGroupName -VMName $vmDetails.Name

        #Find ADE extension version if ADE extension is installed                 
        $vmExtensions = $vmDetails.Extensions
        
        $isVMADEEncrypted = $false
        $extensionName = "Null"

        foreach ($extension in $vmExtensions) {
            if ($extension.Name -like "azurediskencryption*") {
                $extensionName = $extension.Name
                $isVMADEEncrypted = $true
                break;            
            }            
        }

        # Check OS disk
        $osDisk = $disks | Where-Object { $_.Id -eq $vmDetails.StorageProfile.OsDisk.ManagedDisk.Id }
        if ($osDisk) {
            
            if ($null -eq $disk.EncryptionSettingsCollection.EncryptionSettings)
            {
                $encryptionTypeOs = "Null"
            }
            else {
                $encryptionTypeOs = $disk.EncryptionSettingsCollection.EncryptionSettings

            }

            $recordOs = [PSCustomObject]@{
                Subscription       = $subscription.Name
                VMName             = $vm.Name
                ResourceGroup       = $vm.ResourceGroupName
                VMExtension        = $extensionName
                Encrypted          = $isVMADEEncrypted
                DiskEncryptionType = Get-ValueOrStringNull -InputObject $osDisk.Encryption.Type
                DiskName           = Get-ValueOrStringNull -InputObject $osDisk.Name
                StorageProfile     = "OS"
                StorageEncryption  = Get-ValueOrStringNull -InputObject $encryptionStatus.OsVolumeEncrypted
                EncryptionType     = if ($encryptionTypeOs -ne "Null" || $isVMADEEncrypted-eq $true) { "ADE" } else { "None or Other" }                
            }
            Write-Host "Record: " $recordOs
            if ($null -ne $recordOs) {
                $outputContent.Add($recordOs)
            }
            else {
                Write-Error "Null record issue: " $recordOs
            }
            $recordOs = $null
        }

        # Check data disks
        foreach ($dataDisk in $vmDetails.StorageProfile.DataDisks) {
            $disk = $disks | Where-Object { $_.Id -eq $dataDisk.ManagedDisk.Id }
            if ($disk) {

                if ($null -eq $disk.EncryptionSettingsCollection.EncryptionSettings)
                {
                    $encryptionType = "Null"
                }
                else {
                    $encryptionType = $disk.EncryptionSettingsCollection.EncryptionSettings
    
                }
                
                $recordData = [PSCustomObject]@{
                    Subscription       = $subscription.Name
                    VMName             = $vm.Name
                    ResourceGroup      = $vm.ResourceGroupName
                    VMExtension        = $extensionName
                    Encrypted          = $isVMADEEncrypted
                    DiskEncryptionType = Get-ValueOrStringNull -InputObject $disk.Encryption.Type
                    DiskName           = Get-ValueOrStringNull -InputObject $disk.Name
                    StorageProfile     = "Data"
                    StorageEncryption  = Get-ValueOrStringNull -InputObject $encryptionStatus.DataVolumesEncrypted
                    EncryptionType     = if ($encryptionType -ne "Null" || $isVMADEEncrypted-eq $true) { "ADE" } else { "None or Other" }
                }
                Write-Host "Record: " $recordData
                if ($null -ne $recordData){
                    $outputContent.Add($recordData)
                }
                else {
                    Write-Host "Null record issue: " $recordData
                }

                $recordData = $null
            }
        }
    }

    # Output the results
    $vmDiskCollection | Format-Table -Property Subscription, VMName, EncryptionType, Encrypted, VMExtension, DiskEncryptionType, DiskName, StorageProfile, StorageEncryption

}

# Convert ConcurrentBag to array for export
$outputArray = $outputContent.ToArray()

# Get the current date and time
$currentDateTime = Get-Date

# Format the date and time in a file-friendly format (e.g., 'YYYYMMDD_HHMMSS')
$dateTimeString = $currentDateTime.ToString("yyyyMMdd_HHmmss")


#Write to output file
$filePath = ".\" + "Scan_" + $dateTimeString + "_AdeVMInfo.csv"
$outputArray | export-csv -Path $filePath -NoTypeInformation

Write-Host "Total Record Count: " $outputContent.Count
