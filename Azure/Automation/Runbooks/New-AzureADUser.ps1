Param(
    [string]$SharePointSiteURL = 'https://crayondemos.sharepoint.com/sites/IT',
    [string]$SharePointListName = 'User Onboarding',
    [string]$SharepointListNewEmployeeId
)

<#

    NAME: New-AzureADUser.ps1

    AUTHOR: Jan Egil Ring 
    EMAIL: jan.egil.ring (at) outlook.com

    COMMENT: Sample Azure Automation runbook to create a new Azure AD user based on input from a Sharepoint list. 

    Prerequisites:
    -A SharePoint list
    -A service account/principal which have permissions to the SharePoint list that will be used to write back status and information.
    -Azure AD PowerShell module
 
    Note 2018-05-21: This runbook is intended as an example only. I would encourage to break the code 
                     into a more modular approach if starting from scratch in a new environment.

    You have a royalty-free right to use, modify, reproduce, and 
    distribute this script file in any way you find useful, provided that 
    you agree that the creator, owner above has no warranty, obligations, 
    or liability for such use. 

    VERSION HISTORY: 
    1.0 17.03.2017 - Initial release

#>

Write-Output -InputObject "Runbook started $(Get-Date) on Azure Automation Runbook Worker $($env:computername)"

#region Set up loggging
$LoggingEnabled = $true
$LogFolder = 'C:\Azure Automation\Logs\New-AzureADUser'

if ($LoggingEnabled) {

    Write-Output -InputObject 'Setting up file logging...'

    if (!(Test-Path -Path $LogFolder)) {

        mkdir $LogFolder

    }

    try {

        Import-Module -Name 'Communary.Logger' -ErrorAction Stop

        $logHeaderString = "Crayon Demo Azure AD User provisioning. Log file created $(Get-Date)"

        $LogPath = Join-Path -Path $LogFolder -ChildPath ($((Get-Date).tostring('yyyyMMdd-hhmmss')) + '.log')

        if (-not (Test-Path -Path $LogPath)) {

            New-Log -Path $LogPath -Header $logHeaderString -ErrorAction Stop

        }

        else {

            New-Log -Path $LogPath -Header $logHeaderString -Append -ErrorAction Stop

        }

        Write-Output -InputObject "File-logging started, logging to $($LogPath)"


    }

    catch {

        Write-Output -InputObject "Setting up logging failed. Verify that the required PowerShell module (Communary.Logger) for logging is installed and that $($env:username) has write permissions to log file $($settingsobject.LogPath) on computer $($env:computername) , aborting..."

        Write-Error -Message "Setting up logging failed. Verify that the required PowerShell module (Communary.Logger) for logging is installed and that $($env:username) has write permissions to log file $($settingsobject.LogPath) on computer $($env:computername) , aborting..."

        throw $_.Exception

        break

    }

} else {

    Write-Output -InputObject 'File logging logging not enabled'

}

#endregion

#region Process prerequisites


Write-Output -InputObject 'Importing prerequisite modules...'

if ($LoggingEnabled) {

    Write-Log -LogEntry 'Importing prerequisite modules...'

}

try {

    Import-Module -Name AzureAD -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false
    Import-Module -Name Crayon.Core -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false
    Import-Module -Name SharePointPnPPowerShellOnline -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false
    Import-Module -Name pdftools -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false

} catch {

    Write-Error -Message 'Prerequisites not installed'

    if ($LoggingEnabled) {

        Write-Log -LogEntry 'Prerequisites not installed' -LogType Error

    }


}

#endregion

$AADCredential = Get-AutomationPSCredential -Name cred-AzureAutomation
$EXOCredential = Get-AutomationPSCredential -Name cred-AzureAutomation
$SPOCredential = Get-AutomationPSCredential -Name cred-AzureAutomation


try {
    
        Connect-PnPOnline -Url $SharePointSiteURL -Credentials $SPOCredential
    
        $NewUserSourceData = Get-PnPListItem -List  $SharePointListName -Id $SharepointListNewEmployeeId -ErrorAction Stop
    
    }
    
    catch {
    
        Write-Log -LogEntry "User object with Id $SharepointListNewEmployeeId not found in Sharepoint list $SharePointListName - aborting" -LogType Error
    
        $WorkflowStatus = 'Failed'
    
    }

if (-not ($NewUserSourceData)) {

    throw "User object not found"

}

$Count = ($NewUserSourceData | Measure-Object).Count
if ($Count -ne 1) {

    if ($LoggingEnabled) {

        Write-Log -LogEntry "User objects found in Sharepoint list: $Count Should be exactly 1, aborting" -LogType Error

    }

    throw "User objects found in Sharepoint list: $Count Should be exactly 1, aborting"

}

if ($LoggingEnabled) {

    Write-Log -LogEntry 'Setting deployment status in Sharepoint list to In Progress...'

}

if ($NewUserSourceData.FieldValues.Workflow_x0020_Status -ne 'New') {

    Write-Log -LogEntry "Workflow status in Sharepoint list is $($NewUserSourceData.FieldValues.WorkflowStatus) - should be 'New'. Aborting." -PassThru

    throw "Workflow status in Sharepoint list is $($NewUserSourceData.FieldValues.Workflow_x0020_Status) - should be 'New'. Aborting."

}

$WorkflowStatus = 'In Progress'
$null = Set-PnPListItem -List $SharePointListName -Identity $SharepointListNewEmployeeId -Values @{'Workflow_x0020_Status' = $WorkflowStatus}

$CompanyData = [pscustomobject]@{

    CompanyName                = $NewUserSourceData.FieldValues.Company.LookupValue
    CompanyDomain              = $NewUserSourceData.FieldValues.Company_x003a_Domain.LookupValue
    CompanyCountry             = $NewUserSourceData.FieldValues.Company_x003a_Country.LookupValue
    CompanyCountryAbbriviation = $NewUserSourceData.FieldValues.Company_x003a_Country_x0020_abbr.LookupValue
    CompanyNameAbbriviation    = $NewUserSourceData.FieldValues.Company_x003a_Company_x0020_abbr.LookupValue
    CompanyPostalCode          = $NewUserSourceData.FieldValues.Company_x003a_PostalCode.LookupValue
    CompanyCity                = $NewUserSourceData.FieldValues.Company_x003a_City.LookupValue
    CompanyStreetAddress       = $NewUserSourceData.FieldValues.Company_x003a_StreetAddress.LookupValue
    HREmployeeArchiveUrl       = ($CompanyList.Where{$PSItem.FieldValues.Domain -eq $NewUserSourceData.FieldValues.Company_x003a_Domain.LookupValue}).FieldValues.HR_Emplyee_Archive.Url

}

Write-Output 'Contents of CompanyData variable:'
$CompanyData

if ($LoggingEnabled) {

    Write-Log -LogEntry "Normalizing username from: $(($NewUserSourceData.FieldValues.First_x0020_Name + '.' + $NewUserSourceData.FieldValues.Last_x0020_Name).ToLower())"

}

$FirstName = $NewUserSourceData.FieldValues.First_x0020_Name.Trim()

if ($NewUserSourceData.FieldValues.Middle_x0020_Name) {

    $MiddleName = $NewUserSourceData.FieldValues.Middle_x0020_Name.Trim()

}

$LastName = $NewUserSourceData.FieldValues.Last_x0020_Name.Trim()

$Username = Remove-StringLatinCharacters -String ($FirstName + '.' + $LastName).ToLower()
$Username = $Username.Replace(' ', '.')

if ($LoggingEnabled) {

    Write-Log -LogEntry "To: $Username"

}

switch ($NewUserSourceData.FieldValues.EmployeeCategory.LookupValue) {
    'Consultant' { 
       
        if ($NewUserSourceData.FieldValues.Middle_x0020_Name) {

            $DisplayName = ($FirstName + ' ' + $MiddleName + ' ' + $LastName + ' (' + $NewUserSourceData.FieldValues.CompanyNameConsultantExternal + ')')
      
        } else {

            $DisplayName = ($FirstName + ' ' + $LastName + ' (' + $NewUserSourceData.FieldValues.CompanyNameConsultantExternal + ')')

        }
       
        $UserPrincipalName = $Username + '@demo.crayon.com'
        $Licenses = @{

            Adobe     = $null
            Office365 = $null
            Other     = $null

        }
    }

    'External User' { 

        if ($NewUserSourceData.FieldValues.MiddleName) {

            $DisplayName = ($FirstName + ' ' + $MiddleName + ' ' + $LastName + ' (' + $NewUserSourceData.FieldValues.CompanyNameConsultantExternal + ')')
      
        } else {

            $DisplayName = ($FirstName + ' ' + $LastName + ' (' + $NewUserSourceData.FieldValues.CompanyNameConsultantExternal + ')')

        }

        $UserPrincipalName = $Username + '@demo.crayon.com'

        $Licenses = @{

            Adobe     = $null
            Office365 = $null
            Other     = $null

        }

    }

    default { 

        if ($NewUserSourceData.FieldValues.Middle_x0020_Name) {

            $DisplayName = ($FirstName + ' ' + $MiddleName + ' ' + $LastName)
      
        } else {

            $DisplayName = ($FirstName + ' ' + $LastName)

        }

        $UserPrincipalName = $Username + '@' + $CompanyData.CompanyDomain

        $Licenses = @{

            Adobe     = $null
            Office365 = 'E3', 'EMS'
            Other     = $null

        }
                
    }

}



$UserData = [pscustomobject]@{

    DisplayName          = $DisplayName
    FirstName            = $FirstName
    MiddleName           = $MiddleName
    LastName             = $LastName
    JobTitle             = $NewUserSourceData.FieldValues.Job_x0020_Title
    Department           = $NewUserSourceData.FieldValues.Department
    MobilePhone          = $NewUserSourceData.FieldValues.MobilePhone
    Manager              = $NewUserSourceData.FieldValues.Manager.Email
    UserPrincipalName    = $UserPrincipalName
    mailNickName         = $Username
    UsageLocation        = $CompanyData.CompanyCountryAbbriviation
    PostalCode           = $CompanyData.CompanyPostalCode
    City                 = $CompanyData.CompanyCity
    StreetAddress        = $CompanyData.CompanyStreetAddress
    EmployeeCategory     = $NewUserSourceData.FieldValues.Employee_x0020_Category
    ExternalEmailAddress = $NewUserSourceData.FieldValues.EmailAddress
    Licenses             = $Licenses

}

Write-Output 'Contents of UserData variable:'
$UserData

if ($LoggingEnabled) {

    Write-Log -LogEntry 'Source data for user provisioning:'
#
    Write-Log -LogEntry "DisplayName = $DisplayName"
    Write-Log -LogEntry "FirstName = $($FirstName)"
    Write-Log -LogEntry "MiddleName = $($MiddleName)"
    Write-Log -LogEntry "LastName = $($LastName)"
    Write-Log -LogEntry "JobTitle = $($NewUserSourceData.FieldValues.Job_x0020_Title)"
    Write-Log -LogEntry "Department = $($NewUserSourceData.FieldValues.Department)"
    Write-Log -LogEntry "MobilePhone = $($NewUserSourceData.FieldValues.MobilePhone)"
    Write-Log -LogEntry "Manager = $($NewUserSourceData.FieldValues.Manager.Email)"
    Write-Log -LogEntry "UserPrincipalName = $($UserPrincipalName)"
    Write-Log -LogEntry "mailNickName = $($Username)"
    Write-Log -LogEntry "UsageLocation = $($CompanyData.CompanyCountryAbbriviation)"
    Write-Log -LogEntry "PostalCode = $($CompanyData.CompanyPostalCode)"
    Write-Log -LogEntry "City = $($CompanyData.CompanyCity)"
    Write-Log -LogEntry "StreetAddress = $($CompanyData.CompanyStreetAddress)"
    Write-Log -LogEntry "EmployeeCategory = $($NewUserSourceData.FieldValues.Employee_x0020_Category)"
    Write-Log -LogEntry "ExternalEmailAddress = $($NewUserSourceData.FieldValues.EmailAddress)"
    Write-Log -LogEntry "Office365Licenses = $($Licenses.Office365 -join ',')"

}


$CreatedByEmail = $NewUserSourceData.FieldValues.Author.Email

Write-Output -InputObject 'Authenticating to Azure AD...'

if ($LoggingEnabled) {

    Write-Log -LogEntry 'Authenticating to Azure AD...'

}

$null = Connect-AzureAD -Credential $AADCredential

try {

    $TestAzureADUser = Get-AzureADUser -SearchString $Username -ErrorAction Stop

}

catch {

    Write-Output -InputObject "An error occured checking for existing user with the username $($UserData.UserPrincipalName)"

    if ($LoggingEnabled) {

        Write-Log -LogEntry "An error occured checking for existing user with the username $($UserData.UserPrincipalName)" -LogType Error

    }  

}

if ($TestAzureADUser) {

    if ($LoggingEnabled) {

        Write-Log -LogEntry "User $($UserData.UserPrincipalName) already exist in the Azure AD directory, aborting user provisioning..." -LogType Error

    }

    Write-Output -InputObject "User $($UserData.UserPrincipalName) already exist in the Azure AD directory, aborting user provisioning..."
    $ProvisioningStatus = 'User already exists in Azure AD'
    $WorkflowStatus = 'Failed'

    $TestAzureADUser

} else {

    if ($LoggingEnabled) {

        Write-Log -LogEntry "User $($UserData.UserPrincipalName) does not already exist in the Azure AD directory, continuing..."

    }

    Write-Output -InputObject "User $($UserData.UserPrincipalName) does not already exist in the Azure AD directory, continuing..."

    $PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
    $PasswordProfile.Password = (New-Password -MinimumPasswordLength 12 -Type Complex)

    $ADUserParameters = @{
        DisplayName       = $UserData.DisplayName
        GivenName         = $UserData.FirstName
        SurName           = $UserData.LastName
        JobTitle          = $UserData.JobTitle
        Department        = $UserData.Department
        Country           = $CompanyData.CompanyCountry
        PasswordProfile   = $PasswordProfile
        UserPrincipalName = $UserData.UserPrincipalName
        mailNickName      = $UserData.mailNickName
        UsageLocation     = $UserData.UsageLocation
        Mobile            = $UserData.MobilePhone
        City              = $UserData.City
        PostalCode        = $UserData.PostalCode
        StreetAddress     = $UserData.StreetAddress
        AccountEnabled    = $true
        ErrorAction       = 'Stop'
    }

    if ($UserData.MobilePhone) {

        $ADUserParameters.Mobile = $UserData.MobilePhone

    }

    try {

        $AzureADUser = New-AzureADUser @ADUserParameters
        $ProvisioningStatus = 'User provisioning succeeded'
        $WorkflowStatus = 'Completed'

        if ($LoggingEnabled) {

            Write-Log -LogEntry 'New user successfully created in Azure AD'

        }


    }

    catch {

        $ProvisioningStatus = "User provisioning failed. $($_.Exception.Message -split '\n' | Select-String message)"
        $WorkflowStatus = 'Failed'

        $_.Exception.Message

        if ($LoggingEnabled) {

            Write-Log -LogEntry $ProvisioningStatus -LogType Error
            Write-Log -LogEntry $_.Exception.Message -LogType Error

        }


    }

    if ($AzureADUser) {


        $ADUserManager = Get-AzureADUser -ObjectId $UserData.Manager

        if ($ADUserManager) {

            if ($LoggingEnabled) {

                Write-Log -LogEntry  "Setting user $($ADUserManager.DisplayName) as manager for new user $($AzureADUser.DisplayName)"

            }

            Write-Output -InputObject "Setting user $($ADUserManager.DisplayName) as manager for new user $($AzureADUser.DisplayName)"

            Set-AzureADUserManager -ObjectId $AzureADUser.ObjectId -RefObjectId $ADUserManager.ObjectId

        } else {

            Write-Output -InputObject "Unable to set user $($ADUserManager) as manager for new user $($AzureADUser.DisplayName) - manager not found in Azure AD"

            if ($LoggingEnabled) {

                Write-Log -LogEntry "Unable to set user $($ADUserManager) as manager for new user $($AzureADUser.DisplayName) - manager not found in Azure AD" -LogType Error

            }


        }

        if ($LoggingEnabled) {

            Write-Log -LogEntry 'Adding user to Azure AD groups for Group Based Licensing (if applicable)...'

        }
        Write-Output -InputObject 'Adding user to Azure AD groups for Group Based Licensing (if applicable)...'

        if (($UserData.Licenses.Office365 -split ',') -contains 'E3') {

            Write-Output -InputObject 'Adding user to Azure AD group NO.License.Office365_E3...'

            if ($LoggingEnabled) {

                Write-Log -LogEntry 'Adding user to Azure AD group NO.License.Office365_E3...'

            }

            try {

                $AzureADGroup = Get-AzureADGroup -ObjectId 06406b24-42f3-4bff-8316-5f3aaa84b9d3 -ErrorAction Stop
                $null = Add-AzureADGroupMember -ObjectId $AzureADGroup.ObjectId -RefObjectId $AzureADUser.ObjectId -ErrorAction Stop

            }

            catch {

                if ($LoggingEnabled) {

                    Write-Log -LogEntry "An error occured while adding user to Azure AD group NO.License.Office365_E3: $($_.Exception.Message)" -LogType Error

                }

                Write-Output "An error occured while adding user to Azure AD group NO.License.Office365_E3: $($_.Exception.Message)"

            }

        } elseif ($UserData.CreateEmailAccountExternalEmployee -eq $true) {

            Write-Output -InputObject 'Adding user to Azure AD group NO.License.Office365_E3... (CreateEmailAccountExternalEmployee: $true)'
            
                        if ($LoggingEnabled) {
            
                            Write-Log -LogEntry 'Adding user to Azure AD group NO.License.Office365_E3... (CreateEmailAccountExternalEmployee: $true)'
            
                        }
            
                        try {
            
                            $AzureADGroup = Get-AzureADGroup -ObjectId 06406b24-42f3-4bff-8316-5f3aaa84b9d3 -ErrorAction Stop
                            $null = Add-AzureADGroupMember -ObjectId $AzureADGroup.ObjectId -RefObjectId $AzureADUser.ObjectId -ErrorAction Stop
            
                        }
            
                        catch {
            
                            if ($LoggingEnabled) {
            
                                Write-Log -LogEntry "An error occured while adding user to Azure AD group NO.License.Office365_E3: $($_.Exception.Message)" -LogType Error
            
                            }
            
                            Write-Output "An error occured while adding user to Azure AD group NO.License.Office365_E3: $($_.Exception.Message)"
            
                        }

        }

        if (($UserData.Licenses.Office365 -split ',') -contains 'EMS') {

            if ($LoggingEnabled) {

                Write-Log -LogEntry 'Adding user to Azure AD group NO.CD.License.EMS_E3...'

            }

            Write-Output -InputObject 'Adding user to Azure AD group NO.CD.License.EMS_E3...'

            try {

                $AzureADGroup = Get-AzureADGroup -ObjectId 9860b262-f14f-466c-aae6-140d0b4bdc31 -ErrorAction Stop
                $null = Add-AzureADGroupMember -ObjectId $AzureADGroup.ObjectId -RefObjectId $AzureADUser.ObjectId -ErrorAction Stop

            }

            catch {

                if ($LoggingEnabled) {

                    Write-Log -LogEntry "An error occured while adding user to Azure AD group NO.License.EMS_E3: $($_.Exception.Message)" -LogType Error

                }

                Write-Output "An error occured while adding user to Azure AD group NO.License.EMS_E3: $($_.Exception.Message)"

            }

        }

        try {
            
            
            Write-Output -InputObject "Adding user to AD group All.Users.Access ..."
            
            if ($LoggingEnabled) {
            
                Write-Log -LogEntry "Adding user to AD group All.Users.Access ..."
            
            }
            
            $AllUsersADSecurityGroup = Get-AzureADGroup -ObjectId '503107f3-13cc-4221-922c-cb7b0748cc44'
            
            if ($AllUsersADSecurityGroup) {
            
                $null = Add-AzureADGroupMember -ObjectId $AllUsersADSecurityGroup.ObjectId -RefObjectId $AzureADUser.ObjectId -ErrorAction Stop
            
            } else {
            
                Write-Output -InputObject "AD group All.Users.Access not found, skipping..."
            
                if ($LoggingEnabled) {
            
                    Write-Log -LogEntry "AD group All.Users.Access not found, skipping..." -LogType Warning
            
                }
                
            
            }
            
        }
            
        catch {
            
            Write-Output "An error occured while adding user to AD group All.Users.Access : $($_.Exception.Message)"
            
            if ($LoggingEnabled) {
            
                Write-Log -LogEntry "An error occured while adding user to AD group All.Users.Access : $($_.Exception.Message)" -LogType Error
            
            }
            
        }

        try {

            $CompanyAzureADSecurityGroupName = $CompanyData.CompanyCountryAbbriviation + '.' + $CompanyData.CompanyNameAbbriviation + '.SG.ALL.Access'

            Write-Output -InputObject "Adding user to company security group $CompanyAzureADSecurityGroupName ..."

            if ($LoggingEnabled) {

                Write-Log -LogEntry "Adding user to company security group $CompanyAzureADSecurityGroupName ..."

            }

            $CompanyAzureADSecurityGroup = Get-AzureADGroup -SearchString $CompanyAzureADSecurityGroupName

            if ($CompanyAzureADSecurityGroup) {

                $null = Add-AzureADGroupMember -ObjectId $CompanyAzureADSecurityGroup.ObjectId -RefObjectId $AzureADUser.ObjectId -ErrorAction Stop

            } else {

                Write-Output -InputObject "Company security group $CompanyAzureADSecurityGroupName not found, skipping..."

                if ($LoggingEnabled) {

                    Write-Log -LogEntry "Company security group $CompanyAzureADSecurityGroupName not found, skipping..." -LogType Warning

                }
    

            }

        }

        catch {

            Write-Output "An error occured while adding user to Azure AD group $CompanyAzureADSecurityGroupName : $($_.Exception.Message)"

            if ($LoggingEnabled) {

                Write-Log -LogEntry "An error occured while adding user to Azure AD group $CompanyAzureADSecurityGroupName : $($_.Exception.Message)" -LogType Error

            }

        }


        if ($LoggingEnabled) {

            Write-Log -LogEntry "Disconnecting from Azure AD"

        }

        Write-Output "Disconnecting from Azure AD"
        Disconnect-AzureAD

        #Exchange Online

        if ($LoggingEnabled) {

            Write-Log -LogEntry "Connecting to Exchange Online"

        }

        Write-Output "Connecting to Exchange Online"

        $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $EXOCredential -Authentication Basic -AllowRedirection -ErrorAction Stop

        $null = Import-PSSession $Session -CommandName Get-User, Set-User, Get-UnifiedGroup, Add-UnifiedGroupLinks, Get-Mailbox, Set-Mailbox, Get-DistributionGroup, Add-DistributionGroupMember

        Write-Output 'Waiting for user to be provisioned in Exchange Online...'

        if ($LoggingEnabled) {

            Write-Log -LogEntry 'Waiting for user to be provisioned in Exchange Online...'

        }

        #Loop while waiting for Exchange provisioning
        $counter = 0
        Do {
            $finished = $false
            $ExchangeUser = Get-User -Identity $UserData.UserPrincipalName -ErrorAction Ignore
            if ($ExchangeUser) {
                $Finished = $true
            }

            
            if (($counter -lt 10) -and ($counter -gt 0)) {
                Start-Sleep -Seconds 30
            } Else {
                Start-Sleep -Seconds 60
            }
            
            if ($counter -gt 30) {
            
                $Finished = $true
            
            }
            
            $counter ++
            Write-Output "Wait loop: $counter"

            if ($LoggingEnabled) {

                Write-Log -LogEntry "Wait loop: $counter"

            }

        }
        until ($finished -eq $true)


        if ($ExchangeUser) {

            if ($LoggingEnabled) {

                Write-Log -LogEntry 'Configuring Company and Custom attributtes...'

            }

            Write-Output 'Configuring Company and Custom attributtes...'

            $ExchangeUser | Set-User -Company $CompanyData.CompanyName -Confirm:$false

            if ($UserData.EmployeeCategory -eq 'Consultant' -or $UserData.EmployeeCategory -eq 'External User') {

                if ($LoggingEnabled) {

                    Write-Log -LogEntry 'External user: Creating mail contact with external e-mail address...'

                }

                Write-Output 'External user: Creating mail contact with external e-mail address...'

                if ($UserData.ExternalEmailAddress) {

                    $MailContactParameters = @{
                        FirstName            = $UserData.FirstName
                        LastName             = $UserData.LastName
                        DisplayName          = $UserData.DisplayName
                        Name                 = $UserData.DisplayName
                        Alias                = $UserData.mailNickName
                        ExternalEmailAddress = $UserData.ExternalEmailAddress
                    }

                    $null = New-MailContact @MailContactParameters
  
                } else {

                    Write-Output 'Unable to create mail contact with external e-mail address due to missing value for property ExternalEmailAddress'

                    if ($LoggingEnabled) {

                        Write-Log -LogEntry 'Unable to create mail contact with external e-mail address due to missing value for property ExternalEmailAddress' -LogType Warning

                    }

                }


            } else {

                # Configuring ExtensionCustomAttribute 1-4 (mailbox properties)

                Write-Output 'Waiting for mailbox to be provisioned in Exchange Online...'

                if ($LoggingEnabled) {

                    Write-Log -LogEntry 'Waiting for mailbox to be provisioned in Exchange Online...'

                }

                #Loop while waiting for Exchange provisioning
                $counter = 0
                Do {
                    $finished = $false
                    $ExchangeMailbox = Get-Mailbox -Identity $UserData.UserPrincipalName -ErrorAction Ignore
                    if ($ExchangeMailbox) {
                        $Finished = $true
                    }

            
                    if (($counter -lt 10) -and ($counter -gt 0)) {
                        Start-Sleep -Seconds 30
                    } Else {
                        Start-Sleep -Seconds 60
                    }
            
                    if ($counter -gt 30) {
            
                        $Finished = $true
            
                    }
            
                    $counter ++
                    Write-Output "Wait loop: $counter"

                    if ($LoggingEnabled) {

                        Write-Log -LogEntry "Wait loop: $counter"

                    }

                }
                until ($finished -eq $true)

                if ($ExchangeMailbox) {

                    if ($LoggingEnabled) {

                        Write-Log -LogEntry 'Configuring ExtensionCustomAttribute 1-4 (mailbox properties)'

                    }

                    # Hard coded dummy data out until properties is provisioned in Sharepoint list
                    $ExchangeMailbox | Set-Mailbox -ExtensionCustomAttribute1 ICEData1 -Confirm:$false
                    $ExchangeMailbox | Set-Mailbox -ExtensionCustomAttribute2 ICEData2 -Confirm:$false
                    $ExchangeMailbox | Set-Mailbox -ExtensionCustomAttribute3 ICEData3 -Confirm:$false
                    $ExchangeMailbox | Set-Mailbox -ExtensionCustomAttribute4 EmployeePercent -Confirm:$false

                    # Distribution group membership

                    try {

                        $CompanyDistributionGroupName = $CompanyData.CompanyCountryAbbriviation + '.' + $CompanyData.CompanyNameAbbriviation + '.ALL.Employees'

                        Write-Output -InputObject "Adding user to company distribution group $CompanyDistributionGroupName ..."

                        if ($LoggingEnabled) {

                            Write-Log -LogEntry "Adding user to company distribution group $CompanyDistributionGroupName ..."

                        }

                        $CompanyDistributionGroup = Get-DistributionGroup -Identity $CompanyDistributionGroupName -ErrorAction SilentlyContinue

                        if ($CompanyDistributionGroup) {

                            $null = Add-DistributionGroupMember -Identity $CompanyDistributionGroupName -Member $ExchangeMailbox.UserPrincipalName -ErrorAction Stop

                        } else {

                            Write-Output -InputObject "Company distribution group $CompanyDistributionGroupName not found, skipping..."

                            if ($LoggingEnabled) {

                                Write-Log -LogEntry "Company distribution group $CompanyDistributionGroupName not found, skipping..." -LogType Warning

                            }
    

                        }

                    }

                    catch {

                        Write-Output "An error occured while adding user to distribution group $CompanyDistributionGroupName : $($_.Exception.Message)"

                        if ($LoggingEnabled) {

                            Write-Log -LogEntry "An error occured while adding user to distribution group $CompanyDistributionGroupName : $($_.Exception.Message)" -LogType Error

                        }

                    }

                } else {

                    Write-Output "Mailbox $($UserData.UserPrincipalName) not found in Exchange Online, distribution group and ExtensionCustomAttribute not configured"


                    if ($LoggingEnabled) {

                        Write-Log -LogEntry "Mailbox $($UserData.UserPrincipalName) not found in Exchange Online, distribution group and ExtensionCustomAttribute not configured" -LogType Error

                    }

                }

            }

        } else {

            Write-Output "User $($UserData.UserPrincipalName) not found in Exchange Online"

            if ($LoggingEnabled) {

                Write-Log -LogEntry "User $($UserData.UserPrincipalName) not found in Exchange Online" -LogType Warning

            }

        }

        if ($LoggingEnabled) {

            Write-Log -LogEntry "Disconnecting from Exchange Online"

        }

        Write-Output "Disconnecting from Exchange Online"
        Remove-PSSession $Session

    }

}

if ($LoggingEnabled) {

    Write-Log -LogEntry "Status: $ProvisioningStatus"
    Write-Log -LogEntry "Updating Sharepoint list..."

}

Write-Output -InputObject "Status: $ProvisioningStatus"
Write-Output -InputObject "Updating Sharepoint list..."

$null = Set-PnPListItem -List $SharePointListName -Identity $SharepointListNewEmployeeId -Values @{'Workflow_x0020_Status' = $WorkflowStatus}


if ($CreatedByEmail) {

    if ($LoggingEnabled) {

        Write-Log -LogEntry "Sending e-mail notification with provisioning status to list item author $CreatedByEmail "

    }

    Write-Output -InputObject "Sending e-mail notification with provisioning status to list item author $CreatedByEmail "

    $MailParameters = @{
        From       = 'Crayon Demo - User Management <svc_azureautomation@crayondemos.onmicrosoft.com>'
        Subject    = "Status for new user account: $($UserData.DisplayName)"
        Body       = @"
$ProvisioningStatus

Username: $($UserData.UserPrincipalName)
Password: $($ADUserParameters.PasswordProfile.Password)

The new user will be prompted to change the password during initial login at portal.office.com.

Regards
Crayon Demo

Do not respond to this e-mail, as this is an unmonitored e-mail address sent from an automated process.
"@
        SmtpServer = 'smtp.office365.com'
        Port       = '587'
        Credential = $EXOCredential
        Encoding    = 'Unicode'
        UseSsl     = $true
    }

    $To = @()

    if ($NewUserSourceData.FieldValues.OnBehalf.Email) {

        if ($LoggingEnabled) {

            Write-Log -LogEntry "Sending e-mail notification with provisioning status to On Behalf user: $($NewUserSourceData.FieldValues.OnBehalf.Email)"

        }

        Write-Output -InputObject "Sending e-mail notification with provisioning status to On Behalf user: $($NewUserSourceData.FieldValues.OnBehalf.Email)"

        $To += $CreatedByEmail

    } else {

        $To += $CreatedByEmail
        
    }

    $To += 'jan.egil.ring@crayon.com'
    $To += 'jan.egil.ring@outlook.com'

    $MailParameters.Add('To', $To)

    if ($LogPath) {

        $MailParameters.Add('Attachments', $LogPath)

    }

    Send-MailMessage @MailParameters

}

if ($LoggingEnabled) {

    Write-Log -LogEntry "Runbook finished $(Get-Date)"

}

Write-Output -InputObject "Runbook finished $(Get-Date)"