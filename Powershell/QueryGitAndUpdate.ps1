#params to do 

param
(
##[Parameter(Mandatory=$true)]
[string]$databaseServer,
[string]$database="HashHistoryDb",
[string]$dbUsername,
[string]$dbPassword,
[string]$repoSourcePath="C:\Users\ingledej\Documents\DevClanAzureChallenge",
[string]$subscriptionName="Visual Studio Ultimate with MSDN",
[string]$projectName="Jfi.TestAzureProject",
[string]$publishSettings,
[string]$storageAccount,
[string]$service,
[string]$containerName="mydeployments",
[string]$config,
[string]$package,
[string]$slot="Staging",
[string]$subscription
)

function Get-GitCommitHash {
    Set-Location $repoSourcePath

    git rev-parse HEAD
}

function Get-GitLatest {
    Set-Location $repoSourcePath

    git pull
}

Function Get-File($filter){
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $fd = New-Object system.windows.forms.openfiledialog
    $fd.MultiSelect = $false
    $fd.Filter = $filter
    [void]$fd.showdialog()
    return $fd.FileName
}

function Set-AzureSettings($publishSettings, $subscription, $storageAccount) {
    Import-AzurePublishSettingsFile $publishSettings

    Set-AzureSubscription $subscription -CurrentStorageAccount $storageAccount

    Select-AzureSubscription $subscription -Default
}

#function Get-AzureCred {
#    $securePassword = ConvertTo-SecureString $AzurePassword -AsPlainText -Force
#    $AzureCred = New-Object System.Management.Automation.PSCredential ($AzureUserName, $securePassword)   
#}

function Get-LastBuildHash {
    $currentHash = ""
    #$storageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName InnovationGroup
    $conn = New-Object System.Data.SqlClient.SqlConnection 
    $conn.ConnectionString = "Data Source=$databaseServer;Initial Catalog=$database;User ID=$dbUsername;Password=$dbPassword" 
    $conn.Open() 

    $cmd = $conn.CreateCommand() 
    $cmd.CommandText = "SELECT TOP (1) [GitHash] FROM [dbo].[GitHistory] ORDER BY [Id] DESC"
    $reader = $cmd.ExecuteReader() 
    while ($reader.Read()) {
        $currentHash = $reader.GetValue($1)
    }

    Write-Host "Latest stored hash: $currentHash"

    $currentHash
}

function Update-LatestBuildHash([string] $HashToInsert) {
    $conn = New-Object System.Data.SqlClient.SqlConnection 
    $conn.ConnectionString = "Data Source=$databaseServer;Initial Catalog=$database;User ID=$dbUsername;Password=$dbPassword" 
    $conn.Open() 

    $cmd = $conn.CreateCommand() 
    $cmd.CommandText = "INSERT INTO [dbo].[GitHistory] (GitHash) VALUES ($HashToInsert)"
    $result = $cmd.ExecuteNonQuery()
    Write-Host "Added record to database: $HashToInsert"
}

function Create-ProjectPackage {
    $fullProjPath = "$repoSourcePath\$projectName\$projectName.ccproj"

    exec { msbuild $fullProjPath /p:Configuration=Release
                                 /p:DebugType=None
                                 /p:Platform=AnyCpu
                                 /p:OutputPath=$repoSourcePath\Output
                                 /p:TargetProfile=Cloud
                                 /t:Publish }
}

function Upload-Package($package, $container){ 
    $blob = "$service.package.$(get-date -f yyyy_MM_dd_hh_ss).cspkg"

    $containerState = Get-AzureStorageContainer -Name $container -ea 0
    if ($containerState -eq $null)
    {
        New-AzureStorageContainer -Name $container | out-null
    }

    Set-AzureStorageBlobContent -File $package -Container $container -Blob $blob -Force| Out-Null
    $blobState = Get-AzureStorageBlob -blob $blob -Container $container

    $blobState.ICloudBlob.uri.AbsoluteUri
}

function Create-Deployment($packageurl, $service, $slot, $config){
    $stat = New-AzureDeployment -Slot $slot -Package $packageurl -Configuration $config -ServiceName $service
}

function Upgrade-Deployment($packageurl, $service, $slot, $config) {
    $setdeployment = Set-AzureDeployment -Upgrade -Slot $slot -Package $packageurl -Configuration $config -ServiceName $service -Force
}

function Check-Deployment($service, $slot) {
    $completeDeployment = Get-AzureDeployment -ServiceName $service -Slot $slot
    $completeDeployment.DeploymentId
}

Write-Host "Pulling latest from Git"
Get-GitLatest
Write-Host "Successfully pulled latest code"

Add-AzureAccount

try{
    #Import-AzurePublishSettingsFile $publishSettings

    #Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccount

    #Select-AzureSubscription -SubscriptionName $subscriptionName -Default

    $gitHash = Get-GitCommitHash
    Write-Host "Latest git hash: $gitHash"
    $sqlHash = Get-LastBuildHash

    if ($gitHash -ne $sqlHash) {
        Write-Host "Creating package..."
        Create-ProjectPackage
        Write-Host "Package created at $repoSourcePath\Output"

        Write-Host "Gathering required data"
        if (!$subscription){    $subscription = Read-Host "Subscription (case-sensitive)"}
        if (!$storageAccount){    $storageAccount = Read-Host "Storage account name"}
        if (!$service){            $service = Read-Host "Cloud service name"}
        if (!$publishSettings){    $publishSettings = Get-File "Azure publish settings (*.publishsettings)|*.publishsettings"}
        if (!$package){            $package = Get-File "Azure package (*.cspkg)|*.cspkg"}
        if (!$config){            $config = Get-File "Azure config file (*.cspkg)|*.cscfg"}

        Write-Host "Uploading package to cloud storage..."
        $packageurl = Upload-Package -package $package -container $containerName
        Write-Host "Package uploaded to $packageurl"

        WriteHost "Getting Azure deployment..."
        $deployment = Get-AzureDeployment -ServiceName $service -Slot $slot -ErrorAction silentlycontinue

        if ($deployment.Name -eq $null) {
            Write-Host "Deployment not found. Creating new deployment."
            Create-Deployment -packageurl $packageurl -service $service -slot $slot -config $config
            Write-Host "Created deployment"
        } else {
            Write-Host "Deployment found. Upgrading..."
            Upgrade-Deployment -packageurl $packageurl -service $service -slot $slot -config $config
            Write-Host "Upgraded deployment"
        }

        Write-Host "Checking deployment..."
        $deploymentId = Check-Deployment -service $service -slot $slot
        Write-Host "Deployment OK. ID $deploymentId "
        Write-Host "Service: $service"
        Write-Host "Slot: $slot"

        # update git hash in table
        Write-Host "Updating Git Hash History with new has $gitHash"
        Update-LatestBuildHash -hashToInsert $gitHash
        Write-Host "Done. Exiting..."
        exit 0
    }
}
catch [System.Exception] {
    Write-Host $_.Exception.ToString()
    exit 1
}
