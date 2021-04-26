# CloneFromEscrowZip.ps1

<#
Author : Thierry Brunet de Courssou
Company: Connect Develop - Brisbane - Australia
Date   : September 2019
Last   : 08 Dec 2020
Notes  : to be executed line by line or by selected block of lines
AzDO   : yes - https://dev.azure.com/ConnectExpress/ConnectExpress/_git/DevOps?path=%2FEscrow%2FCloneFromEscrowZip.ps1

Purpose: 
--------
- Cloning :

    from
        . Escrow ZIP file located on PC local disk (restored from Escrow Vault)

    to 
        . AzDoGit projects
        . GitHub projects,
        . Builds definitions
        . Releases definitions
        . Variablegroups


Optional:
---------
- 

Warning:
--------
- 

Notes :
-------
- the "clone-clone" term is used instead of "backup-restore" as this better captures the intent of cloning everything to a different environment that may be run in parallel
- The artifacts on the Escrow Zip file are original un-mofifed. This way they may be restored to the original Team Project in case of recovery needed
- Although artifacts names are identical in origin team project and target escrow project, associated GUIDs are different
- Upon cloning from the Escrow Zip file, GUIDs used for linking repos/builds/releases/variable-groups will need to be matched by entity name and replaced accordingly


Pre-requisites:
---------------
- Azure Devops project workspace named "Escrow" already created and empty
TODO -- create Azure Devops project workspace named "Escrow" programmatically)

- Windows 10 PC (AzFileShare local mount not working on Mac )

- Powershell 7.1

- Visual Studo Code (latest) with Powershell Extension

- Azure Active Directory (AAD) account not necessary as AzDO PAT is used

- Latest Powershell modules: run LatestAZ function (Step A.1)


--TODOs--:
----------
TODO -- Create Escrow Project workspace programmatically
    https://docs.microsoft.com/en-us/rest/api/azure/devops/core/projects/create?view=azure-devops-rest-5.1
    POST https://dev.azure.com/{organization}/_apis/projects?api-version=5.1

In each Release definition: Replace"

"triggerType":"pullRequest"
with
"triggerType": "continuousIntegration"

Project ID: 
0d354d3e-09e9-430e-b241-c0e7e2272e1a
with
59342557-6984-40c3-befa-488f6d2b2bf8


INFO
----
The Azure DevOps REST API is a powerful and versatile interface to automate 
almost anything involving Azure DevOps.

https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-5.1
https://chocolatey.org/packages/vsts-sync-migrator/
https://marketplace.visualstudio.com/items?itemName=nkdagility.processtemplate
https://www.youtube.com/watch?v=RCJsST0xBCE&feature=youtu.be
https://blog.devopsabcs.com/index.php/2019/06/12/one-project-to-rule-them-all/

Note: The AzDo Migration tools suite does not support Pipeline migration. This has to be done manually
via Export/Import, either mnaually via portal or via Rest API

#>

#<<<<<<<<<<<<<<<<
''#<< PHASE A <<< -- Initialization
#<<<<<<<<<<<<<<<<
function a_Init {}
if ($true)
{
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
        $AzDoAccountName = 'ConnectExpress'
        $AzDoTeamProjectName = 'Escrow'
        $vstsPAT = '3enuulrhvte4pe7kxqcnh5f4blbkg37iaq4qy5dopztmivmh33hq' # Escrow PAT (rotated monthly)
        $User = ""

        # Base64-encodes the Personal Access Token (PAT) appropriately
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $vstsPAT)))
        $AzDoAuthHeader = @{Authorization = ("Basic {0}" -f $base64AuthInfo) }

        # Get Project Name ID
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/core/projects/list?view=azure-devops-rest-5.1
        # GET https://dev.azure.com/{organization}/_apis/projects?api-version=5.1
        $Uri = "https://dev.azure.com/$AzDoAccountName/_apis/projects?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $r.value
        <#
            id             : ac636c8c-7015-4fbf-9777-eb4022d802e3
            name           : ConnectExpress
            description    : CX Movers is a simple yet powerful solution that streamlines energy and other connections for tenants, property managers and        
                            service providers.
            url            : https://dev.azure.com/ConnectExpress/_apis/projects/ac636c8c-7015-4fbf-9777-eb4022d802e3
            state          : wellFormed
            revision       : 99
            visibility     : private
            lastUpdateTime : 4/11/2019 12:33:21 AM

            id             : 59342557-6984-40c3-befa-488f6d2b2bf8
            name           : Escrow
            description    : Escrow audit - by Thierry
            url            : https://dev.azure.com/ConnectExpress/_apis/projects/59342557-6984-40c3-befa-488f6d2b2bf8
            state          : wellFormed
            revision       : 188
            visibility     : private
            lastUpdateTime : 8/11/2019 12:01:57 AM
        #>

        $ConnectExpressProjectID = $r.value[0].id  # ac636c8c-7015-4fbf-9777-eb4022d802e3
        $EscrowProjectID = $r.value[1].id # 59342557-6984-40c3-befa-488f6d2b2bf8
        $thisProject = $r.value[1]
    }

    ################
    ''### Step 3 ### -- Initialize for local disk folder
    ################
    if ($true) { 
        # $Date = Get-Date -UFormat "(%d-%m-%Y)"
        $Date = "(10-11-2019)"
        $Date = "(11-11-2019)"
        $Date = "(09-11-2019)"

        $LocalDiskPathIn = "c:\Temp\EscrowZipIn"
        Set-Location $LocalDiskPathIn 
        Get-ChildItem
    }

    ################
    ''### Step 4 ### -- Upzip Escrow ZIP file
    ################
    if ($true) { 
        Expand-Archive -LiteralPath "$LocalDiskPathIn\$Date\Escrow_$Date.Zip" -DestinationPath $LocalDiskPathIn
        Expand-Archive -LiteralPath "$LocalDiskPathIn\Escrow_$Date.Zip" -DestinationPath $LocalDiskPathIn
        Set-Location $LocalDiskPathIn
        Get-ChildItem
    }
}

#<<<<<<<<<<<<<<<<
''#<< PHASE B <<< -- CloneIn GitRepos from local PC disk
#<<<<<<<<<<<<<<<<
function b_Git {}
if ($true)
{
    ################
    ''### Step 1 ### -- Create the cloned Git repositories in the "Escrow" team project
    ################
    if ($DoIt) {

        # https://docs.microsoft.com/en-us/rest/api/azure/devops/git/repositories/create?view=azure-devops-rest-5.0
        # POST https://dev.azure.com/ { organization }/ { project }/_apis/git/repositories?api-version=5.0
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories?api-version=5.1"

        Set-Location $LocalDiskPathIn/$Date/Git
        $repos = Get-ChildItem 
        $repos.name

        # (a) Create blank repos in AzDo
        $repos | ForEach-Object { 
            $repoName = $_.name
            write-host $repoName -NoNewline
            $repoBody = @{ name = $repoName } | ConvertTo-Json
            $r = Invoke-RestMethod -Method POST -Uri $Uri -Headers $AzDoAuthHeader -Body $repoBody -ContentType application/json
            write-host "  ---> " $r.webUrl
        }

        # (b) Clone local repo to remote AzDo
        $repos | ForEach-Object {  
            $repoName = $_.name
            write-host "`n ---> " $repoName
            Set-Location "$LocalDiskPathIn/$Date/Git/$repoName" 
            git remote rm origin  # Remove the previous origin which is no longer valid
            $Uri = "https://$AzDoAccountName@dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_git/$repoName"
            git remote add origin $Uri
            git push -u origin --all
        }
    }

    ################
    ''### Step 2 ### --  List repos
    ################
    if ($DoIt) {
        # List Repositories
        # GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?api-version=5.1
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $r.count
        # $r.value
        $r.value.name
    }

    ################
    ''### Step 3 ### --  [Optional] Delete repos
    ################
    if ($false) {
        $repos2delete = @()
        $repos2delete += "au-movers-new-account-invitations"
        $repos2delete += "au-movers-realestate-agent-onboarding"
        $repos2delete += "au-movers-realestate-dashboard"
        $repos2delete += "au-switchboard"
        $repos2delete += "Auth0"
        $repos2delete += "connectexpress-com-au"
        $repos2delete += "cx-alinta-energy-integration-svc"
        $repos2delete += "Cx-Data-Insights"
        $repos2delete += "cx-signup-svc"
        $repos2delete += "cx-signup-ui"
        $repos2delete += "DevOps"
        $repos2delete += "DevOpsMinions"
        $repos2delete += "the-builders-platform"
        $repos2delete += "the-movers-platform"
        $repos2delete += "Conversations"
        $repos2delete.Length
        
        foreach ($repo2delete  in $repos2delete ) { 
            write-host $repo2delete -NoNewline
            
            # First get the repo ID by supplying repo name
            $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories/" + $repo2delete + '?api-version=5.1'
            $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
            $r.id
            
            # Delete repo in AzDo using its ID
            $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories/" + $r.id + '?api-version=5.1'
            $r = Invoke-RestMethod -Method DELETE -Uri $Uri -Headers $AzDoAuthHeader
        }
    }
}

#<<<<<<<<<<<<<<<<
''#<< PHASE C <<< -- CloneIn Variable Groups from local PC disk
#<<<<<<<<<<<<<<<<
function c_VariableGroups {}
if ($true)
{
    ################
    ''### Step 1 ### -- Read Variable Groups from local PC disk
    ################
    {
        Set-Location $LocalDiskPathIn/$Date/VariableGroups
        Get-ChildItem
        $VariableGroupsJson = Get-Content  -Path ./VariableGroupsExported.json
        $VariableGroups = $VariableGroupsJson | ConvertFrom-Json 
        $VariableGroups.value.name
    }

    ################
    ''### Step 2 ### -- Create Variable Groups in AzDo
    ################
    {
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/variablegroups/add?view=azure-devops-rest-5.1
        # POST https://dev.azure.com/{organization}/{project}/_apis/distributedtask/variablegroups?api-version=5.1-preview.1
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/distributedtask/variablegroups?api-version=5.1-preview.1"

        # just to get the hash text if needed
        $x = $VariableGroups.value | get-member | Sort-Object name
        $x.Name
        $y = $x.Name
        $z = @()
        $y | ForEach-Object { $z += $_ + ' = $_.' + $_ }
        $z

        # Members full set associated to $VariableGroups read from ZIP file
        <#
            createdBy
            createdOn
            description  (***)
            Equals
            GetHashCode
            GetType
            id
            isShared
            modifiedBy
            modifiedOn
            name       (***)
            ToString
            type       (***)
            variableGroupProjectReferences
            variables  (***)
        #>

        # Recommended member set for API boby  --- (***) shown above:
        $VariableGroups | ForEach-Object { 

            $RequestBody = @{
                description = $_.value.description
                name        = $_.value.name
                type        = $_.value.type
                variables   = $_.value.variables
            }
            # providerData = $true   ????
            
            $RequestBodyJson = ConvertTo-Json $RequestBody

            # Create this Variables Group
            $thisVariableGroupName = $_.value.name
            Write-Host "---> " $thisVariableGroupName
            $r = Invoke-RestMethod -Method POST -Uri $Uri -Headers $AzDoAuthHeader  -Body $RequestBodyJson -ContentType application/json

        }
    }

    ################
    ''### Step 2 ### -- [Optional] Delete Variable Groups
    ################
    if ($false) {

        # List Variable Groups
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $VariableGroupsIds2Delete = $r.value.id

        # Currate Delete VariableGroups list as needed
        # ....... doit here

        # Delete Variable Groups
        $r.value.id | ForEach-Object {
            $VariableGroupsId2Delete = $_
            Write-Host "---> deleting variable groups ID " $VariableGroupsId2Delete
            $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/distributedtask/variablegroups/$VariableGroupsId2Delete" + '?api-version=5.1-preview.1'
            $r = Invoke-RestMethod -Method DELETE -Uri $Uri -Headers $AzDoAuthHeader
        }
    }
}

#<<<<<<<<<<<<<<<<
''#<< PHASE D <<< -- CloneIn Task Groups from local PC disk
#<<<<<<<<<<<<<<<<
function d_TaskGroups {}
if ($true)
{
    ################
    ''### Step 1 ### -- Read Task Groups from local PC disk
    ################
    {
        Set-Location $LocalDiskPathIn/$Date/TaskGroups
        Get-ChildItem
        $TaskGroupsJson = Get-Content  -Path ./TaskGroupsExported.json
        $TaskGroupsJson.count

        $TaskGroups = $TaskGroupsJson | ConvertFrom-Json 
        $TaskGroups.value.count
        $TaskGroups.value | Format-Table name, id
    }
    
    ################
    ''### Step 2 ### -- Create Task Groups in AzDo
    ################
    {
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/distributedtask/taskgroups/add?view=azure-devops-rest-5.1
        # POST https://dev.azure.com/{organization}/{project}/_apis/distributedtask/taskgroups?api-version=5.1-preview.1
        
        # This is simply a trick to create the $RequestBody fields list, which will be pasted between [ $RequestBody @{...} ]
        # Fields for body as specified in Rest API
        if ($false) {
            $x = @(
                "author",
                "category",
                "description",
                "friendlyName",
                "iconUrl",
                "inputs",
                "instanceNameFormat",
                "name",
                "parentDefinitionId",
                "runsOn",
                "tasks",
                "version"
            )
            $RequestBobyFields = $x | ForEach-Object { $_ = $_ + ' = $_.' + $_ ; $_ }  ; write-host "`n>>>>---"; $RequestBobyFields; write-host "---<<<<`n"
        }
            
        #Create the Task Groups with the recommended request body
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/distributedtask/taskgroups?api-version=5.1-preview.1"

        $CreatedTaskGroups = @()
        $TaskGroups.value | ForEach-Object { 
            $Tasks = $_.tasks

            $Tasks | ForEach-Object { 
                if ($_.task.definitionType -eq "task") { 
                    Write-Host "---> Success"
                } 
                else {
                    $CreatedTaskGroups | Format-Table name, id
                    Write-Host "`n>>>>> input needed for : " -ForegroundColor Red -NoNewline
                    Write-Host "xx`n" $_.name -ForegroundColor Green
                    $TasksGroupDependancyId = Read-Host "Metatask dependancy -- Enter task ID from the list above"
                    $_.task.id = $TasksGroupDependancyId
                }
            }

            $RequestBody = @{
                author             = $_.author
                category           = $_.category
                description        = $_.description
                friendlyName       = $_.friendlyName
                iconUrl            = $_.iconUrl
                inputs             = $_.inputs
                instanceNameFormat = $_.instanceNameFormat
                name               = $_.name
                parentDefinitionId = $_.parentDefinitionId
                runsOn             = $_.runsOn
                tasks              = $_.tasks
                version            = $_.version  
            }
            $RequestBodyJson = $RequestBody | ConvertTo-Json -depth 10
            write-host "===> " $RequestBody.name
            $CreatedTaskGroup = Invoke-RestMethod -Method POST -Uri $Uri -Headers $AzDoAuthHeader  -Body $RequestBodyJson -ContentType application/json 
            $CreatedTaskGroups += $CreatedTaskGroup
        }
    }

    ################
    ''### Step 3 ### -- [Optional] Delete Task Groups
    ################
    if ($false) {
    
        # List Variable Groups
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/distributedtask/taskgroups?api-version=5.1-preview.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $TaskGroupsIds2Delete = $r.value.id
        $r.value | Format-Table name, id
    
        # Currate Delete Task Groups list as needed
        # ....... doit here
    
        # Delete Task Groups
        if ($r.value.id.Count -gt 0) {
            $r.value.id | ForEach-Object {
                $TaskGroupsId2Delete = $_
                Write-Host "---> deleting task groups ID " $TaskGroupsId2Delete
                $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/distributedtask/taskgroups/$TaskGroupsId2Delete" + '?api-version=5.1-preview.1'
                $r = Invoke-RestMethod -Method DELETE -Uri $Uri -Headers $AzDoAuthHeader  
            }
        }
    }
}

#<<<<<<<<<<<<<<<<
''#<< PHASE E <<< -- CloneIn Build Definitions from local PC disk
#<<<<<<<<<<<<<<<<
function e_BuilDeft {}
if ($true)
{
    ################
    ''### Step 1 ### -- Read Build Definitions from local PC disk
    ################
    {
        Set-Location $LocalDiskPathIn/$Date/BuildDefinitions
        Get-ChildItem
        $BuildDefinitionsImportedJson = Get-Content  -Path ./BuildDefinitionsExported.json
        $BuildDefinitionsImportedJson.Count

        $BuildDefinitionsImported = $BuildDefinitionsImportedJson | ConvertFrom-Json  -depth 20 -AsHashtable
        $BuildDefinitionsImported.name

        # Verification
        # $BuildDefinitionsImported[0]   # Original Build Definition prior to modifs
        # $BuildDefinitionsImported[0].options
        # $BuildDefinitionsImported[0].triggers
        # $BuildDefinitionsImported[0].process
        # $BuildDefinitionsImported[0].process.phases
    }

    ################
    ''### Step 2 ### --  List Git repos for replacing GUIDs referenced in Build Definitions
    ################
    {
        # List Repositories
        # GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?api-version=5.1
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $r.count
        $r.value | Format-Table name, id, project

        $repoNamesIds = @()
        $r.value | ForEach-Object { if ($_.name -ne "Tasmota") { $repoNamesIds += @{$_.name = $_.id } } }  # Opt-out repos that are to be ignored 
        $repoNamesIds
        $repoNamesIds.length
    }

    ################
    ''### Step 3 ### --  Delete the useless fields in Build definitions
    ################
    {
        # Fields to delete
        # ----------------
        $ExcludeThis = ""
        for ($i = 0; $i -lt $fields2delete.Count; $i++) { $ExcludeThis += $fields2delete[$i] + ", " }
        $ExcludeThis = $ExcludeThis.TrimEnd(", ")
        $ExcludeThis   # copy the output to the -ExcludeProperty in the command below
        $Builds = $BuildDefinitionsImported | Select-Object -Property * -ExcludeProperty _links, authoredBy, url, uri, revision, createdDate, id
        $Builds.Count

        # Exclude some properties in the "queue" property
        $Builds | ForEach-Object { 
            $x = $_.queue
            # $y = $x | Select-Object -Property * -ExcludeProperty _links, url, id, pool
            $y = $x | Select-Object -Property * -ExcludeProperty _links
            $_.queue = $y
        }

        # Quick Check
        # $BuildDefinitionsImported[0]  # Before
        # $Builds[0]          # After

        # $Builds.repository.id
        # $Builds.repository.name
        # $Builds.repository.url

        # $Builds.repository[0].properties
        # $Builds.project.name[0]
        # $Builds.project.id[0]
        # $Builds.project.url[0]
    }

    ################
    ''### Step 4 ### --  Modify/update fields in Build definitions
    ################
    {

        $Builds2Create = @()
        $Builds | ForEach-Object {
            $verif = $_
            # $verif.queue
            # $verif.queue.name
            # $verif.queue.id
            # $verif.queue.pool
            # $verif.queue.url
            # $verif.process.target 
            # $verif.process.target.agentSpecification.identifier

            # (1) Modify Release Definition members
            # --------------------------------------
            $_.queue.id = "48"
            $_.queue.name = "Azure Pipelines"
            $_.queue.url = "https://dev.azure.com/ConnectExpress/_apis/build/Queues/48"

            $_.queue.pool.id = "15"
            $_.queue.pool.name = "Azure Pipelines"
            $_.queue.pool.isHosted = "true"

            $_.process.target = @{agentSpecification = @{identifier = "windows-2019" } }

            # (2) Modify Project members
            # ---------------------------
            $_.project.name = $thisProject.name
            $_.project.id = $thisProject.id
            $_.project.url = $thisProject.url
            $_.project.description = "Escrow project -- all is cloned from the ZIP file retrieved from the Escrow vault"
       
            # (3) Modify Repository members
            # ------------------------------
            $y = $_.repository.name
            $y = $y.replace("Connect-Express/", "")
            $y = $y.replace("Connect-Develop/", "")
            $thisRepoName = $y

            # Get the local repo GUID for the "Repository" that is referenced in the "build definition"
            write-host "---> " $thisRepoName -NoNewline
            $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories/" + $thisRepoName + "?api-version=5.1"
          
            try {  
                $thisRepo = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader 
                $_.repository.id = $thisRepo.id
                $x = $thisRepo.name
                $x = $x.replace("Connect-Express/", "")
                $x = $x.replace("Connect-Develop/", "")
                $_.repository.name = $x
                $_.repository.url = $thisRepo.url
                $Builds2Create += $_
                write-host "  -- OK"
            } 
            Catch { 
                # $_.repository.name = "deleteit"
                write-host "  -- ignore this one" -ForegroundColor Red
            }

            $verif2 = $_
            # $verif2.queue
            # $verif2.queue.name
            # $verif2.queue.id
            # $verif2.queue.pool
            # $verif2.queue.url
            # $verif2.process.target 
            # $verif2.process.target.agentSpecification.identifier
        }

        # Verify
        $Builds2Create.name
    }

    ################
    ''### Step 5 ### --  Create the amended build definition in AzDo
    ################
    {
        if ($false) { 
            # This is simply a trick to create the $RequestBody fields list, which will be pasted between @{...}
            $x = $Builds2Create[0] | get-member | Sort-Object Name
            $x.Name
            $y = $x.Name
            $RequestBobyFields = $y | ForEach-Object { $_ = $_ + ' = $_.' + $_; $_ }
        }

        # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/definitions/create?view=azure-devops-rest-5.1
        # POST https://dev.azure.com/{organization}/{project}/_apis/build/definitions?api-version=5.1
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/build/definitions?api-version=5.1"

        $Builds2Create | ForEach-Object {
            write-host "---> " $_.name
            $RequestBody = @{
                id                        = ""
                buildNumberFormat         = $_.buildNumberFormat
                drafts                    = $_.drafts
                jobAuthorizationScope     = $_.jobAuthorizationScope
                jobCancelTimeoutInMinutes = $_.jobCancelTimeoutInMinutes
                jobTimeoutInMinutes       = $_.jobTimeoutInMinutes
                name                      = $_.name
                options                   = $_.options
                path                      = $_.path
                process                   = $_.process
                processParameters         = $_.processParameters
                project                   = $_.project
                properties                = $_.properties
                quality                   = $_.quality
                queue                     = $_.queue
                queueStatus               = $_.queueStatus
                repository                = $_.repository
                tags                      = $_.tags
                type                      = $_.type
                variables                 = $_.variables
            }
            $RequestBodyJson = ConvertTo-Json  $RequestBody -depth 10
        
            # Create this Build Definition
            $thisBuildName = $_.name
            Write-Host "---> " $thisBuildName
            $r = Invoke-RestMethod -Method POST -Uri $Uri -Headers $AzDoAuthHeader  -Body $RequestBodyJson -ContentType application/json
        }
    }


    ################
    ''### Step 6 ### -- [Optional] Delete Build Definitions
    ################
    if ($false) {
    
        # List Build Definitions
        # ----------------------
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/build/definitions?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $BuildDefinitionsIds2Delete = $r.value.id
        $r.value | Format-Table name, id
    
        # Currate Build Definitions list as needed
        # ....... doit here
    
        # Delete Build Definitions
        # ------------------------
        # DELETE https://dev.azure.com/{organization}/{project}/_apis/build/definitions/{definitionId}?api-version=5.1
        if ($r.value.id.Count -gt 0) {
            $r.value.id | ForEach-Object {
                $BuildDefinitionsId2Delete = $_
                Write-Host "---> deleting task groups ID " $BuildDefinitionsId2Delete
                $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/build/definitions/$BuildDefinitionsId2Delete" + '?api-version=5.1'
                $r = Invoke-RestMethod -Method DELETE -Uri $Uri -Headers $AzDoAuthHeader  
            }
        }

        # Warning: getting error 
        # {"$id":"1","innerException":null,"message":"The user doesn't have access to the service connection(s) added 
        # to this pipeline or they are not found. Names/IDs: 0d354d3e-09e9-430e-b241-c0e7e2272e1a",
        # "typeName":"Microsoft.TeamFoundation.Build.WebApi.AccessDeniedException, 
        # Microsoft.TeamFoundation.Build2.WebApi","typeKey":"AccessDeniedException","errorCode":0,"eventId":3000}
        start-process "https://aka.ms/yamlauthz"
    }
}

#<<<<<<<<<<<<<<<<
''#<< PHASE F <<< -- CloneIn Release Definitions from local PC disk
#<<<<<<<<<<<<<<<<
function f_ReleaseDef {}
if ($true)
{
    ################
    ''### Step 1 ### -- Read Release Definitions from local PC disk
    ################
    {
        Set-Location $LocalDiskPathIn/$Date/ReleaseDefinitions
        Get-ChildItem
        $ReleaseDefinitionsImportedJson = Get-Content  -Path ./ReleaseDefinitionsExported.json
        $ReleaseDefinitionsImported = $ReleaseDefinitionsImportedJson | ConvertFrom-Json
        $ReleaseDefinitionsImported.name
        $ReleaseDefinitionsImported.Count
    }

    ################
    ''### Step 2 ### --  List Git repos for replacing GUIDs referenced in Release Definitions
    ################
    {
        # List Repositories
        # GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?api-version=5.1
        $Uri = "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/git/repositories?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $r.count
        $r.value
        $r.value.id
        $r.value.name
        $r.value.project
        $r.value | Format-Table name, id, project

        $repoNamesIds = @()
        $r.value | ForEach-Object { if ($_.name -ne "Tasmota") { $repoNamesIds += @{$_.name = $_.id } } }  # Opt-out repos that are to be ignored 
        $repoNamesIds
        $repoNamesIds.length
        <# 
           Name                           Value
           ----                           -----
           cx-signup-ui                   2a009f76-8024-443d-abe6-0472066ac6e7
           KestrelMinions                 321748ee-d2ab-4b0c-bd76-15bd01a37817
           connectexpress-com-au          a3ee3b56-dae3-4489-8660-1777bebaa999
           au-movers-realestate-dashboard dcefe7f0-a1f2-430c-b7dd-29b9a2f84f27
           cx-signup-svc                  e64e08cb-9157-4927-8d1f-3a00f6ad6e81
           the-movers-platform            c978c842-d847-4f1f-af66-432f1ea35786
           Cx-Data-Insights               3834569f-1664-4c37-80b3-442af93dadef
           au-movers-new-account-invitat… 4c8eed46-980b-415d-9beb-5a57485a26fd
           au-switchboard                 5b7936c0-fba6-4807-a79d-638c40e16302
           cx-alinta-energy-integration-… e3595a0c-6c53-4549-9316-99be8001ee63
           DevOpsMinions                  fa2a596e-3a03-41cf-86b6-a9a6c7ded7d5
           au-movers-realestate-agent-on… f1f2131d-8ffc-4871-94f9-b575db20c8f3
           the-builders-platform          19b4470b-4a9d-4493-b790-c8f34dcdb820
           Auth0                          4a8b9c8f-c69f-46fd-acf8-d28ba8d9e6d9
           DevOps                         5d6641e8-a8ed-489d-b0da-f00a9aadbe8b
        #>
    }

    ################
    ''### Step 3 ### --  Delete the useless fields in Release definitions
    ################
    {
       
    }

    ################
    ''### Step 4 ### --  Modify/update fields in Release definitions
    ################
    {
       
    }

    ################
    ''### Step 5 ### --  Create the amended Release definitions in AzDo
    ################
    {
        # https://docs.microsoft.com/en-us/rest/api/azure/devops/release/definitions/create?view=azure-devops-rest-5.1
        # POST https://vsrm.dev.azure.com/{organization}/{project}/_apis/release/definitions?api-version=5.1
        $Uri = "https://vsrm.dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/release/definitions?api-version=5.1"

        $RequestBody = @{
            _links           = $_.links 
            artifacts        = ""
            comment          = ""
            createdBy        = ""
            createdOn        = ""
            description      = ""
            environments     = ""
            id               = $_.id 
            isDeleted        = $_.
            lastRelease = $_.
            modifiedBy = $_.
            modifiedOn = $_.
            name = $_.name
            path             = $_.path
            projectReference = $_.
            properties = $_.    
            releaseNameFormat = $_.
            revision = $_.
            source = "undefined"
            tags             = $_.tags
            triggers         = $_.triggers
            url              = $_.url
            variableGroups   = $_.variableGroups
            variables        = $_.variables
        }

        # Create this Release Definition
        $thisReleaseName = $_.name
        Write-Host "---> " $thisReleaseName
        $r = Invoke-RestMethod -Method POST -Uri $Uri -Headers $AzDoAuthHeader  -Body $RequestBodyJson -ContentType application/json

    }

    ################
    ''### Step 6 ### -- [Optional] Delete Release Definitions
    ################
    if ($false) {
    
        # List Release Definitions
        # ----------------------
        $Uri = "https://vsrm.dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/Release/definitions?api-version=5.1"
        $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader
        $ReleaseDefinitionsIds2Delete = $r.value.id
        $r.value | Format-Table name, id
    
        # Currate Release Definitions list as needed
        # ....... doit here
    
        # Delete Release Definitions
        # ------------------------
        # DELETE https://dev.azure.com/{organization}/{project}/_apis/Release/definitions/{definitionId}?api-version=5.1
        if ($r.value.id.Count -gt 0) {
            $r.value.id | ForEach-Object {
                $ReleaseDefinitionsId2Delete = $_
                Write-Host "---> deleting task groups ID " $ReleaseDefinitionsId2Delete
                $Uri = "https://vsrm.dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_apis/Release/definitions/$ReleaseDefinitionsId2Delete" + '?api-version=5.1'
                $r = Invoke-RestMethod -Method DELETE -Uri $Uri -Headers $AzDoAuthHeader  
            }
        }

        # Warning: getting error 
        # {"$id":"1","innerException":null,"message":"The user doesn't have access to the service connection(s) added 
        # to this pipeline or they are not found. Names/IDs: 0d354d3e-09e9-430e-b241-c0e7e2272e1a",
        # "typeName":"Microsoft.TeamFoundation.Build.WebApi.AccessDeniedException, 
        # Microsoft.TeamFoundation.Build2.WebApi","typeKey":"AccessDeniedException","errorCode":0,"eventId":3000}
        start-process "https://aka.ms/yamlauthz"
    }
}

#<<<<<<<<<<<<<<<<
''#<< PHASE G <<< -- Trigger ALL Build Definitions
#<<<<<<<<<<<<<<<<
function g_TriggerAllBuilds {}
if ($true)
{
    # TODO G -- Trigger ALL Build Definitions programmatically via AzDo Rest API
}

#<<<<<<<<<<<<<<<<
''#<< PHASE H <<< -- Trigger ALL Release Definitions
#<<<<<<<<<<<<<<<<
function h_TriggerAllReleases {}
if ($true)
{
    # TODO H -- Trigger ALL Build Definitions programmatically via AzDo Rest API (as already implemented in WakeUp from hibernation AzPsFunction)

}

#<<<<<<<<<<<<<<<<<<<
''#<< PlayGround <<< 
#<<<<<<<<<<<<<<<<<<<
function x_PlayGround {}
if ($true)
{
    # ----------------------------------------------
    # DevOps Security - One Project To Rule Them All
    # ----------------------------------------------
    https://blog.devopsabcs.com/index.php/2019/06/12/one-project-to-rule-them-all/

    # https://blog.devopsabcs.com/index.php/2019/06/24/one-project-to-rule-them-all-3/


    # List of security namespaces
    # ---------------------------
    # https://dev.azure.com/{organization}/_apis/securitynamespaces?api-version=5.0
    $Uri = "https://dev.azure.com/$AzDoAccountName/_apis/securitynamespaces/?api-version=5.1"
    $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader 
    $r.value
    $r.count
    $r.value.name | Sort-Object


    # What the subjectDescriptor is and where I can find it?

    # In the security of Azure Devops, subjectDescriptor is user's SID. It used as identification 
    # when operating some security control. This parameter can uniquely identify the same graph 
    # subject across both Accounts and Organizations.
    # GET https://vssps.dev.azure.com/{org name}/_apis/graph/users?api-version=5.1-preview.1
    $Uri = "https://vssps.dev.azure.com/$AzDoAccountName/_apis/graph/users?api-version=5.1-preview.1"
    $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader 
    $r.value
    $r.value.displayname | Sort-Object
    $r.value | Sort-Object displayname | Format-Table displayname, descriptor


    # Lists of all the session token details of the personal access tokens (PATs) for a particular user.
    # https://docs.microsoft.com/en-us/rest/api/azure/devops/tokenadmin/personal%20access%20tokens/list?view=azure-devops-rest-5.1
    # GET https://vssps.dev.azure.com/{organization}/_apis/tokenadmin/personalaccesstokens/{subjectDescriptor}?api-version=5.1-preview.1
    $Descriptor = "svc.ZTA5NDE3ZGUtNmNhOC00MjlkLWIwYTEtZGE3MDIxYzQ2ZDE2OkFnZW50UG9vbDo1YTZlMDlkNi1lNDYxLTQ5NGItODU1ZC0yNGMwMDM0NWI0Zjk"   # Agent Pool Service (9)
    $Descriptor = "aad.OTEzM2Y5MmUtYWZkOC03YjE2LWI2YmItMzc3Yjk4NzJiOGQ5"   # Thierry

    $Uri = "https://vssps.dev.azure.com/$AzDoAccountName/_apis/tokenadmin/personalaccesstokens/" + $Descriptor + '?api-version=5.1-preview.1'
    $r = Invoke-RestMethod -Method GET -Uri $Uri -Headers $AzDoAuthHeader 
    $r.value
    $r.value | Sort-Object displayname | Format-Table scope, displayname

    $Patx = $r.value | Where-Object displayname -like "*escrow*"
    $Patx
    <# 
        clientId            : 00000000-0000-0000-0000-000000000000
        accessId            : a8d5fede-c7c9-4b87-8bc6-3ca212ee1985
        authorizationId     : 6be42e38-ee5f-4cb8-bf4d-b82873bc3320
        hostAuthorizationId : 00000000-0000-0000-0000-000000000000
        userId              : 9133f92e-afd8-6b16-b6bb-377b9872b8d9
        validFrom           : 9/11/2019 12:00:00 AM
        validTo             : 8/11/2020 12:00:00 AM
        displayName         : PowerShellEscrow
        scope               : app_token
        targetAccounts      : {e09417de-6ca8-429d-b0a1-da7021c46d16}
        token               : 
        alternateToken      : 
        isValid             : True
        isPublic            : False
        publicData          :
        source              :
        claims              : 
    #>



### IMPORTANT ####

# Service connections are created at project scope. A service connection created in one project is not visible in another project.

# Therefore make sure the service connection "Powershell4EscrowAuditAzDo" is created in the "Escrow" project 
# If not, create it using the Escrow PAT entered above.

# Also make sure the service connection "Powershell4EscrowAuditARM" is created in the "Escrow" project 
# If not, create it for the entire scope of the subscription.

# https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints

# Define and manage service connections from the Admin settings of your project:
# https://dev.azure.com/{organization}/{project}/_admin/_services
start-process "https://dev.azure.com/$AzDoAccountName/$AzDoTeamProjectName/_admin/_services"


}