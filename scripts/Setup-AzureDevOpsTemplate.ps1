<#
.SYNOPSIS
Performs installation of Azure Devops Pipeline Monitoring Dataflow 1.0.
.DESCRIPTION
    Description: This script:
        1) Upload sample Power BI Dataflow to the Power BI workspace
        2) Generates a PAT Token to be used in setting up the dataflow
        Dependencies:
            1) Power BI Powershell installed
            2) ImportModel.ps1
            3) Az.Accounts
         
    Author: John Kerski
.INPUTS
None.
.OUTPUTS
None.
.EXAMPLE
PS> .\Setup-AzureDevOpsTemplate.ps1
#>
### GLOBAL VARIABLES
$Branch = "development"
$DevOpsURLKeyword = "\|DEVOPS_URL\|"
$ProjectNameKeyword = "\|PROJECT_NAME\|"
$ProjectName = $null
$ADOSiteURL = $null
$DF_URL = ""
$DFOutput = ".\Azure DevOps Pipeline Monitoring.json"
$DFUtilsURI = "https://raw.githubusercontent.com/kerski/pbi-dataops-monitoring/$($Branch)/scripts/DFUtils.psm1"
$GraphURI = "https://raw.githubusercontent.com/kerski/pbi-dataops-monitoring/$($Branch)/scripts/Graph.psm1"
$ImportURI = "https://raw.githubusercontent.com/kerski/pbi-dataops-monitoring/$($Branch)/scripts/ImportModel.ps1"
$TemplateURI = "https://raw.githubusercontent.com/kerski/pbi-dataops-monitoring/$($Branch)/Azure%20DevOps%20Pipeline%20Monitoring%20Template.json"
$FileLocation = "./Azure DevOps Pipeline Monitoring Template.json"
### Install dependencies
#Install Powershell Modules if Needed
if (Get-Module -ListAvailable -Name "MicrosoftPowerBIMgmt") {
    Write-Host "MicrosoftPowerBIMgmt installed moving forward"
} else {
    #Install Power BI Module
    Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -AllowClobber -Force
}

if (Get-Module -ListAvailable -Name "Az.Accounts") {
    Write-Host "Az.Accounts installed moving forward"
} else {
    #Install Az.Accounts
    Install-Module -Name Az.Accounts -Scope CurrentUser -AllowClobber -Force
}
# Set Execution Policy so we can handle Az.Accounts loading
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser


### UPDATE VARIABLES HERE thru Read-Host
# Set Workspace Name
$WorkspaceName = Read-Host "Please enter the name of the Power BI Workspace"
# Paste the URL of the SharePoint list
$Location = Read-Host "Please paste the URL of the Azure DevOps Project."

$SiteResults = ($Location -Split '/')
if ($SiteResults.Count -lt 5)
{
    Throw "We could not extract the project name from the URL $($Location)."
} else {
    $ADOSiteURL = $SiteResults[0..3] -join "/"
    $OrgName = $SiteResults[3]
    $ProjectName = $SiteResults[4]
} #end if

Write-Host -ForegroundColor Cyan "Updating the Power BI dataflow template."
# Download Dependencies
Write-Host -ForegroundColor Cyan "Downloading scripts and dataflow template from GitHub."
#Download scripts for Graph, DFUtils, and Import-Module.ps1
Invoke-WebRequest -Uri $DFUtilsURI -OutFile "./DFUtils.psm1"
Invoke-WebRequest -Uri $GraphURI -OutFile "./Graph.psm1"
Invoke-WebRequest -Uri $ImportURI -OutFile "./ImportModel.ps1"
#Download Template
Invoke-WebRequest -Uri $TemplateURI -OutFile $FileLocation

(Get-Content $FileLocation) -replace $DevOpsURLKeyword, $ADOSiteURL | Set-Content $DFOutput -Force
(Get-Content $DFOutput) -replace $ProjectNameKeyword, $ProjectName | Set-Content $DFOutput -Force

#Login into Power BI to Get Workspace Information
Login-PowerBI

$WS = Get-PowerBIWorkspace -Name $WorkspaceName

if(!$WS){
    Throw "Unable to retrieve the workspace information for the workspace provided: $($WorkspaceName)"
}

#Upload Bronze Data Flow
.\ImportModel.ps1 -Workspace $WS.name -File $DFOutput

### Now Setup Azure DevOps
Write-Host -ForegroundColor Cyan "Generating PAT Token scoped to Builds and Releases"

<# Thanks to @autosysops for this article 
   which helped me generate PAT tokens
   more consistently.

   https://autosysops.com/blog/automatic-pat-renewal-for-azure-devops 
#>

   #Get the Azure Ad AccessToken
$null = Connect-AzAccount
$ADToken = Get-AzAccessToken

#Create the authentication header for the DevOps API
$Headers = @{
    "Content-Type" = "application/json"
    Authorization = "Bearer $($ADToken.Token)"
}
      
#Retrieve all tokens
$Url = "https://vssps.dev.azure.com/$($OrgName)/_apis/tokens/pats?api-version=7.1-preview.1"

# Set Valid To expiration
$Today = Get-Date
$FutureDate = $Today.AddDays(363).ToUniversalTime()
$FutureDateISO = $FutureDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

# Generate Guid
$PATGuid = New-Guid

# Setup payload to create token
$Body = @{
  displayName = "Azure DevOps Monitoring - DataOps ($($PATGuid.Guid))"
  scope = "vso.build vso.release"
  validTo = "$($FutureDateISO)"
  allOrgs = "false"
}

$JsonBody = $Body | ConvertTo-Json 

# Issue creation request
$PATToken = Invoke-RestMethod -Uri $Url -Headers $Headers -Method POST -Body $JsonBody -Verbose

if(!$PATToken)
{
    Throw "Unable to generate PAT Token"
}

# Success messages
Write-Host -ForegroundColor Green "Dataflow Template successfully uploaded to $($WS.name)"
Write-Host -ForegroundColor Green "Please save this PAT Token for use in setting the credentials in the dataflow: $($PATToken.patToken.token)"