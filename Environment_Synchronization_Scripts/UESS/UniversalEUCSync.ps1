[CmdletBinding()]
Param(
	[Parameter(Mandatory=$false)][string]$FolderPath,
	[Parameter(Mandatory=$false)][string]$Exclude,
	[Parameter(Mandatory=$false)][string]$AddBrokers,
	[Parameter(Mandatory=$false)][string]$Delete,
	[Parameter(Mandatory=$false)][string]$Force,
	[Parameter(Mandatory=$false)][string]$Domain,
	[Parameter(Mandatory=$false)][string]$Preview,
	[Parameter(Mandatory=$false)][string]$VerbosDebug,
	[Parameter(Mandatory=$false)][string]$SaveConfig
)

#########################################
########### Support Functions ###########
#########################################

function Write-CULog {
Param(
	[Parameter(Mandatory = $True)][Alias('M')][String]$Msg,
	[Parameter(Mandatory = $False)][Alias('S')][switch]$ShowConsole,
	[Parameter(Mandatory = $False)][Alias('C')][String]$Color = "",
	[Parameter(Mandatory = $False)][Alias('T')][String]$Type = "",
	[Parameter(Mandatory = $False)][Alias('B')][switch]$SubMsg
)
    
    $LogType = "INFORMATION..."
    if ($Type -eq "W"){ $LogType = "WARNING........."; $Color = "Yellow" }
    if ($Type -eq "E"){ $LogType = "ERROR..............."; $Color = "Red" }
    if (!($SubMsg)){$PreMsg = "+"}else{$PreMsg = "`t>"}
    $date = Get-Date -Format G
    if ($Global:LogFile){Write-Output "$date | $LogType | $Msg"  | Out-file $($Global:LogFile) -Append}
            
    if (!($ShowConsole)){
	    if (($Type -eq "W") -or ($Type -eq "E")){Write-Host "$PreMsg $Msg" -ForegroundColor $Color;$Color = $null}else{Write-Verbose -Message "$PreMsg $Msg";$Color = $null}
    }else{
	    if ($Color -ne ""){Write-Host "$PreMsg $Msg" -ForegroundColor $Color;$Color = $null}else{Write-Host "$PreMsg $Msg"}
    }
}

function Remap{
#Remaps the path to the new path based on filters
	$path = $args[0]
	foreach ($map in $global:maps){
		$map = $map.split(',')
		$path = $path.replace($map[0],$map[1].trim()).replace('\\','')
	}
	return $path
}

function siteMap {
#Filters Computer and Site names to math paths
	$path = $args[0] + $args[1]
		if ($global:SiteMaps){
			foreach ($map in $global:SiteMaps){
				$map = $map.split(',')
				$sMap = $map[1].trim()
				if($path -like "*$($map[0])*"){
					$site = if($global:cuSites|?{$_.name -eq $sMap}){$sMap}
					break
				}else{$site = "Default"}
			}
		}else{$site = "Default"}
		$siteGuid = ($global:cuSites|?{$_.name -eq $site}).id
	return $siteGuid
}

function fixPathCase{
$path = $args[0]
	foreach($name in $global:FolderNameCase){
		$path = $path.replace($name.toLower(),$name)
	}
return $path
}
#########################################
######## Save and Import Config #########
#########################################

$tsStart = get-date
#PS Module Import and test Module is running correctly
try {
	Get-Item "$((get-childitem 'C:\Program Files\Smart-X\ControlUpMonitor\' -Directory)[-1].fullName)\*powershell*.dll"|import-module
	$global:cuSites = get-cusites
}catch{if($_){throw $_}}

$logTime = (get-date).toString("MMddyyyyHHmm")
$exportPath = "$($env:programdata)\ControlUp\SyncScripts"
$LogFile = "$exportPath\Logs\$logTime.log"
New-Item -ItemType Directory -Force -Path "$exportPath\Logs" |out-null

[String]$syncFolder = $FolderPath
[String]$Exclude = if($Exclude.toLower() -ne "no"){$Exclude}else{$null}
[Array]$ExcludedWords = if($Exclude){$Exclude.split(",")}else{$null}
[bool]$addBrokers = if($addBrokers.toLower()[0] -eq "y"){$true}else{$false}
[bool]$Delete = if($Delete.toLower()[0] -eq "y"){$true}else{$false}
[bool]$Force = if($Force.toLower()[0] -eq "y"){$true}else{$false}
[String]$DomainOverride = if($Domain.toLower() -ne "no"){$Domain}else{$null}
[bool]$Preview = if($Preview.ToLower()[0] -eq "y"){$false}else{$true}
[bool]$VerbosDebug = if($VerbosDebug.ToLower()[0] -eq "y"){$true}else{$false}
[bool]$save = if($saveConfig.ToLower()[0] -eq "y"){$true}else{$false}

if($save){
#export arguments to config file
	$Config = @{
		SyncFolder = $syncFolder; 
		Excludes = $Exclude;
		AddBrokers = $addBrokers;
		Force = $Force;
		DomainOverride = $DomainOverride;
		delete = $delete;
		Preview = $preview;
		VerbosDebug = $VerbosDebug;
	}
	
	New-Item -ItemType Directory -Force -Path $exportPath |out-null
	$config|convertto-json|Out-File -FilePath "$exportPath\Universal_EUC_Sync.cfg" -Force
	if(!(test-path "$exportPath\sitemap.cfg")){$null|Out-File -FilePath "$exportPath\sitemap.cfg" -Force}
	if(!(test-path "$exportPath\map.cfg")){$null|Out-File -FilePath "$exportPath\map.cfg" -Force}
	$config|convertto-json|Out-File -FilePath "$exportPath\Universal_EUC_Sync.cfg" -Force
	
	$configImport = get-content "$exportPath\Universal_EUC_Sync.cfg"|convertfrom-json
	write-host "Configuration Saved. Please validate the following settings before finalizing: `n`n $($configImport|out-string) Exiting Script, To finalize please change 'Save Configuration File' to No'"
	exit
}

if (test-path "$exportPath\Universal_EUC_Sync.cfg"){$configImport = get-content "$exportPath\Universal_EUC_Sync.cfg"|convertfrom-json}
if (test-path "$exportPath\Map.cfg"){$global:maps = get-content "$exportPath\Map.cfg"}else{$null|Out-File -FilePath "$exportPath\map.cfg" -Force}
if (test-path "$exportPath\SiteMap.cfg"){$global:SiteMaps = get-content "$exportPath\SiteMap.cfg"}else{$null|Out-File -FilePath "$exportPath\sitemap.cfg" -Force}
if(!$configImport -and !$save){write-host "Please save a configuration before running the script";exit}
if($configImport -and !$save){
#import Config File
	$syncFolder = $configImport.SyncFolder
	[Array]$excludedWords = if($configImport.Excludes.count){$configImport.Excludes.split(",")}
	[bool]$delete = $configImport.delete
	[bool]$preview = $configImport.Preview
	[bool]$VerbosDebug = $configImport.VerbosDebug
	[bool]$addBrokers = $configImport.AddBrokers
	[bool]$Force = $configImport.Force
	$DomainOverride = if($configImport.DomainOverride){$configImport.DomainOverride}
}

$query = New-Object -TypeName System.Collections.Generic.List[PSObject]
class machines{
    [string]$ParentFolderPath
    [string]$sName
    [string]$GuestHostName
        machines ([String]$ParentFolderPath,[string]$sName,[string]$GuestHostName) {
        $this.ParentFolderPath = $ParentFolderPath
        $this.sName = $sName
        $this.GuestHostName = $GuestHostName
    }
}

if(!$syncFolder){throw "No sync folder found. `n`nPlease use arguments or the config file"}

#########################################
### Build Variables and Create Object ###
#########################################

$global:sf = $syncFolder
$root = (Get-CUFolders)[0].name.toLower()
$rootPath = "$root\$syncFolder"
#array List
$iq = [System.Collections.ArrayList]@()
$names = [System.Collections.ArrayList]@()
$noDNS = [System.Collections.ArrayList]@()
$folderList = [System.Collections.ArrayList]@()
$foldersToAdd = [System.Collections.ArrayList]@()
$data = [System.Collections.ArrayList]@()
$noAdd = [System.Collections.ArrayList]@()
$eucFolder = [System.Collections.ArrayList]@()
$global:eucDisconnected = [System.Collections.ArrayList]@()
$removedEUC = [System.Collections.ArrayList]@()
$maxValue = [int32]::MaxValue
$global:FolderNameCase = [System.Collections.ArrayList]@()
(Invoke-CUQuery -Fields "Name" -Scheme "Main" -Table "Folders" -Focus "$root\EUC Environments").data.name|%{$global:FolderNameCase.add($_)|out-null}

if($addBrokers){
	#Adding cloud connectorss, connection servers, delivery controllers
	if($VerbosDebug){Write-CULog -Msg "Adding cloud connectors, connection servers, delivery controllers to array" -ShowConsole -color Green}
	else{Write-CULog -Msg "Adding cloud connectors, connection servers, delivery controllers to array"}
	$iq.Add((Invoke-CUQuery -Fields "ParentFolderPath", "sName", "GuestHostName" -Take $maxValue -Scheme "Main" -Table "XD_Brokers" -Focus "$root\EUC Environments").data)|out-null
	$iq.Add((Invoke-CUQuery -Fields "xdBrokerFolderPath", "sName", "GuestHostName" -Take $maxValue -Scheme "Main" -Table "CloudConnector" -Focus "$root\EUC Environments").data)|out-null
}else{
	#write-host "Skipping Brokers"
}

#Pull All EUC Machines from delivery groups and desktop pools
if($VerbosDebug){Write-CULog -Msg "Pull All EUC Machines from delivery groups and desktop pools to array" -ShowConsole -color Green}
else{Write-CULog -Msg "Pull All EUC Machines from delivery groups and desktop pools to array"}
$iq.Add((Invoke-CUQuery -Fields "ParentFolderPath", "sName", "GuestHostName" -Take $maxValue -Scheme "Main" -Table "XD_VDA" -Focus "$root\EUC Environments").data)|out-null

#Put all query machines into an object for easy processing
if($VerbosDebug){Write-CULog -Msg "Put all query machines into an object for easy processing" -ShowConsole -color Green}
else{Write-CULog -Msg "Put all query machines into an object for easy processing"}
foreach ($q in $iq){
	foreach ($item in $q){
		if($item.ParentFolderPath){$path =remap $item.ParentFolderPath}
		if($item.xdBrokerFolderPath){$path = remap $item.xdBrokerFolderPath}
		$query.Add([machines]::new($path,$item.sname,$item.GuestHostName))|out-null
	}
}


#Determine if an EUC connection exists but is disconnected
if($VerbosDebug){Write-CULog -Msg "Determine if an EUC connection exists but is disconnected" -ShowConsole -color Green}
else{Write-CULog -Msg "Determine if an EUC connection exists but is disconnected"}
(Invoke-CUQuery -Fields "*" -Take $maxValue -Scheme "Main" -Table "Folders" -Focus "$root\EUC Environments").data.path|%{if(([string]$_).toString().split('\').count -eq 3){$eucFolder.add($_)|out-null}}
$eucConnected = (Invoke-CUQuery -Fields "ParentFolderPath", "sName", "GuestHostName" -Take $maxValue -Scheme "Main" -Table "XD_VDA" -Focus "$root\EUC Environments").data


#if EUC folder is disconnected, do not remove machines
if($VerbosDebug){Write-CULog -Msg "if EUC folder is disconnected, do not remove machines" -ShowConsole -color Green}
else{Write-CULog -Msg "if EUC folder is disconnected, do not remove machines"}
foreach ($folder in $eucConnected){
	$s = $folder.ParentFolderPath.split("\")
	$eucFolder.remove("$($s[0])\$($s[1])\$($s[2])")
	$removedEUC.add("$($s[0])\$($s[1])\$($s[2])")|out-null
}
$disconnected = $removedEUC|sort -unique|out-string
if($VerbosDebug){Write-CULog -Msg "Disconnected: $($Disconnected)" -ShowConsole -SubMsg -Color Red}
else{Write-CULog -Msg "Disconnected: $($Disconnected)"}

#Remaps every folder to where they will belong, this is from the Map.cfg
if($VerbosDebug){Write-CULog -Msg "Remaps every folder to where they will belong, this is from the Map.cfg" -ShowConsole -color Green}
else{Write-CULog -Msg "Remaps every folder to where they will belong, this is from the Map.cfg"}
$eucFolder|%{
	$ex = $_.split("\")
	$map = if($global:maps){remap "$rootPath\$($ex[2])".toLower()}else{"$rootPath\$($ex[2])".toLower()}
	$global:eucDisconnected.Add($map)|out-null
}


#Exclude Folders/Machines/Prefixes/Whatever
if($VerbosDebug){Write-CULog -Msg "Exclude Folders/Machines/Prefixes" -ShowConsole -color Green}
else{Write-CULog -Msg "Exclude Folders/Machines/Prefixes"}

if($excludedWords){
	foreach ($item in $query){
		foreach ($exclusion in $excludedWords){
			#write-host $item.ParentFolderPath.toLower() 
			$exclusion = $exclusion.trim()
			if($item.ParentFolderPath.toLower() -like "*$($exclusion.toLower())*"){$noAdd.Add($item.ParentFolderPath)|out-null}
			if($item.sName.toLower() -like "*$($exclusion.toLower())*"){$noAdd.Add($item.sName)|out-null}
			
		}
	}
}

#Massaging and adding machine data to the collection to be populated
if($VerbosDebug){Write-CULog -Msg "Massaging and adding machine data to the collection to be populated" -ShowConsole -color Green}
else{Write-CULog -Msg "Massaging and adding machine data to the collection to be populated"}

foreach ($item in $query){
	if($item.ParentFolderPath){
		if($item.ParentFolderPath.toLower() -notin $noAdd -and $item.sName -notin $noAdd){
			$data.Add($item)|out-null
		}
	}
}

$Environment = New-Object -TypeName System.Collections.Generic.List[PSObject]
class ControlUpObject{
    [string]$Name
    [string]$FolderPath
    [string]$Type
    [string]$Domain
    [string]$Description
    [string]$DNSName
    [string]$Site
        ControlUpObject ([String]$Name,[string]$folderPath,[string]$type,[string]$domain,[string]$description,[string]$DNSName,[string]$Site) {
        $this.Name = $Name
        $this.FolderPath = $folderPath
        $this.Type = $type
        $this.Domain = $domain
        $this.Description = $description
        $this.DNSName = $DNSName
        $this.Site = $Site
    }
}

#Creating Machines ControlUp Object to be shipped to buildcutree
if($VerbosDebug){Write-CULog -Msg "Creating Machines Object, be patient this could take some time. Expecially if looking up DNS" -ShowConsole -color Magenta}
else{Write-CULog -Msg "Creating Machines Object, be patient this could take some time. Expecially if looking up DNS"}

foreach ($item in $data){
	#Get FQDN for machine
	if(!$DomainOverride){
		$resolveDNS = $null
		if($force){
			try{$resolveDNS = [System.Net.Dns]::GetHostByName($item.sName).hostname}catch{}
		}else{
			if(![string]::IsNullOrEmpty($item.guesthostname)){
				$resolveDNS = $item.guesthostname
			}else{
				try{$resolveDNS = [System.Net.Dns]::GetHostByName($item.sName).hostname}catch{}
			}
		}
	}
	
	if(![string]::IsNullOrEmpty($resolveDNS) -or ![string]::IsNullOrEmpty($DomainOverride)){
		if($DomainOverride){$Domain = $DomainOverride}else{$Domain = $resolveDNS.substring($resolveDNS.indexof(".")+1)}
		if ($item.ParentFolderPath){$folderPath = ($item.ParentFolderPath).replace("euc environments",$syncFolder)}
		
		$folderList.Add($folderPath.TrimEnd("\"))|out-null
		$folder = $folderPath.TrimEnd("\")
		$folder = $folder.replace("$rootPath\","")
		$site = siteMap "$($item.sname)$folder"
		$name = $item.sname.split(".")[0]
		$Environment.Add(([ControlUpObject]::new($name, $folder ,"Computer", $Domain ,"Added by Sync Script", $resolveDNS,$site)))
	}
}

#Creating Folder ControlUp Object to be shipped to buildcutree
if($VerbosDebug){Write-CULog -Msg "Creating Folder Object, should be quick" -ShowConsole -color Green}
else{Write-CULog -Msg "Creating Folder Object, should be quick"}
$foldersToAdd.Add($rootPath.TrimEnd("\"))|out-null
foreach ($path in $folderList){
	if($path -ne $rootPath -or $path -ne $root){
		$exploded = ($path.replace($rootPath.toLower(),"")).split("\")
		for ($i = 0; $i -lt $exploded.count; $i++) {
			$folderadd = if($i -eq 0){$exploded[$i]}else{$foldersToAdd[-1] + "\$($exploded[$i])".TrimEnd("\")}
			$foldersToAdd.Add($folderadd)|out-null
		}
	}
}

$uniqueFolders = ($foldersToAdd|?{$_ -ne $root -and $_ -ne $rootPath})|sort -unique
foreach ($folder in $uniqueFolders){
	$folderName = fixPathCase $folder.split("\")[-1]
	$addFolderTo = fixPathCase $folder.replace("$rootPath\","")
	#write-host "Name: $folderName -> $addfolderTo"
	$Environment.Add([ControlUpObject]::new($FolderName,$addFolderTo,"Folder",$null,$null,$null,$null))
}

$tsEnd = get-date
$time = new-timespan -start $tsStart -end $tsEnd
if($VerbosDebug){Write-CULog -Msg "Time it took to build Object: $($time.TotalSeconds) seconds." -ShowConsole -color Yellow}
else{Write-CULog -Msg "Time it took to build Object: $($time.TotalSeconds) seconds."}

############################
##### Start BuildCUTree ####
############################
function Build-CUTree {
    [CmdletBinding()]
    Param(
	    [Parameter(Mandatory=$true,HelpMessage='Object to build tree within ControlUp')]
	    [PSObject] $ExternalTree,
	    [Parameter(Mandatory=$false,HelpMessage='ControlUp root folder to sync')]
	    [string] $CURootFolder,
	    [Parameter(Mandatory=$false,HelpMessage='ControlUp root ')]
	    [string] $CUSyncFolder,
 	    [Parameter(Mandatory=$false, HelpMessage='Delete CU objects which are not in the external source')]
	    [switch] $Delete,
        [Parameter(Mandatory=$false, HelpMessage='Generate a report of the actions to be executed')]
        [switch]$Preview,
        [Parameter(Mandatory=$false, HelpMessage='Save a log file')]
	    [string] $LogFile,
        [Parameter(Mandatory=$false, HelpMessage='ControlUp Site name to assign the machine object to')]
	    [string] $SiteName,
        [Parameter(Mandatory=$false, HelpMessage='Debug CU Machine Environment Objects')]
	    [Object] $DebugCUMachineEnvironment,
        [Parameter(Mandatory=$false, HelpMessage='Debug CU Folder Environment Object')]
	    [switch] $DebugCUFolderEnvironment ,
        [Parameter(Mandatory=$false, HelpMessage='Create folders in batches rather than individually')]
	    [switch] $batchCreateFolders ,
        [Parameter(Mandatory=$false, HelpMessage='Number of folders to be created that generates warning and requires -force')]
        [int] $batchCountWarning = 100 ,
        [Parameter(Mandatory=$false, HelpMessage='Force creation of folders if -batchCountWarning size exceeded')]
        [switch] $force ,
        [Parameter(Mandatory=$false, HelpMessage='Smtp server to send alert emails from')]
	    [string] $SmtpServer ,
        [Parameter(Mandatory=$false, HelpMessage='Email address to send alert email from')]
	    [string] $emailFrom ,
        [Parameter(Mandatory=$false, HelpMessage='Email addresses to send alert email to')]
	    [string[]] $emailTo ,
        [Parameter(Mandatory=$false, HelpMessage='Use SSL to send email alert')]
	    [switch] $emailUseSSL ,
        [Parameter(Mandatory=$false, HelpMessage='Delay between each folder creation when count exceeds -batchCountWarning')]
        [double] $folderCreateDelaySeconds = 0.5
   )
	
        #This variable sets the maximum computer batch size to apply the changes in ControlUp. It is not recommended making it bigger than 1000
        $maxBatchSize = 1000
        #This variable sets the maximum batch size to apply the changes in ControlUp. It is not recommended making it bigger than 100
        $maxFolderBatchSize = 100
        [int]$errorCount = 0
        [array]$stack = @(Get-PSCallStack)
        [string]$callingScript = $stack.Where({ $_.ScriptName -ne $stack[0].ScriptName }) | Select-Object -First 1 -ExpandProperty ScriptName
        if(!$callingScript -and !($callingScript = $stack | Select-Object -First 1 -ExpandProperty ScriptName)){$callingScript = $stack[-1].Position}

        function Execute-PublishCUUpdates {
            Param(
	            [Parameter(Mandatory = $True)][Object]$BatchObject,
	            [Parameter(Mandatory = $True)][string]$Message
           )
            [int]$returnCode = 0
            [int]$batchCount = 0
            foreach ($batch in $BatchObject){
                $batchCount++
                Write-CULog -Msg "$Message. Batch $batchCount/$($BatchObject.count)" -ShowConsole -Color DarkYellow -SubMsg
                if (-not($preview)){
                    [datetime]$timeBefore = [datetime]::Now
                    $result = Publish-CUUpdates -Batch $batch 
                    [datetime]$timeAfter = [datetime]::Now
                    [array]$results = @(Show-CUBatchResult -Batch $batch)
                    [array]$failures = @($results.Where({$_.IsSuccess -eq $false})) ## -and $_.ErrorDescription -notmatch 'Folder with the same name already exists' }))

                    Write-CULog -Msg "Execution Time: $(($timeAfter - $timeBefore).TotalSeconds) seconds" -ShowConsole -Color Green -SubMsg
                    Write-CULog -Msg "Result: $result" -ShowConsole -Color Green -SubMsg
                    Write-CULog -Msg "Failures: $($failures.Count) / $($results.Count)" -ShowConsole -Color Green -SubMsg

                    if($failures -and $failures.Count -gt 0){
                        $returnCode += $failures.Count
                        foreach($failure in $failures){Write-CULog -Msg "Action $($failure.ActionName) on `"$($failure.Subject)`" gave error $($failure.ErrorDescription) ($($failure.ErrorCode))" -ShowConsole -Type E}
                    }
                }else{Write-CULog -Msg "Execution Time: PREVIEW MODE" -ShowConsole -Color Green -SubMsg}
            }
        }
        

        #attempt to setup the log file
        if ($PSBoundParameters.ContainsKey("LogFile")){
            $Global:LogFile = $PSBoundParameters.LogFile
            Write-Host "Saving Output to: $Global:LogFile"
            if (-not(Test-Path $($PSBoundParameters.LogFile))){
                Write-CULog -Msg "Creating Log File" #Attempt to create the file
                if (-not(Test-Path $($PSBoundParameters.LogFile))){Write-Error "Unable to create the report file" -ErrorAction Stop}
            }else{Write-CULog -Msg "Beginning Synchronization"}
            Write-CULog -Msg "Detected the following parameters:"
            foreach($psbp in $PSBoundParameters.GetEnumerator()){
                if ($psbp.Key -like "ExternalTree" -or $psbp.Key -like "DebugCUMachineEnvironment"){
                    Write-CULog -Msg $("Parameter={0} Value={1}" -f $psbp.Key,$psbp.Value.count)
                }else{Write-CULog -Msg $("Parameter={0} Value={1}" -f $psbp.Key,$psbp.Value)}
            }
        }else{$Global:LogFile = $false}

        if(!$PSBoundParameters['folderCreateDelaySeconds' ] -and $env:CU_delay){
            $folderCreateDelaySeconds = $env:CU_delay
        }

        $startTime = Get-Date
        [string]$errorMessage = $null

        #region Load ControlUp PS Module
        try{
            ## Check CU monitor is installed and at least minimum required version
            [string]$cuMonitor = 'ControlUp Monitor'
            [string]$cuDll = 'ControlUp.PowerShell.User.dll'
            [string]$cuMonitorProcessName = 'CUmonitor'
            [version]$minimumCUmonitorVersion = '8.1.5.600'
            if(!($installKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -Name DisplayName -ErrorAction SilentlyContinue| Where-Object DisplayName -eq $cuMonitor)){
                Write-CULog -ShowConsole -Type W -Msg "$cuMonitor does not appear to be installed"
            }
            ## when running via scheduled task we do not have sufficient rights to query services
            if(!($cuMonitorProcess = Get-Process -Name $cuMonitorProcessName -ErrorAction SilentlyContinue)){
                Write-CULog -ShowConsole -Type W -Msg "Unable to find process $cuMonitorProcessName for $cuMonitor service" ## pid $($cuMonitorService.ProcessId)"
            }else{
                [string]$message =  "$cuMonitor service running as pid $($cuMonitorProcess.Id)"
                ## if not running as admin/elevated then won't be able to get start time
                if($cuMonitorProcess.StartTime){
                    $message += ", started at $(Get-Date -Date $cuMonitorProcess.StartTime -Format G)"
                }
                Write-CULog -Msg $message
            }

	        # Importing the latest ControlUp PowerShell Module - need to find path for dll which will be where cumonitor is running from. Don't use Get-Process as may not be elevated so would fail to get path to exe and win32_service fails as scheduled task with access denied
            if(!($cuMonitorServicePath = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\cuMonitor' -Name ImagePath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ImagePath))){
                Throw "$cuMonitor service path not found in registry"
            }elseif(!($cuMonitorProperties = Get-ItemProperty -Path $cuMonitorServicePath.Trim('"') -ErrorAction SilentlyContinue)){
                Throw  "Unable to find CUmonitor service at $cuMonitorServicePath"
            }elseif($cuMonitorProperties.VersionInfo.FileVersion -lt $minimumCUmonitorVersion){
                Throw "Found version $($cuMonitorProperties.VersionInfo.FileVersion) of cuMonitor.exe but need at least $($minimumCUmonitorVersion.ToString())"
            }elseif(!($pathtomodule = Join-Path -Path (Split-Path -Path $cuMonitorServicePath.Trim('"') -Parent) -ChildPath $cuDll)){
                Throw "Unable to find $cuDll in `"$pathtomodule`""
            }elseif(!(Import-Module $pathtomodule -PassThru)){
                Throw "Failed to import module from `"$pathtomodule`""
            }elseif(!(Get-Command -Name 'Get-CUFolders' -ErrorAction SilentlyContinue)){
                Throw "Loaded CU Monitor PowerShell module from `"$pathtomodule`" but unable to find cmdlet Get-CUFolders"
            }
        }catch{
            $exception = $_
            Write-CULog -Msg $exception -ShowConsole -Type E
            ##Write-CULog -Msg (Get-PSCallStack|Format-Table)
            Write-CULog -Msg 'The required ControlUp PowerShell module was not found or could not be loaded. Please make sure this is a ControlUp Monitor machine.' -ShowConsole -Type E
            Send-EmailAlert -SmtpServer $SmtpServer -from $emailFrom -to $emailTo -useSSL:$emailUseSSL -subject "Fatal error from ControlUp sync script `"$callingScript`" on $env:COMPUTERNAME" -body "$exception"
            $errorCount++
            break
        }
        #endregion


        #region Retrieve ControlUp folder structure
        if (-not($DebugCUMachineEnvironment)){
            try {
                $CUComputers = Get-CUComputers # add a filter on path so only computers within the $rootfolder are used
            }catch{
                $errorMessage = "Unable to get computers from ControlUp: $_" 
                Write-CULog -Msg $errorMessage -ShowConsole -Type E
                Send-EmailAlert -SmtpServer $SmtpServer -from $emailFrom -to $emailTo -useSSL:$emailUseSSL -subject "Fatal error from ControlUp sync script `"$callingScript`" on $env:COMPUTERNAME" -body "$errorMessage"
                $errorCount++
                break
            }
        }else{
            Write-Debug "Number of objects in DebugCUMachineEnvironment: $($DebugCUMachineEnvironment.count)"
            if ($($DebugCUMachineEnvironment.count) -eq 2){
                foreach ($envObjects in $DebugCUMachineEnvironment){
                    if ($($envObjects  | Get-Member).TypeName[0] -eq "Create-CrazyCUEnvironment.CUComputerObject"){$CUComputers = $envObjects}
                }
            }else{$CUComputers = $DebugCUMachineEnvironment}
        }
        
        Write-CULog -Msg  "CU Computers Count: $(if($CUComputers){ $CUComputers.count }else{ 0 })" -ShowConsole -Color Cyan
        #create a hashtable out of the CUMachines object as it's much faster to query. This is critical when looking up Machines when ControlUp contains ten's of thousands of machines.
        $CUComputersHashTable = @{}
        foreach ($machine in $CUComputers){
            foreach ($obj in $machine){
                $CUComputersHashTable.Add($Obj.Name, $obj)
            }
        }

        if (-not($DebugCUFolderEnvironment)){
            try {
                $CUFolders   = Get-CUFolders # add a filter on path so only folders within the rootfolder are used
            }catch{
                $errorMessage = "Unable to get folders from ControlUp: $_"
                Write-CULog -Msg $errorMessage  -ShowConsole -Type E
                Send-EmailAlert -SmtpServer $SmtpServer -from $emailFrom -to $emailTo -useSSL:$emailUseSSL -subject "Fatal error from ControlUp sync script `"$callingScript`" on $env:COMPUTERNAME" -body "$errorMessage"
                $errorCount++
                break
            }
        }else{
            Write-Debug "Number of folder objects in DebugCUMachineEnvironment: $($DebugCUMachineEnvironment.count)"
            if ($($DebugCUMachineEnvironment.count) -eq 2){
                foreach ($envObjects in $DebugCUMachineEnvironment){
                    if ($($envObjects  | Get-Member).TypeName[0] -eq "Create-CrazyCUEnvironment.CUFolderObject"){$CUFolders = $envObjects}
                }
            }else{$CUFolders = Get-CUFolders}
        }

        #endregion
        $OrganizationName = ($CUFolders)[0].path
        Write-CULog -Msg "Organization Name: $OrganizationName" -ShowConsole
        [array]$rootFolders = @(Get-CUFolders | Where-Object FolderType -eq 'RootFolder')
        Write-Verbose -Message "Got $($rootFolders.Count) root folders/organisations: $(($rootFolders | Select-Object -ExpandProperty Path) -join ' , ')"

        [string]$pathSoFar = $null
        [bool]$builtPath = $false
        ## strip off leading \ as CU cmdlets don't like it
        [string[]]$CURootFolderElements = @(($CURootFolder.Trim('\').Split('\')))
        Write-Verbose -Message "Got $($CURootFolderElements.Count) elements in path `"$CURootFolder`""

        ## see if first folder element is the organisation name and if not then we will prepend it as must have that
        if($OrganizationName -ne $CURootFolderElements[0]){
            #Write-CULog -Msg "Organization Name `"$OrganizationName`" not found in path `"$CURootFolder`" so adding" -Verbose
            $CURootFolder = Join-Path -Path $OrganizationName -ChildPath $CURootFolder
        }

        ## Code making folders checks if each element in folder exists and if not makes it so no pointmaking path here

        #region Prepare items for synchronization
        #replace FolderPath in ExternalTree object with the local ControlUp Path:
        foreach ($obj in $externalTree){$obj.FolderPath = (Join-Path -Path $CURootFolder -ChildPath $obj.FolderPath).Trim('\')}

        #We also create a hashtable to improve lookup performance for computers in large organizations.
        $ExtTreeHashTable = @{}
        $ExtFolderPaths = New-Object -TypeName System.Collections.Generic.List[psobject]
        foreach ($ExtObj in $externalTree){
            foreach ($obj in $ExtObj){
                ## GRL only add computers since that is all we look up and get duplicate error if OU and computer have the same name
                if($obj.Type -eq 'Computer'){
                    $ExtTreeHashTable.Add($Obj.Name, $obj)
                }else{
                    $ExtFolderPaths.Add($obj)
                }
            }
        }

        Write-CULog -Msg "Target Folder Paths:" -ShowConsole
        if ($ExtFolderPaths.count -ge 25){
            Write-CULog "$($ExtFolderPaths.count) paths detected" -ShowConsole -SubMsg
            foreach ($ExtFolderPath in $ExtFolderPaths){Write-CULog -Msg "$($ExtFolderPath.FolderPath)" -SubMsg}
        }else{
            foreach ($ExtFolderPath in $ExtFolderPaths){Write-CULog -Msg "$($ExtFolderPath.FolderPath)" -ShowConsole -SubMsg}
        }

        $FolderAddBatches   = New-Object System.Collections.Generic.List[PSObject]
        $FoldersToAddBatch  = New-CUBatchUpdate
        $FoldersToAddCount  = 0

        #we'll output the statistics at the end -- also helps with debugging
        $FoldersToAdd          = New-Object System.Collections.Generic.List[PSObject]
        ## There can be problems when folders are added in large numbers so we will see how many new ones are being requested so we can control if necessary
        $FoldersToAddBatchless = New-Object System.Collections.Generic.List[PSObject]
        [hashtable]$newFoldersAdded = @{} ## keep track of what we've issued btch commands to create so we don't duplicate

        foreach ($ExtFolderPath in $ExtFolderPaths.FolderPath){
            if ($ExtFolderPath -notin $CUFolders.Path){ 
                [string]$pathSoFar = $null
                ## Check each part of the path exists, or will be created, and if not add a task to create it
				#write-host $ExtFolderPath
                foreach($pathElement in ($ExtFolderPath.Trim('\')).Split('\')){
                    [string]$absolutePath = $(if($pathSoFar){ Join-Path -Path $pathSoFar -ChildPath $pathElement }else{ $pathElement })
                    if($null -eq $newFoldersAdded[$absolutePath ] -and $absolutePath -notin $CUFolders.Path ){
                        ## there is a bug that causes an error if a folder name being created in a batch already exists at the top level so we workaround it
                        if($batchCreateFolders){
                            if ($FoldersToAddCount -ge $maxFolderBatchSize){
                                Write-Verbose "Generating a new add folder batch"
                                $FolderAddBatches.Add($FoldersToAddBatch)
                                $FoldersToAddCount = 0
                                $FoldersToAddBatch = New-CUBatchUpdate
                            }
                            Add-CUFolder -Name $pathElement -ParentPath $pathSoFar -Batch $FoldersToAddBatch
                        }else{if(!$Preview){$FoldersToAddBatchless.Add([pscustomobject]@{ PathElement = $pathElement ; PathSoFar = $pathSoFar })}}
						
                        $FoldersToAdd.Add("Add-CUFolder -Name `"$pathElement`" -ParentPath `"$pathSoFar`"")
                        $FoldersToAddCount++
                        $newFoldersAdded.Add($absolutePath , $ExtFolderPath)
                    }
                    $pathSoFar = $absolutePath
                }
            }
        }

        if($FoldersToAddBatchless -and $FoldersToAddBatchless.Count){
            [int]$folderDelayMilliseconds = 0
            if($FoldersToAddBatchless.Count -ge $batchCountWarning){
                [string]$logText = "$($FoldersToAddBatchless.Count) folders to add which could cause performance issues"

                if($force){
                    Write-CULog -Msg $logText -ShowConsole -Type W
                    $folderDelayMilliseconds = $folderCreateDelaySeconds * 1000
                }else{
                    $errorMessage = "$logText, aborting - use -force to override" 
                    Write-CULog -Msg $errorMessage -ShowConsole -Type E
                    Send-EmailAlert -SmtpServer $SmtpServer -from $emailFrom -to $emailTo -useSSL:$emailUseSSL -subject "Fatal error from ControlUp sync script `"$callingScript`" on $env:COMPUTERNAME" -body "$errorMessage"
                    $errorCount++
                    break
                }
            }
            foreach($item in $FoldersToAddBatchless){
                Write-Verbose -Message "Creating folder `"$($item.pathElement)`" in `"$($item.pathSoFar)`""
                if(!($folderCreated = Add-CUFolder -Name $item.pathElement -ParentPath $item.pathSoFar) -or $folderCreated -notmatch "^Folder '$($item.pathElement)' was added successfully$"){
                    Write-CULog -Msg "Failed to create folder `"$($item.pathElement)`" in `"$($item.pathSoFar)`" - $folderCreated" -ShowConsole -Type E
                }
                ## to help avoid central CU service becoming overwhelmed
                if($folderDelayMilliseconds -gt 0){
                    Start-Sleep -Milliseconds $folderDelayMilliseconds
                }
            }
        }

        if ($FoldersToAddCount -le $maxFolderBatchSize -and $FoldersToAddCount -ne 0){$FolderAddBatches.Add($FoldersToAddBatch)}

        # Build computers batch
        $ComputersAddBatches    = New-Object System.Collections.Generic.List[PSObject]
        $ComputersMoveBatches   = New-Object System.Collections.Generic.List[PSObject]
        $ComputersRemoveBatches = New-Object System.Collections.Generic.List[PSObject]
        $ComputersAddBatch      = New-CUBatchUpdate
        $ComputersMoveBatch     = New-CUBatchUpdate
        $ComputersRemoveBatch   = New-CUBatchUpdate
        $ComputersAddCount      = 0
        $ComputersMoveCount     = 0
        $ComputersRemoveCount   = 0

        $ExtComputers = $externalTree.Where{$_.Type -eq "Computer"}
        Write-CULog -Msg  "External Computers Total Count: $($ExtComputers.count)" -ShowConsole -Color Cyan

        #we'll output the statistics at the end -- also helps with debugging
        $MachinesToMove   = New-Object System.Collections.Generic.List[PSObject]
        $MachinesToAdd    = New-Object System.Collections.Generic.List[PSObject]
        $MachinesToRemove = New-Object System.Collections.Generic.List[PSObject]
        
        Write-CULog "Determining Computer Objects to Add or Move" -ShowConsole
        foreach ($ExtComputer in $ExtComputers){
	        if (($CUComputersHashTable.Contains("$($ExtComputer.Name)"))){
    	        if ("$($ExtComputer.FolderPath)\" -notlike "$($CUComputersHashTable[$($ExtComputer.name)].Path)\"){
                    if ($ComputersMoveCount -ge $maxBatchSize){  ## we will execute computer batch operations $maxBatchSize at a time
                        Write-Verbose "Generating a new computer move batch"
                        $ComputersMoveBatches.Add($ComputersMoveBatch)
                        $ComputersMoveCount = 0
                        $ComputersMoveBatch = New-CUBatchUpdate
                    }

        	        Move-CUComputer -Name $ExtComputer.Name -FolderPath "$($ExtComputer.FolderPath)" -Batch $ComputersMoveBatch
                    $MachinesToMove.Add("Move-CUComputer -Name $($ExtComputer.Name) -FolderPath `"$($ExtComputer.FolderPath)`"")
                    $ComputersMoveCount = $ComputersMoveCount+1
    	        }
	        }else{
                if ($ComputersAddCount -ge $maxBatchSize){
                        Write-Verbose "Generating a new add computer batch"
                        $ComputersAddBatches.Add($ComputersAddBatch)
                        $ComputersAddCount = 0
                        $ComputersAddBatch = New-CUBatchUpdate
                    }
                #write-host $($ExtComputer.FolderPath)
				#write-host "$($extComputer.Name) - $($extComputer.Domain) - $($extComputer.Name) - $($extComputer.DNSName) - $($extComputer.Site)"
    	        try{Add-CUComputer -Domain $ExtComputer.Domain -Name $ExtComputer.Name -DNSName $ExtComputer.DNSName -FolderPath "$($ExtComputer.FolderPath)" -siteId $extComputer.Site -Batch $ComputersAddBatch}
				catch{
                         Write-CULog "Error while attempting to run Add-CUComputer" -ShowConsole -Type E
                         Write-CULog "$($Error[0])"  -ShowConsole -Type E
                }

                $MachinesToAdd.Add("Add-CUComputer -Domain $($ExtComputer.Domain) -Name $($ExtComputer.Name) -DNSName $($ExtComputer.DNSName) -FolderPath `"$($ExtComputer.FolderPath)`" -SiteId $SiteIdGUID")

                $ComputersAddCount = $ComputersAddCount+1
	        }
        }
        if ($ComputersMoveCount -le $maxBatchSize -and $ComputersMoveCount -ne 0){ $ComputersMoveBatches.Add($ComputersMoveBatch) }
        if ($ComputersAddCount -le $maxBatchSize -and $ComputersAddCount -ne 0)   { $ComputersAddBatches.Add($ComputersAddBatch)   }

        $FoldersToRemoveBatches = New-Object System.Collections.Generic.List[PSObject]
        $FoldersToRemoveBatch   = New-CUBatchUpdate
        $FoldersToRemoveCount   = 0
        #we'll output the statistics at the end -- also helps with debugging
        $FoldersToRemove = New-Object System.Collections.Generic.List[PSObject]
        
        if ($Delete){
            Write-CULog "Determining Objects to be Removed" -ShowConsole
	        # Build batch for folders which are in ControlUp but not in the external source

            [string]$folderRegex = "^$([regex]::Escape($CURootFolder))\\.+"
            [array]$CUFolderSyncRoot = @($CUFolders.Where{ $_.Path -match $folderRegex })
            if($CUFolderSyncRoot -and $CUFolderSyncRoot.Count){
                Write-CULog "Root Target Path : $($CUFolderSyncRoot.Count) subfolders detected" -ShowConsole -Verbose
            }else{
                Write-CULog "Root Target Path : Only Target Folder Exists" -ShowConsole -Verbose
            }
            Write-CULog "Determining Folder Objects to be Removed" -ShowConsole
	        foreach ($CUFolder in $($CUFolderSyncRoot.Path)){
                $folderRegex = "$([regex]::Escape($CUFolder))"
                ## need to test if the whole path matches or it's a sub folder (so "Folder 1" won't match "Folder 12")
                if($ExtFolderPaths.Where({ $_.FolderPath -match "^$folderRegex$" -or $_.FolderPath -match "^$folderRegex\\" }).Count -eq 0 -and $CUFolder -ne $CURootFolder){
                ## can't use a simple -notin as path may be missing but there may be child paths of it - GRL
    	        ##if (($CUFolder -notin $ExtFolderPaths.FolderPath) -and ($CUFolder -ne $("$CURootFolder"))){ #prevents excluding the root folder
                    	$s = $CUFolder.split("\")
						if("$($s[0])\$($s[1])\$($s[2])".toLower() -in $global:eucDisconnected){$skip = $true}else{$skip = $false}
						#write-host "$skip - " + "$($s[0])\$($s[1])\$($s[2])"
						if ($Delete -and $CUFolder -and !$Skip){
							if ($FoldersToRemoveCount -ge $maxFolderBatchSize){  ## we will execute computer batch operations $maxBatchSize at a time
								Write-Verbose "Generating a new remove folder batch"
								$FoldersToRemoveBatches.Add($FoldersToRemoveBatch)
								$FoldersToRemoveCount = 0
								$FoldersToRemoveBatch = New-CUBatchUpdate
							}
							Remove-CUFolder -FolderPath "$CUFolder" -Force -Batch $FoldersToRemoveBatch
							$FoldersToRemove.Add("Remove-CUFolder -FolderPath `"$CUFolder`" -Force")
							$FoldersToRemoveCount = $FoldersToRemoveCount+1
						
					}
    	        }
	        }

            Write-CULog "Determining Computer Objects to be Removed" -ShowConsole
	        # Build batch for computers which are in ControlUp but not in the external source
            [string]$curootFolderAllLower = $CURootFolder.ToLower()

	        foreach ($CUComputer in $CUComputers.Where{$_.path -like "$CURootFolder*"}){
    	            if (!($ExtTreeHashTable[$CUComputer.name].name)){
						$s = $cucomputer.path.split("\")
						if("$($s[0])\$($s[1])\$($s[2])" -in $global:eucDisconnected){$skip = $true}else{$skip = $false}
                        if ($Delete -and !$skip){
                            if ($FoldersToRemoveCount -ge $maxFolderBatchSize){
                                Write-Verbose "Generating a new remove computer batch"
                                $ComputersRemoveBatches.Add($ComputersRemoveBatch)
                                $ComputersRemoveCount = 0
                                $ComputersRemoveBatch = New-CUBatchUpdate
                            }
        	                Remove-CUComputer -Name $($CUComputer.Name) -Force -Batch $ComputersRemoveBatch
                            $MachinesToRemove.Add("Remove-CUComputer -Name $($CUComputer.Name) -Force")
                            $ComputersRemoveCount = $ComputersRemoveCount+1
                        }
                    }
    	        ##}
	        }
        }
        if ($FoldersToRemoveCount -le $maxFolderBatchSize -and $FoldersToRemoveCount -ne 0){ $FoldersToRemoveBatches.Add($FoldersToRemoveBatch)   }
        if ($ComputersRemoveCount -le $maxBatchSize -and $ComputersRemoveCount -ne 0)       { $ComputersRemoveBatches.Add($ComputersRemoveBatch)   }

        #endregion

        Write-CULog -Msg "Folders to Add     : $($FoldersToAdd.Count)" -ShowConsole -Color White 
        Write-CULog -Msg "Folders to Add Batches     : $($FolderAddBatches.Count)" -ShowConsole -Color Gray -SubMsg
        if ($($FoldersToAdd.Count) -ge 25){
            foreach ($obj in $FoldersToAdd){Write-CULog -Msg "$obj" -SubMsg}
        }else{
            foreach ($obj in $FoldersToAdd){Write-CULog -Msg "$obj"} #-ShowConsole -Color Green -SubMsg}
        }

        Write-CULog -Msg "Folders to Remove  : $($FoldersToRemove.Count)" -ShowConsole -Color White
        Write-CULog -Msg "Folders to Remove Batches  : $($FoldersToRemoveBatches.Count)" -ShowConsole -Color Gray -SubMsg
        if ($($FoldersToRemove.Count) -ge 25){
            foreach ($obj in $FoldersToRemove){Write-CULog -Msg "$obj" -SubMsg}
        }else{
            foreach ($obj in $FoldersToRemove){Write-CULog -Msg "$obj"} #-ShowConsole -Color DarkYellow -SubMsg}
        }

        Write-CULog -Msg "Computers to Add   : $($MachinesToAdd.Count)" -ShowConsole -Color White
        Write-CULog -Msg "Computers to Add Batches   : $($ComputersAddBatches.Count)" -ShowConsole -Color Gray -SubMsg
        if ($($MachinesToAdd.Count) -ge 25){
            foreach ($obj in $MachinesToAdd){Write-CULog -Msg "$obj" -SubMsg} 
        }else{
            foreach ($obj in $MachinesToAdd){Write-CULog -Msg "$obj"} #-ShowConsole -Color Green -SubMsg}
        }

        Write-CULog -Msg "Computers to Move  : $($MachinesToMove.Count)" -ShowConsole -Color White
        Write-CULog -Msg "Computers to Move Batches  : $($ComputersMoveBatches.Count)" -ShowConsole -Color Gray -SubMsg
        if ($($MachinesToMove.Count) -ge 25){
            foreach ($obj in $MachinesToMove){Write-CULog -Msg "$obj" -SubMsg}
        }else{
            foreach ($obj in $MachinesToMove){Write-CULog -Msg "$obj"} #-ShowConsole -Color DarkYellow -SubMsg}
        }

        Write-CULog -Msg "Computers to Remove: $($MachinesToRemove.Count)" -ShowConsole -Color White
        Write-CULog -Msg "Computers to Remove Batches: $($ComputersRemoveBatches.Count)" -ShowConsole -Color Gray -SubMsg
        if ($($MachinesToRemove.Count -ge 25)){
            foreach ($obj in $MachinesToRemove){Write-CULog -Msg "$obj" -SubMsg}
        }else{
            foreach ($obj in $MachinesToRemove){Write-CULog -Msg "$obj"} #-ShowConsole -Color DarkYellow -SubMsg}
        }
            
        $endTime = Get-Date
		$bcutStart = get-date
        Write-CULog -Msg "Build-CUTree took: $($(New-TimeSpan -Start $startTime -End $endTime).Seconds) Seconds." -ShowConsole -Color White
        Write-CULog -Msg "Committing Changes:" -ShowConsole -Color DarkYellow
        if ($ComputersRemoveBatches.Count -gt 0){ $errorCount += Execute-PublishCUUpdates -BatchObject $ComputersRemoveBatches -Message "Executing Computer Object Removal" }
        if ($FoldersToRemoveBatches.Count -gt 0){ $errorCount += Execute-PublishCUUpdates -BatchObject $FoldersToRemoveBatches -Message "Executing Folder Object Removal"   }
        if ($FolderAddBatches.Count -gt 0 -and $batchCreateFolders){ $errorCount += Execute-PublishCUUpdates -BatchObject $FolderAddBatches -Message "Executing Folder Object Adds"            }
        if ($ComputersAddBatches.Count -gt 0){ $errorCount += Execute-PublishCUUpdates -BatchObject $ComputersAddBatches -Message "Executing Computer Object Adds"       }
        if ($ComputersMoveBatches.Count -gt 0){ $errorCount += Execute-PublishCUUpdates -BatchObject $ComputersMoveBatches -Message "Executing Computer Object Moves"     }
        Write-CULog -Msg "Returning $errorCount to caller"
		$bcutEnd = get-date
		Write-CULog -Msg "Committing Changes took: $($(New-TimeSpan -start $bcutStart -end $bcutEnd).Seconds) Seconds."
		Write-Host -Msg "Committing Changes took: $($(New-TimeSpan -start $bcutStart -end $bcutEnd).totalSeconds) Seconds."
        return $errorCount
}

############################
#####  End BuildCUTree  ####
############################

#Kicking off Build CUTree 
if($debug){Write-CULog -Msg "Starting BuildCUTree, this could also take some time" -ShowConsole}
else{Write-CULog -Msg "Starting BuildCUTree, this could also take some time"}

$BuildCUTreeParams = @{CURootFolder = $syncFolder}
$BuildCUTreeParams.Add("Force",$true)
if ($Preview){$BuildCUTreeParams.Add("Preview",$true)}
if ($Delete){$BuildCUTreeParams.Add("Delete",$true)}
if ($LogFile){$BuildCUTreeParams.Add("LogFile",$LogFile)}
if ($batchCreateFolders){$BuildCUTreeParams.Add("batchCreateFolders",$true)}


[int]$errorCount = Build-CUTree -ExternalTree $Environment @BuildCUTreeParams


