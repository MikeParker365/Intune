<#
.SYNOPSIS
Export policy settings from Intune from Settings Catalog Policies

.NOTES

Version 1.0, 14th June 2021
Revision History
---------------------------------------------------------------------
1.0 	- Initial release


Author/Copyright:    Mike Parker - All rights reserved
Email/Blog/Twitter:  mike@mikeparker365.co.uk | www.mikeparker365.co.uk | @MikeParker365

THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.

.DESCRIPTION
   Use this script to export all or selected policies from Microsoft Intune that have been created using the Settings Catalog.

.LINK
http://www.mikeparker365.co.uk

.PARAMETER PolicyName
   The name of the policy you would like to export
.EXAMPLE
   Export-SettingsCatalogPolicies -PolicyName 'My Test Policy'

.PARAMETER ExportPath
   A destination folder path to export the policies 
.EXAMPLE
   Export-SettingsCatalogPolicies -ExportPath 'C:\Folder\Target\Outputs\'

#>

[CmdletBinding()]
param (

	[Parameter( Mandatory = $false )]
	[string]$PolicyName,
	
	[Parameter( Mandatory = $false)]
	[string]$ExportPath

)

$scriptVersion = "0.0"

############################################################################
# Functions Start 
############################################################################

#Retrieves the path the script has been run from
function Get-ScriptPath {
 Split-Path $myInvocation.ScriptName
}

#This function is used to write the log file
Function Write-Logfile() {
 param( $logentry )
	$timestamp = Get-Date -DisplayHint Time
	"$timestamp $logentry" | Out-File $logfile -Append
	Write-Host $logentry
}

#This function enables you to locate files using the file explorer
function Get-FileName($initialDirectory) { 
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
	Out-Null

	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $initialDirectory
	$OpenFileDialog.filter = "All files (*.*)| *.*"
	$OpenFileDialog.ShowDialog() | Out-Null
	$OpenFileDialog.filename
} #end function Get-FileName

function Get-AuthToken {

	<#
    .SYNOPSIS
    This function is used to authenticate with the Graph API REST interface
    .DESCRIPTION
    The function authenticate with the Graph API Interface with the tenant name
    .EXAMPLE
    Get-AuthToken
    Authenticates you with the Graph API interface
    .NOTES
    NAME: Get-AuthToken
    #>
    
	[cmdletbinding()]
    
	param
	(
		[Parameter(Mandatory = $true)]
		$User
	)
    
	$userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User
    
	$tenant = $userUpn.Host
    
	Write-Host "Checking for AzureAD module..."
    
	$AadModule = Get-Module -Name "AzureAD" -ListAvailable
    
	if ($AadModule -eq $null) {
    
		Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
		$AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    
	}
    
	if ($AadModule -eq $null) {
		write-host
		write-host "AzureAD Powershell module not installed..." -f Red
		write-host "Install by running 'Install-Module AzureAD' or 'Install-Module AzureADPreview' from an elevated PowerShell prompt" -f Yellow
		write-host "Script can't continue..." -f Red
		write-host
		exit
	}
    
	# Getting path to ActiveDirectory Assemblies
	# If the module count is greater than 1 find the latest version
    
	if ($AadModule.count -gt 1) {
    
		$Latest_Version = ($AadModule | select version | Sort-Object)[-1]
    
		$aadModule = $AadModule | ? { $_.version -eq $Latest_Version.version }
    
		# Checking if there are multiple versions of the same module found
    
		if ($AadModule.count -gt 1) {
    
			$aadModule = $AadModule | select -Unique
    
		}
    
		$adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
		$adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    
	}
    
	else {
    
		$adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
		$adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"
    
	}
    
	[System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    
	[System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    
	$clientId = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547"
    
	$redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    
	$resourceAppIdURI = "https://graph.microsoft.com"
    
	$authority = "https://login.microsoftonline.com/$Tenant"
    
	try {
    
		$authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    
		# https://msdn.microsoft.com/en-us/library/azure/microsoft.identitymodel.clients.activedirectory.promptbehavior.aspx
		# Change the prompt behaviour to force credentials each time: Auto, Always, Never, RefreshSession
    
		$platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
    
		$userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
    
		$authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $redirectUri, $platformParameters, $userId).Result
    
		# If the accesstoken is valid then create the authentication header
    
		if ($authResult.AccessToken) {
    
			# Creating header for Authorization token
    
			$authHeader = @{
				'Content-Type'  = 'application/json'
				'Authorization' = "Bearer " + $authResult.AccessToken
				'ExpiresOn'     = $authResult.ExpiresOn
			}
    
			return $authHeader
    
		}
    
		else {
    
			Write-Host
			Write-Host "Authorization Access Token is null, please re-run authentication..." -ForegroundColor Red
			Write-Host
			break
    
		}
    
	}
    
	catch {
    
		write-host $_.Exception.Message -f Red
		write-host $_.Exception.ItemName -f Red
		write-host
		break
    
	}
    
}

Function Export-JSONData() {

	<#
        .SYNOPSIS
        This function is used to export JSON data returned from Graph
        .DESCRIPTION
        This function is used to export JSON data returned from Graph
        .EXAMPLE
        Export-JSONData -JSON $JSON
        Export the JSON inputted on the function
        .NOTES
        NAME: Export-JSONData
        #>
        
	param (
        
		$JSON,
		$ExportPath,
		$ExportName
        
	)
        
	try {
        
		if ($JSON -eq "" -or $JSON -eq $null) {
        
			write-host "No JSON specified, please specify valid JSON..." -f Red
        
		}
        
		elseif (!$ExportPath) {
        
			write-host "No export path parameter set, please provide a path to export the file" -f Red
        
		}
        
		elseif (!(Test-Path $ExportPath)) {
        
			write-host "$ExportPath doesn't exist, can't export JSON Data" -f Red
        
		}
        
		else {
        
			$JSON1 = ConvertTo-Json $JSON -Depth 5
        
			$JSON_Convert = $JSON1 | ConvertFrom-Json
        
			$displayName = $ExportName
        
			# Updating display name to follow file naming conventions - https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247%28v=vs.85%29.aspx
			$DisplayName = $DisplayName -replace '\<|\>|:|"|/|\\|\||\?|\*', "_"
        
			$FileName_JSON = "$DisplayName" + "_" + $(get-date -f dd-MM-yyyy-H-mm-ss) + ".json"
        
			write-host "Export Path:" "$ExportPath"
        
			$JSON1 | Set-Content -LiteralPath "$ExportPath\$FileName_JSON"
			write-host "JSON created in $ExportPath\$FileName_JSON..." -f cyan
                    
		}
        
	}
        
	catch {
        
		$_.Exception
        
	}
        
}


############################################################################
# Functions end 
############################################################################

############################################################################
# Variables Start 
############################################################################

$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$logfile = "$myDir\Add-SMTPAddresses.log"

$start = Get-Date

############################################################################
# Variables End
############################################################################

############################################################################
# Script start   
############################################################################

Write-Logfile "Script started at $start";
Write-Logfile "Running script version $scriptVersion"

## WRITE YOUR SCRIPT HERE

#region Authentication

write-host

# Checking if authToken exists before running authentication
if ($global:authToken) {

	# Setting DateTime to Universal time to work in all timezones
	$DateTime = (Get-Date).ToUniversalTime()

	# If the authToken exists checking when it expires
	$TokenExpires = ($authToken.ExpiresOn.datetime - $DateTime).Minutes

	if ($TokenExpires -le 0) {

		write-host "Authentication Token expired" $TokenExpires "minutes ago" -ForegroundColor Yellow
		write-host

		# Defining User Principal Name if not present

		if ($User -eq $null -or $User -eq "") {

			$User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
			Write-Host

		}

		$global:authToken = Get-AuthToken -User $User

	}
}

# Authentication doesn't exist, calling Get-AuthToken function

else {

	if ($User -eq $null -or $User -eq "") {

		$User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
		Write-Host

	}

	# Getting the authorization token
	$global:authToken = Get-AuthToken -User $User

}

#endregion Authentication

#region Get ConfigurationPolicies

$baseUri = "https://graph.microsoft.com/beta/deviceManagement"
$uri = "$baseUri/configurationPolicies"
$restParam = @{
	Method      = 'Get'
	Uri         = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
	Headers     = $authHeader
	ContentType = 'Application/json'
}



$configPolicies = Invoke-RestMethod -Uri $uri -Headers $authToken -Method Get -ContentType 'Application/Json'

if ($policyName -ne "") {

	$results = @()
	$policyID = ($configPolicies.Value | Where-Object { $_.Name -eq $policyName }).id

	$configPolicySettings = Invoke-RestMethod -Uri "$baseUri/configurationPolicies('$policyId')/settings" -Headers $authToken -ContentType 'Application/Json' -Method Get
	$results += $configPolicySettings.value
	do {

		$configPolicySettings = Invoke-RestMethod -Uri $configPolicySettings.'@odata.nextLink' -Headers $authToken -ContentType 'Application/Json' -Method Get
		$results += $configPolicySettings.Value
		$null

	} until ($configpolicySettings.'@odata.nextLink' -eq $null)

	If ($null -eq $ExportPath) {

		[string]$ExportPath = $myDir
	}

	# Create folder if does not exist
	if (!(Test-Path -Path $ExportPath)) {
		$paramNewItem = @{
			Path     = $ExportPath
			ItemType = 'Directory'
			Force    = $true
		}

		New-Item @paramNewItem
	}
	$null
	Export-JSONData -JSON $results -ExportPath "$ExportPath" -ExportName $PolicyName

}

else {
	
	Foreach ($Policy in $configPolicies.value) {

		$results = @()
	
		$null
		$policyID = ($Policy).id
		$PolicyName = ($Policy).name

		$null

		$configPolicySettings = Invoke-RestMethod -Uri "$baseUri/configurationPolicies('$policyId')/settings" -Headers $authToken -ContentType 'Application/Json' -Method Get
		$results += $configPolicySettings.value

		if ($null -ne $configpolicySettings.'@odata.nextLink') {
			
		
			do {
	
				$configPolicySettings = Invoke-RestMethod -Uri $configPolicySettings.'@odata.nextLink' -Headers $authToken -ContentType 'Application/Json' -Method Get
				$results += $configPolicySettings.Value
				$null
	
			} until ($configpolicySettings.'@odata.nextLink' -eq $null)
		}
		If ($null -eq $ExportPath) {
	
			[string]$ExportPath = $myDir
		}
	
		# Create folder if does not exist
		if (!(Test-Path -Path $ExportPath)) {
			$paramNewItem = @{
				Path     = $ExportPath
				ItemType = 'Directory'
				Force    = $true
			}
	
			New-Item @paramNewItem
		}
		$null
		Export-JSONData -JSON $results -ExportPath "$ExportPath" -ExportName "$policyName"
	}
	

}
$null
#endRegion

##

Write-Logfile "------------Processing Ended---------------------"
$end = Get-Date;
Write-Logfile "Script ended at $end";
$diff = New-TimeSpan -Start $start -End $end
Write-Logfile "Time taken $($diff.Hours)h : $($diff.Minutes)m : $($diff.Seconds)s ";

############################################################################
# Script end   
############################################################################