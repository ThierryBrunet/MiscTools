# CloneToEscrowZip.ps1

<#
Author : Thierry Brunet de Courssou
Company: Connect Develop - Brisbane - Australia
Date   : September 2019
Last   : 08 Dec 2020
Notes  : to be executed line by line or by selected block of lines
AzDO   : yes - https://dev.azure.com/ConnectExpress/ConnectExpress/_git/DevOps?path=%2FEscrow%2FCloneToEscrowZip.ps1

Purpose: 
--------
- Cloning:

    from
        . AzDoGit projects
        . GitHub projects,
        . Builds definitions
        . Releases definitions
        . Variablegroups
    to 
        . Azure Storage cx-global ZIP file
        . Local PC disk ZIP file

Optional:
---------
- 

Warning:
--------
- 

Notes :
-------
- the "clone-clone" term is used instead of "backup-restore" as this better captures the intent of cloning everything to a different environment that may be run in parallel
- The artifacts are cloned to the Escrow Zip file unmodified. This way they may be restored to the original Team Project in case of recovery needed
- Although artifacts names are identical in  origin team project and target escrow project, associated GUIDs are different
- Upon cloning from the Escrow Zip file, GUIDs used for linking repos/builds/releases/variable-groups will need to be matched by entity name and replaced accordingly


Pre-requisites:
---------------
- Windows 10 PC (AzFileShare local mount not working on Mac )

- Powershell 7.1

- Visual Studo Code (latest) with Powershell Extension

- Azure Active Directory (AAD) account not necessary as AzDO PAT is used

- Latest Powershell modules: run LatestAZ function (Step A.1)


TODO:
-----
- see TODOs in below code
TODO A.2 -- change PAT

INFO
----
https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-5.1

#>

# >>>>>>>>>>>>>>>>
# >>> PHASE A >>>> -- [MANDATORY] Initialization
# >>>>>>>>>>>>>>>>
function a_Init {}
if ($true) {
    ################
    ''### Step 1 ### -- Latest Powershell Modules
    ################
    function a.1_LatestAz {
        # Install/Update listed modules
        # -----------------------------

        # Step 1 - Selected desired modules
        # ---------------------------------
        $ModuleNames = @()
        $ModuleNames += "Az"
        $ModuleNames += "Az.Resources"

        # Step 2 - Install/Upgrade modules
        # --------------------------------
        if ($true) {
            $ModuleNames | ForEach-Object {
                $ModuleName = $_
                $r = Find-Module -Name $ModuleName
                $latestAzResourcesVersion = $r.Version

                # Install module if not already installed
                $r = ""
                $r = Get-InstalledModule -Name $ModuleName -AllVersions -ErrorAction SilentlyContinue
                if (($r.count -eq 0 ) -or ($r -eq "") ) {
                    Write-Host "$ModuleName not found for this user; Installing $ModuleName for all users"
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                    Install-Module -Name $ModuleName -Scope allusers -Force
                }
                else {
                    Write-Host "Found $ModuleName version"  $r.Version 
                }

                # Upgrade module if not latest version
                $r = Get-InstalledModule -Name $ModuleName -AllVersions
                # $r
                if ($r.version -ne $latestAzResourcesVersion) {
                    Update-Module -Name $ModuleName -Force 
                }

                # Remove old module versions
                $r = Get-InstalledModule -Name $ModuleName -AllVersions
                $r2 = $r | Where-Object { $_.version -ne $latestAzResourcesVersion }
                $r2 | Uninstall-Module

                # Verification
                Get-InstalledModule -Name $ModuleName -AllVersions
            }
            Write-Host "`n----> Install/Upgrade modules -- DONE !!!!" -ForegroundColor Yellow
        }

        # Step 3 - Verify installed modules
        # ---------------------------------
        if ($true) {
            Write-Host "`n`n----> Verify installed modules" -ForegroundColor Blue
            $ModuleNames | ForEach-Object {
                $ModuleName = $_
                $ModuleIsInstalled = Get-InstalledModule -Name $ModuleName -AllVersions -ErrorAction Ignore
                if ($ModuleIsInstalled) {
                    $ModuleIsInstalled
                }
                else { Write-Host " -- Module $ModuleName is not installed" }
            }
        }
    }
    LatestAz  # RUN IT !!! - will install/update latest required PS modules

    ################
    ''### Step 2 ### -- Get AzDo credentials
    ################
    if ($true) {
        $vstsAccountName = 'ConnectExpress'
        $vstsTeamProjectName = 'ConnectExpress'
        # $vstsTeamProjectName = 'Escrow'
        $vstsPAT = 'dtqal2bkfvq32ywctz3evq7sgzkrlulshiexi2hlevhy2v76l5tq'  # PAT (Thierry's)
        # TODO A.2 -- change PAT
        $User = ""

        # Base64-encodes the Personal Access Token (PAT) appropriately
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $vstsPAT)))
        $vstsAuthHeader = @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
    }

    ################
    ''### Step 3 ### -- Initialize AzureStorage
    ################
    if ($true) { 
        # Azure Storage FileShare (Windows only)
        # -----------------------
        $AzStoreShare = "cxglobal"
        $AzStoreShareKey = 'L/O44vTn842/6p3k7VJPwxm6WZBGaIQb9li6oD2aRsB15LB3tMViMBceEcTeApC/aL+2SlCxvg5R2ZnNDhLq/w=='
        $AzStoreFolder = "\\$AzStoreShare.file.core.windows.net\escrow"

        cmdkey /add:$AzStoreShare.file.core.windows.net /user:AZURE\$AzStoreShare  /pass:$AzStoreShareKey
        Start-Sleep 10
        Get-ChildItem $AzStoreFolder

        $Date = Get-Date -UFormat "(%d-%m-%Y)"
        $AzStorePathOut = $AzStoreFolder + "\" + $Date

        New-Item -Path $AzStorePathOut -ItemType directory -Force
        Set-Location $AzStorePathOut
        Get-ChildItem $AzStorePathOut

    }

    ################
    ''### Step 4 ### -- Initialize local disk folder
    ################
    if ($true) { 
        $Date = Get-Date -UFormat "(%d-%m-%Y)"
        $LocalDiskPathOut = "c:\Temp\EscrowZipOut\$Date"
        New-Item -Path $LocalDiskPathOut -ItemType directory -Force
        Set-Location $LocalDiskPathOut 
        Get-ChildItem
    }
}

#>>>>>>>>>>>>>>>>
''#>> PHASE B >>> -- [MANDATORY] CloneOut GitRepos
#>>>>>>>>>>>>>>>>
function b_GitRepos {}
if ($true) {
    ################
    ''### Step 1 ### -- [MANDATORY] Clone git repos to local PC
    ################
    if ($true) {

        # Important: Review the list of Git Repos and modify according to the current projects status

        # AzDO git
        # --------
        $AzDoProjects = @()
        $AzDoProjects += "DevOpsMinions"
        $AzDoProjects += "DevOps"
        $AzDoProjects += "Auth0"
        $AzDoProjects += "cx-platform-services-infra"
        $AzDoProjects += "ca-platform-services-infra"

        $AzDoProjects.Count

        foreach ($project in $AzDoProjects) { 
            git clone "https://ConnectExpress@dev.azure.com/ConnectExpress/ConnectExpress/_git/$project" $LocalDiskPathOut/Git/$project
        }

        # GitHub - Connect-Develop -- https://github.com/Connect-Develop
        # ------
        $GitHubProjects = @()
        $GitHubProjects += "Conversations"
        $GitHubProjects += "cx-alinta-energy-integration-svc"
        $GitHubProjects += "cx-signup-svc"
        $GitHubProjects += "the-builders-platform"
        $GitHubProjects += "the-movers-platform"
        $GitHubProjects += "au-movers-new-account-invitations"
        $GitHubProjects += "au-movers-realestate-dashboard"
        $GitHubProjects += "au-switchboard"
        $GitHubProjects += "connectexpress-com-au"
        $GitHubProjects += "cx-signup-ui"
        $GitHubProjects += "cx-data-insights"
        $GitHubProjects += "cx-property-me-integration-svc"
        $GitHubProjects += "cx-affinity-svc"
        $GitHubProjects += "cx-affinity-pages"
        $GitHubProjects += "connect-ui"
        $GitHubProjects += "signup-svc-ui-tests"
        $GitHubProjects += "cx-dotnet-new-templates"
        $GitHubProjects += "connectassist-landing-page"
        $GitHubProjects += "cx-communications"
        $GitHubProjects += "mdl-react"
        $GitHubProjects += "Connect-Assist"
        # $GitHubProjects += "Connect-Assist2"
        $GitHubProjects += "ConnectAssist2.0"
        $GitHubProjects += "ConnectExpressValidators"
        $GitHubProjects += "cd-product-links"
        $GitHubProjects += "connectdevelop.com"
        $GitHubProjects += "Infrastructure"
        $GitHubProjects += "signup-svc-ui-tests"
        $GitHubProjects += "FSharp-Style-Guide"
        $GitHubProjects += "cd-product-links"
        $GitHubProjects += "Cognito"
        $GitHubProjects += "cx-communications-service"
        $GitHubProjects += "movers-login"
        $GitHubProjects += "FSharp-Style-Guide"
        $GitHubProjects += "IdentityServer-Spike"
        # $GitHubProjects += ""
        # $GitHubProjects += ""
        # $GitHubProjects += ""
        # $GitHubProjects += ""
        # $GitHubProjects += ""

        # $GitHubProjects += "au-movers-realestate-agent-onboarding"
        # $GitHubProjects += "movers-login"
        # $GitHubProjects += "cx-core-svc"
        # $GitHubProjects += "cx-eventstore-up"
        # $GitHubProjects += "cx-communications-svc"

        $GitHubProjects.Count

        foreach ($project in $GitHubProjects) { 
            git clone "https://github.com/Connect-Develop/$project.git"  $LocalDiskPathOut/Git/$project
        }

        # Verification
        Set-Location $LocalDiskPathOut/Git
        Get-ChildItem

    } # Run the entire step
}

#>>>>>>>>>>>>>>>>
''#>> PHASE C >>> -- CloneOut Build Definitions
#>>>>>>>>>>>>>>>>
function c_BuildDef {}
if ($true) {
    ################
    ''### Step 1 ### -- [MANDATORY] List Build Definitions
    ################
    if ($true) {

        # Important: Review the list of Buid Definitions and modify according to the current projects status

        # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/list?view=azure-devops-rest-5.1
        # List Build Definitions: GET https://dev.azure.com/ { organization }/ { project }/_apis/build/definitions?api-version=5.0-preview.7

        $Uri = "https://dev.azure.com/$vstsAccountName/$vstsTeamProjectName/_apis/build/definitions/?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
        $r
        $r.value
        $r.value.name.count
        $r.value.name
        <# --- Example ---
        KestrelMinions
        the-builders-platform
        au-switchboard (Builders)
        the-movers-platform
        au-movers-realestate-dashboard
        au-movers-new-account-invitations
        au-movers-realestate-agent-onboarding
        connectexpress-com-au
        Conversations Services
        Auth0_Deploy
        cx-signup-svc
        cx-alinta-energy-integration-svc
        version-two
        cx-validators
        cx-signup-ui
        ConnectDevelop.NET
        connect-ui
        ConnectExpressValidators
        switchboard-ui
        mdl-react
        Cx-Data-Insights
        Cx-EventStore-Up-CI
        KestrelMinionsYaml
        signup-svc-ui-test
        cx-core-svc
        property-me-integration
        cx-FuncPwshAutomation
        cx-property-me-integration-svc (YAML)
        cx-CostReduction
        cx-SynchonizedSnapshots (no stages)
        cx-DataInsights-Pwsh
        Cx Dotnet New Templates
        cx-affinity-pages
        communications
        cx-affinity-svc
        movers-login
        Connect Assist Application
        cx-SmartAlerts-AzF
        ewr-status
        #>

        $r.value.id
        <# --- Example ---
        2
        8
        10
        29
        30
        31
        32
        33
        36
        41
        42
        45
        46
        47
        48
        50
        51
        52
        53
        54
        55
        57
        58
        60
        104
        105
        109
        110
        111
        113
        114
        115
        116
        117
        119
        120
        125
        127
        129
        #>

        # Make your own buildId list or take all
        # $buildIds = @()
        # $buildIds += "2"
        # $buildIds += "8"
        # $buildIds += "10"
        # $buildIds += "29"
        # $buildIds += "30"
        # $buildIds += "31"
        # $buildIds += "32"
        # $buildIds += "33"
        # $buildIds += "36"
        # $buildIds += "39"
        # $buildIds += "41"
        # $buildIds += "42"
        # $buildIds += "45"
        # $buildIds += "46"
        # $buildIds += "47"
        # $buildIds += "48"
        # $buildIds += "50"
        # $buildIds += "51"
        # $buildIds += "52"
        # $buildIds += "53"
        # $buildIds += "54"
        # $buildIds += "55"
        # $buildIds += "57"
        # $buildIds += "58"
        # $buildIds += "60"
        # $buildIds += "104"
        # $buildIds += "105"
        # $buildIds += "109"
        # $buildIds += "110"
        # $buildIds += "111"
        # $buildIds += "113"
        # $buildIds += "114"
        # $buildIds += "115"
        # $buildIds += "116"
        # $buildIds += "117"
        # $buildIds += "119"
        # $buildIds += "120"
        # $buildIds += "125"
        # $buildIds += "127"
        # $buildIds += "129"
        # [MANDATORY] If Escrow
        $buildIds = $r.value.id  # take all BuildIds; will be used in next step
    }

    ################
    ''### Step 2 ### -- [MANDATORY] Export build definitions
    ################
    if ($true) {
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/get?view=azure-devops-rest-5.1
        # Get specific Build def: GET https://dev.azure.com/ { organization }/ { project }/_apis/build/definitions/ { definitionId }?api-version=5.1

        # Prepare disk folder
        New-Item -Path $LocalDiskPathOut/BuildDefinitions -ItemType directory -Force
        Set-Location $LocalDiskPathOut/BuildDefinitions
        Get-ChildItem

        # Get all the build definitions as json
        $Builds2Export = @()
        $buildIds | ForEach-Object {
            $buildId = $_
            $Uri = "https://dev.azure.com/$vstsAccountName/$vstsTeamProjectName/_apis/build/definitions/" + $buildId + "?api-version=5.1"
            # $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
            $r = Invoke-WebRequest -Method GET -Uri $Uri -Headers $vstsAuthHeader  # Get the complete JSON directly
            $Builds2Export += $r
            $x = $r.content | ConvertFrom-Json
            $filePath = "./" + $x.name + ".json"
            $r.content | Out-File -FilePath  $filePath
        }
        $Builds2Export.Count

        # Bulk output of all build definitions to a single file on disk
        # -------------------------------------------------------------
        # $Builds2Export | ConvertTo-Json -Depth 20 | Out-File -FilePath ./BuildDefinitionsExported.json
        $Builds2Export.content | Out-File -FilePath ./BuildDefinitionsExported.json


        # Test re-reading the JSON file
        $verif = Get-Content  -Path ./BuildDefinitionsExported.json
        $verified = $verif | ConvertFrom-Json
        $verified.count
        $verified.name
    }
}

#>>>>>>>>>>>>>>>>
''#>> PHASE D >>> -- CloneOut Release Definitions
#>>>>>>>>>>>>>>>>
function d_RealeaseDef {}
if ($true) {
    ################
    ''### Step 1 ### -- [MANDATORY] List release definitions
    ################
    if ($true) {

        # Important: Review the list of Release Definitions and modify according to the current projects status

        # List and Get release definition
        # GET https://vsrm.dev.azure.com/ { organization }/ { project }/_apis/release/definitions?api-version=5.1
        # GET https://vsrm.dev.azure.com/ { organization }/ { project }/_apis/release/definitions/ { definitionId }?api-version=5.1

        # [MANDATORY] List all release definitions
        # ----------------------------
        $Uri = "https://vsrm.dev.azure.com/$vstsAccountName/$vstsTeamProjectName/_apis/release/definitions?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
        $r
        $r.count
        $r.value
        $r.value.id
        $r.value.name
        $ReleaseDefinitionIds = $r.value.id  # Take all the release def


        # [OPTIONAL] Search release definitions
        # -------------------------------------
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/release/definitions/list?view=azure-devops-rest-5.1
        # GET https://vsrm.dev.azure.com/ { organization }/ { project }/_apis/release/definitions?searchText= { searchText }&$expand = { $expand }&artifactType= { artifactType }&artifactSourceId= { artifactSourceId }&$top = { $top }&continuationToken= { continuationToken }&queryOrder= { queryOrder }&path= { path }&isExactNameMatch= { isExactNameMatch }&tagFilter= { tagFilter }&propertyFilters= { propertyFilters }&definitionIdFilter= { definitionIdFilter }&isDeleted= { isDeleted }&searchTextContainsFolderName= { searchTextContainsFolderName }&api-version=5.1
        $searchFilter = "minions"
        $searchFilter = "platform"
        $searchFilter = "alinta"
        $searchFilter = "cx-platform-services-infra"
        
        $Uri = "https://vsrm.dev.azure.com/" + $vstsAccountName + "/" + $vstsTeamProjectName + '/_apis/release/definitions?searchText=' + $searchFilter + '&api-version=5.1'
        $r1 = Invoke-RestMethod -Method Get -ContentType application/json -Uri $Uri -Headers $vstsAuthHeader
        $r1
        $r1.count
        $r1.value
        $r1.value.Id

        # [OPTIONAL] Get a selected one of the Release definitions
        # --------------------------------------------------------
        $ReleaseDefinitionId = 49 # Minions
        $ReleaseDefinitionId = 36 # cx-alinta-energy-integration-svc
        $ReleaseDefinitionId = 45 # cx-platform-services-infra

        $Uri = "https://vsrm.dev.azure.com/" + $vstsAccountName + '/' + $vstsTeamProjectName + '/_apis/release/definitions/' + $ReleaseDefinitionId + '?api-version=5.1'
        $r2 = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
        $r2
        $r2.variables
        $r2.value
    }

    ################
    ''### Step 2 ### -- [MANDATORY] Export the Release definitions by ID
    ################
    if ($true) {

        # Intialise Disk
        New-Item -Path $LocalDiskPathOut/ReleaseDefinitions -ItemType directory -Force
        Set-Location $LocalDiskPathOut/ReleaseDefinitions
        Get-ChildItem

        # Get all the Release definitions by ID
        # -------------------------------------}
        # GET https://vsrm.dev.azure.com/ { organization }/ { project }/_apis/release/definitions/ { definitionId }?api-version=5.1

        $Releases2Export = @()
        $Releases2ExportIds = $ReleaseDefinitionIds  # TODO D.2 -- filter/dump those not needed

        # $ReleaseDefinitionIds obtained from List of Release Definitions
        $Releases2ExportIds | ForEach-Object {
            $ReleaseDefinitionId = $_
            $Uri = "https://vsrm.dev.azure.com/" + $vstsAccountName + '/' + $vstsTeamProjectName + '/_apis/release/definitions/' + $ReleaseDefinitionId + '?api-version=5.1'
            # $r3 = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
            $r3 = Invoke-WebRequest -Method GET -Uri $Uri -Headers $vstsAuthHeader   # Get the complete JSON directly
            $Releases2Export += $r3
            $x = $r3.content | ConvertFrom-Json
            $JsonfilePath = "./" + $x.name + ".json"
            $r3.content | Out-File -FilePath  $JsonfilePath

        }
        $Releases2Export.count

        # Output to file on disk
        # ----------------------
        Get-ChildItem
        # $Releases2Export | ConvertTo-Json -Depth 20 | Out-File -FilePath ./ReleaseDefinitionsExported.json
        $Releases2Export.content | Out-File -FilePath ./ReleaseDefinitionsExported.json


        # Test re-reading the JSON file
        $verif = Get-Content  -Path ./ReleaseDefinitionsExported.json
        $verified = $verif | ConvertFrom-Json
        $verified.Count

    }
}

#>>>>>>>>>>>>>>>>
''#>> PHASE E >>> -- CloneOut Variable Groups
#>>>>>>>>>>>>>>>>
function e_VariableGroups {}
if ($true ) {
    ################
    ''### Step 1 ### -- [MANDATORY] List Variable Groups
    ################
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/variablegroups/get%20variable%20groups?view=azure-devops-rest-5.1
    # GET https://dev.azure.com/ { organization }/ { project }/_apis/distributedtask/variablegroups?api-version=5.1-preview.1

    $Uri = "https://dev.azure.com/$vstsAccountName/$vstsTeamProjectName/_apis/distributedtask/variablegroups?5.1-preview.1"
    $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
    $r.count
    $r
    $r.value
    $r.value.name
    $r.value.variables
    $VariableGroupdsIds = $r.value.Id

    ################
    ''### Step 2 ### -- [MANDATORY] Export VariableGroups by Id
    ################
    $VariableGroupsToExport = @()
    $VariableGroupdsToExportIds = $VariableGroupdsIds    # TODO - filter/dump those not needed

    $VariableGroupdsToExportIds | ForEach-Object { 
        $VariableGroupdToExportId = $_
        $Uri = "https://dev.azure.com/" + $vstsAccountName + "/" + $vstsTeamProjectName + "/_apis/distributedtask/variablegroups?groupIds=" + $VariableGroupdToExportId + '&api-version=5.1-preview.1'
        $r1 = Invoke-RestMethod -Method Get -ContentType application/json -Uri $Uri -Headers $vstsAuthHeader
        $r1.count
        $r1
        $r1.value
        Write-Host "`n--> "$r1.value.name
        $s1 = [string]$r1.value.name
        $s2 = @{"Group#$GroupNbr ==>" = $s1 } 
        $s3 = $r1.value.variables
        $r1.value.variables
        $VariableGroupsToExport += $r1

        # Output to file on disk
        # ----------------------
        New-Item -Path $LocalDiskPathOut/VariableGroups -ItemType directory -Force
        Set-Location $LocalDiskPathOut/VariableGroups
        Get-ChildItem
        $VariableGroupsToExport | ConvertTo-Json -Depth 20 | Out-File -FilePath ./VariableGroupsExported.json

        # Test re-reading the JSON file
        $verif = Get-Content  -Path ./VariableGroupsExported.json
        $verified = $verif | ConvertFrom-Json
    }

    # Test re-reading the JSON file
    $verif = Get-Content  -Path ./VariableGroupsExported.json
    $verified = $verif | ConvertFrom-Json
    $verified.Count
}

#>>>>>>>>>>>>>>>>
''#>> PHASE F >>> -- CloneOut Task Groups
#>>>>>>>>>>>>>>>>
function f_TaskGroups {}
if ($true ) {

    # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/taskgroups/list?view=azure-devops-rest-5.1

    ################
    ''### Step 1 ### -- [MANDATORY] List Task Groups
    ################
    if ($true ) {
        # List and Get Task Groups
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/taskgroups?api-version=5.1-preview.1
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/taskgroups/{taskGroupId}?api-version=5.1-preview.1

        # List all Task Groups
        # ----------------------------
        $Uri = "https://dev.azure.com/$vstsAccountName/$vstsTeamProjectName/_apis/distributedtask/taskgroups?api-5.1-preview.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
        $r
        $r.count
        $r.value
        $r.value.id
        $r.value.name
        $TaskGroupIds = $r.value.id

    }

    ################
    ''### Step 2 ### -- [MANDATORY] Export the Task Groups by ID
    ################
    if ($true) {
        # Get all the Task Groups by ID
        # -------------------------------------}
        # GET https://vsrm.dev.azure.com/ { organization }/ { project }/_apis/release/definitions/ { definitionId }?api-version=5.1

        $TaskGroups2Export = @()
        $TaskGroups2ExportIds = $TaskGroupIds  # TODO - filter/dump those not needed

        # $ReleaseDefinitionIds obtained from List of Release Definitions
        $TaskGroups2ExportIds | ForEach-Object {
            $TaskGroups2ExportId = $_
            $Uri = "https://dev.azure.com/" + $vstsAccountName + '/' + $vstsTeamProjectName + '/_apis/distributedtask/taskgroups/' + $TaskGroups2ExportId + '?api-5.1-preview.1'
            # $r3 = Invoke-RestMethod -Method GET -Uri $Uri -Headers $vstsAuthHeader
            $r3 = Invoke-WebRequest -Method GET -Uri $Uri -Headers $vstsAuthHeader   # Get the complete JSON directly
            $TaskGroups2Export += $r3
        }
        $TaskGroups2Export.count

        # Output to file on disk
        # ----------------------

        New-Item -Path $LocalDiskPathOut/TaskGroups -ItemType directory -Force
        Set-Location $LocalDiskPathOut/TaskGroups
        Get-ChildItem
        # $Releases2Export | ConvertTo-Json -Depth 20 | Out-File -FilePath ./ReleaseDefinitionsExported.json
        $TaskGroups2Export.content | Out-File -FilePath ./TaskGroupsExported.json


        # Test re-reading the JSON file
        $verif = Get-Content  -Path ./TaskGroupsExported.json
        $verified = $verif | ConvertFrom-Json
        $verified.Count
    }
}

#>>>>>>>>>>>>>>>>
''#>> PHASE G >>> -- Save latest Excel file
#>>>>>>>>>>>>>>>>
function g_Excel {}
if ($true ) {
    $AzStoreExcelFolder = "\\$AzStoreShare.file.core.windows.net\azdevops\Work-in-Progress"
    Get-ChildItem $AzStoreExcelFolder

    Set-Location $LocalDiskPathOut
    Get-ChildItem
    Copy-Item -Path "$($AzStoreExcelFolder)\CredentialsAzDO.xlsx" -Destination $LocalDiskPathOut
}

#>>>>>>>>>>>>>>>>
''#>> PHASE H >>> -- Save Escrow ZIP
#>>>>>>>>>>>>>>>>
function h_ZipIt {}
if ($true ) {
    
    ################
    ''### Step 1 ### -- [MANDATORY] Create Escrow ZIP on local disk
    ################
    if ($true) { 
       
        # Powershell Zip compression powerhell command does not process hidden files. 
        # Therefore we have to un-hide ".git" folders by setting “Hidden" files and folders to "normal"
        $Filepath = Get-ChildItem -Recurse -Path "$LocalDiskPathOut/Git" -Force   
        $HSfiles = $Filepath | Where-Object { $_.Attributes -match "Hidden" } 
        $HSfiles 
        foreach ( $Object in $HSfiles ) { $Object.Attributes = "Archive" } 

        # Zip compress all the folders (git/builds/releases/Variablegroups)
        $compress = @{
            Path             = $LocalDiskPathOut
            CompressionLevel = "Optimal"
            DestinationPath  = "$LocalDiskPathOut\Escrow_$Date.Zip"
        }
        Compress-Archive @compress

        # Verification
        Set-Location "$LocalDiskPathOut"
        Get-ChildItem
        $r = Get-ItemProperty -Path "$LocalDiskPathOut\Escrow_$Date.Zip"
        $fileSize = “{0:N0}” -f $r.Length
        Write-Host "Zipped Escrow file size = " $fileSize "kB"
    }

    ################
    ''### Step 2 ### -- [MANDATORY] Copy Escrow ZIP file to Azure Storage
    ################
    if ($true) { 
        Set-Location $AzStorePathOut
        Get-ChildItem

        Get-ChildItem $LocalDiskPathOut 

        Copy-Item -Path "$LocalDiskPathOut/*.zip"  -Destination $AzStorePathOut
        Get-ChildItem 
    }

    ################
    ''### Step 3 ### -- [MANDATORY] Upload Escrow ZIP file to Escrow Vault
    ################
    { 
        # This is done via the utility provided "Software Escrow Gardians" file: ConnectDevelop_Escrow.exe
        # Cannot be scripted
    }
}
    
#>>>>>>>>>>>>>>>>
''#>> PHASE X >>> -- PLAYGROUND
#>>>>>>>>>>>>>>>>
function x_PlayGround {}
if ($true ) {
    ################
    ''### Step 1 ### -- List other things
    ################
    {
        $vstsBaseUrl = 'https://' + 'dev.azure.com' + '/' + 'ConnectExpress'

        # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/pools/get%20agent%20pools?view=azure-devops-rest-5.1

        # List Pools
        # GET https://dev.azure.com/{organization}/_apis/distributedtask/pools?api-version=5.1
        $Uri = $vstsBaseUrl + '/_apis/distributedtask/pools?api-version=5.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader
        $r.value
        $r.value.Id
        $r.value.name

        # List Agents
        # GET https://dev.azure.com/{organization}/_apis/distributedtask/pools/{poolId}/agents?api-version=5.1
        $Uri = $vstsBaseUrl + '/_apis/distributedtask/pools/7?api-version=5.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader

        # List AgentClouds
        # GET https://dev.azure.com/{organization}/_apis/distributedtask/agentclouds?api-version=5.1-preview.1
        $Uri = $vstsBaseUrl + '/_apis/distributedtask/agentclouds?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader

        # List AgentCloudTypes
        # GET https://dev.azure.com/{organization}/_apis/distributedtask/agentcloudtypes?api-version=5.1-preview.1
        $Uri = $vstsBaseUrl + '/_apis/distributedtask/agentcloudtypes?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader

        # List Deploymentgroups
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/deploymentgroups?api-version=5.1-preview.1
        $Uri = $vstsBaseUrl + '/' + $vstsTeamProjectName + '/_apis/distributedtask/deploymentgroups?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader
        $r.value
        $r.value.name

        # List Targets
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/deploymentgroups/{deploymentGroupId}/targets?api-version=5.1-preview.1
        $Uri = $vstsBaseUrl + '/' + $vstsTeamProjectName + '/_apis/distributedtask/deploymentgroups/11/targets?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader
        $r.value
        $r.value.agent.name

        # List Task Groups
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/taskgroups/{taskGroupId}?api-version=5.1-preview.1
        $Uri = $vstsBaseUrl + '/' + $vstsTeamProjectName + '/_apis/distributedtask/deploymentgroups/11/targets?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader
        $r.value

        # List Variable Groups
        # GET https://dev.azure.com/{organization}/{project}/_apis/distributedtask/variablegroups?api-version=5.1-preview.1
        $Uri = $vstsBaseUrl + '/' + $vstsTeamProjectName + '/_apis/distributedtask/variablegroups?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader
        $r.value
        $r.value.name

        # List YAML Schemas
        # GET https://dev.azure.com/{organization}/_apis/distributedtask/yamlschema?api-version=5.1
        $Uri = $vstsBaseUrl + '/_apis/distributedtask/yamlschema?api-version=5.1-preview.1'
        $r = Invoke-RestMethod -Method Get  -Uri $Uri -Headers $vstsAuthHeader
        $r.value
        $r.title
    }

    ################
    ''### Step 2 ### -- AzDo organization misc.
    ################
    if ($true ) {
        # GET all installed extensions on the source organization
        # -------------------------------------------------------
        # GET https://extmgmt.dev.azure.com/ { organization }/_apis/extensionmanagement/installedextensions?api-version=5.0-preview.1

        # Take note of the publisherId and extensionId from the custom extensions, by excluding the ones with the “builtin” flag
        # POST to install custom extensions you need on the target organization
        # POST https://extmgmt.dev.azure.com/ { organization }/_apis/extensionmanagement/installedextensionsbyname/ { publisherId }/ { extensionId }/ { version }?api-version=5.0-preview.1

        # Doing the following GET request you can retrieve the list of the available service endpoints, with matching URLs and authentication schemas:
        # GET https://dev.azure.com/ { organization }/_apis/serviceendpoint/types?api-version=5.0-preview.1

    }


    ################
    ''### Step 3 ### -- Git misc.
    ################
    if ($true ) {
        cd c:\temp\EscrowAzDoTest
        git config --list --show-origin
        git config --global user.name "Thierry"
        git config --global user.email Thierry@connectdevelop.com
        git help
        git help config
        git add -h

        # Initializing a Repository in an Existing Directory
        git init
        git add *.txt
        git commit -m 'initial project version'

        # Tasmota CLONE
        cd c:\temp
        git clone https://github.com/arendst/Tasmota.git
        cd c:\temp\tasmota
        ls

        # Tasmota PUSH to AzDo
        git status
        git remote -v show
        git remote rm origin   # Remove getting "fatal: remote origin already exists" message

        $Uri = "https://$vstsAccoutName@dev.azure.com/$vstsAccoutName/$vstsTeamProjectName/_git/$repoName"
        git remote add origin $Uri

        # Make a change in local repo
        New-Item -Path AddFileTest.txt -ItemType File
        Get-ChildItem
        Get-ChildItem *.txt
        git add .
        git commit -m 'initial test Thierry'

        git status
        git remote -v show
        git push -u origin --all

        Remove-Item -Path AddFileTest.txt 
        Get-ChildItem *.txt
        git add .
        git commit -m 'Second commit - delete file'
        git status
        git remote -v show
        git push -u origin --all
    }
}
