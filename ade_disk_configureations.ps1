# Check if Azure PowerShell module is installed, install it if not
if (-not (Get-Module -ListAvailable -Name Az)) {
    Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
}
Import-Module Az

# Connect to Azure account
Connect-AzAccount

# Retrieve all Azure subscriptions
$allSubscriptions = Get-AzSubscription
# Initialize a concurrent collection to store output data
$outputData = [System.Collections.Concurrent.ConcurrentBag[Object]]::new()

# Counter for total disks
$totalDiskCount = 0

# Function to return the input object or a string 'Null' if the input is null
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

# Iterate over each subscription
foreach ($subscription in $allSubscriptions) {
    # Set context to current subscription
    Set-AzContext -SubscriptionId $subscription.SubscriptionId

    # Retrieve all VMs and disks in the subscription
    $vmsInSubscription = Get-AzVM
    $disksInSubscription = Get-AzDisk
    $totalDiskCount += $disksInSubscription.Count

    # Initialize an array to store VM and disk information
    $vmDiskInfoArray = @()

    foreach ($vm in $vmsInSubscription) {
        # Retrieve details of each VM
        $vmDetails = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
        $encryptionStatus = Get-AzVMDiskEncryptionStatus -ResourceGroupName $vmDetails.ResourceGroupName -VMName $vmDetails.Name

        # Initialize encryption status and extension name
        $isVmEncrypted = $false
        $vmExtensionName = "Null"

        # Check for Azure Disk Encryption (ADE) extension
        foreach ($extension in $vmDetails.Extensions) {
            if ($extension.Name -like "azurediskencryption*") {
                $vmExtensionName = $extension.Name
                $isVmEncrypted = $true
                break;            
            }            
        }

        # Check and record OS disk encryption status
        $osDisk = $disksInSubscription | Where-Object { $_.Id -eq $vmDetails.StorageProfile.OsDisk.ManagedDisk.Id }
        if ($osDisk) {
            $encryptionTypeOsDisk = if ($null -eq $osDisk.EncryptionSettingsCollection.EncryptionSettings) { "Null" } else { $osDisk.EncryptionSettingsCollection.EncryptionSettings }
            $osDiskRecord = [PSCustomObject]@{
                Subscription       = $subscription.Name
                VMName             = $vm.Name
                ResourceGroup      = $vm.ResourceGroupName
                VMExtension        = $vmExtensionName
                Encrypted          = $isVmEncrypted
                DiskEncryptionType = Get-ValueOrStringNull -InputObject $osDisk.Encryption.Type
                DiskName           = Get-ValueOrStringNull -InputObject $osDisk.Name
                StorageProfile     = "OS"
                StorageEncryption  = Get-ValueOrStringNull -InputObject $encryptionStatus.OsVolumeEncrypted
                EncryptionType     = if ($encryptionTypeOsDisk -ne "Null" || $isVmEncrypted -eq $true) { "ADE" } else { "None or Other" }                
            }
            $outputData.Add($osDiskRecord)
        }

        # Check and record data disk encryption status
        foreach ($dataDisk in $vmDetails.StorageProfile.DataDisks) {
            $disk = $disksInSubscription | Where-Object { $_.Id -eq $dataDisk.ManagedDisk.Id }
            if ($disk) {
                $encryptionTypeDataDisk = if ($null -eq $disk.EncryptionSettingsCollection.EncryptionSettings) { "Null" } else { $disk.EncryptionSettingsCollection.EncryptionSettings }
                $dataDiskRecord = [PSCustomObject]@{
                    Subscription       = $subscription.Name
                    VMName             = $vm.Name
                    ResourceGroup      = $vm.ResourceGroupName
                    VMExtension        = $vmExtensionName
                    Encrypted          = $isVmEncrypted
                    DiskEncryptionType = Get-ValueOrStringNull -InputObject $disk.Encryption.Type
                    DiskName           = Get-ValueOrStringNull -InputObject $disk.Name
                    StorageProfile     = "Data"
                    StorageEncryption  = Get-ValueOrStringNull -InputObject $encryptionStatus.DataVolumesEncrypted
                    EncryptionType     = if ($encryptionTypeDataDisk -ne "Null" || $isVmEncrypted -eq $true) { "ADE" } else { "None or Other" }
                }
                $outputData.Add($dataDiskRecord)
            }
        }
    }
}

# Convert ConcurrentBag data to an array for exporting
$outputArray = $outputData.ToArray()

# Get current date and time for filename
$currentDateTime = Get-Date
$dateTimeString = $currentDateTime.ToString("yyyyMMdd_HHmmss")

# Export data to a CSV file
$filePath = ".\Scan_" + $dateTimeString + "_AdeVMInfo.csv"
$outputArray | Export-Csv -Path $filePath -NoTypeInformation

# Display total record count
Write-Host "Total Record Count: " $outputData.Count
