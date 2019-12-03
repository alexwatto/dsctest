New-EventLog -LogName Application -Source "Terraform Setup Script"
Install-Module -Name xWebAdministration -Force

## Parameters
$admWebsite = "shop-admin.bootshearingcare.com"
$mvcWebsite = "shop.bootshearingcare.com"


Configuration ConfigureDisk
{
    param
    (       
        [String[]]$NodeName = 'localhost',
        [String]$Drive = 'F',
        [Int]$DiskNumber = 2
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration, xStorage

    Node $NodeName
    {
        # Initialize disks
        xWaitforDisk Disk2
        {
            DiskId = "$DiskNumber"
            DiskIdType = 'Number'
            RetryCount = 60
            RetryIntervalSec = 60
        }

        xDisk FVolume
        {
            DiskId = "$DiskNumber"
            DriveLetter = "$Drive"
            DiskIdType = 'Number'
            FSLabel = 'Data'
        }
    }
}

Configuration ConfigureIIS
{
    param
    (       
        [String[]]$NodeName = 'localhost',
        [String]$InetpubRoot   = 'F:\inetpub'
    )
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration, cNtfsAccessControl

    Node $NodeName
    {
        # Install features
        WindowsFeature WebServer
        {
            Ensure = "Present"
            Name   = "Web-Server"
        }

        WindowsFeature MgmtConsole
        {
            Ensure = "Present"
            Name   = "Web-Mgmt-Console"
        }

        WindowsFeature AspNet45
        { 
            Ensure = "Present"
            Name   = "Web-Asp-Net45"
        }

        WindowsFeature HttpRedirect
        { 
            Ensure = "Present"
            Name   = "Web-Http-Redirect"
        }

        WindowsFeature DynamicCompression
        { 
            Ensure = "Present"
            Name   = "Web-Dyn-Compression"
        }

        WindowsFeature IpSecurity 
        { 
            Ensure = "Present"
            Name   = "Web-IP-Security"
        }

        WindowsFeature BasicAuth
        { 
            Ensure = "Present"
            Name   = "Web-Basic-Auth"
        }

        WindowsFeature UrlAuth
        { 
            Ensure = "Present"
            Name   = "Web-Url-Auth"
        }

        WindowsFeature WCF
        { 
            Ensure               = "Present"
            Name                 = "NET-WCF-Services45"
            IncludeAllSubFeature = $true
        }
        
        WindowsFeature WAS
        { 
            Ensure               = "Present"
            Name                 = "WAS"
            IncludeAllSubFeature = $true
        }

        # Create IIS Logs folder
        File IISLogs
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($InetpubRoot)\IISLogs"
        }

        # Grant the IIS_USRS group access to Logs
        cNtfsPermissionEntry IISLogs
        {
            Ensure    = 'Present'
            Principal = 'IIS_IUSRS'
            Path      = "$($InetpubRoot)\IISLogs"
            ItemType  = 'Directory'
            AccessControlInformation = @(
                cNtfsAccessControlInformation
                {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn = '[File]IISLogs'
        }

        #Stop the default website
        xWebsite DefaultSite 
        {
            Ensure          = 'Present'
            Name            = 'Default Web Site'
            State           = 'Stopped'
            PhysicalPath    = 'C:\inetpub\wwwroot'
            DependsOn       = '[WindowsFeature]WebServer'
        }

        # Setup IIS Logs
        xIisLogging Logging
        {
            LogPath = "$($InetpubRoot)\IISLogs"
            Logflags = @('Date','Time','ClientIP','UserName','ServerIP')
            LoglocalTimeRollover = $True
            LogTruncateSize = '2097152'
            LogFormat = 'W3C'
            DependsOn = '[File]IISLogs'
        }
    }
}

Configuration CreateKenticoAdminWebsite
{
    param
    (       
        [String[]]$NodeName = 'localhost',
        [String]$WwwRoot = 'f:\inetpub\wwwroot',
        [String]$Website = 'shop-admin.bootshearingcare.com'
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration, cNtfsAccessControl

    $junctionlinks = "$($WwwRoot)\JunctionLinks\Admin"

    Node $NodeName
    {
        File Website
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$WwwRoot\$Website\v1.00"
        }

        File JunctionLinks
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$junctionlinks"
        }

        File AzureCache
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\AzureCache"
        }

        File AureTemp
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\AzureTemp"
        }

        File CMSFiles
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\CMSFiles"
        }

        File Media
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\Media"
        }

        File SiteAttachments
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\SiteAttachments"
        }

        File SmartSearch
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\SmartSearch"
        }

        # Create apppool
        xWebAppPool AppPool
        {
            Name                  = "$Website"
            managedRuntimeVersion = 'v4.0'
            identityType          = 'ApplicationPoolIdentity'
            Ensure                = 'Present'
            State                 = 'Started'
        }

        # Create website
        xWebsite Website
        {
            Name = "$Website"
            PhysicalPath = "$WwwRoot\$Website\v1.00"
            ApplicationPool = "$Website"
            BindingInfo = @(
                MSFT_xWebBindingInformation
                {
                    Protocol  = 'HTTP' 
                    Port      = '80'
                    IPAddress = '*'
                    HostName  = "$Website"

                }
            )
            Ensure = 'Present'
            State = 'Started'

            DependsOn = '[xWebAppPool]AppPool'
        }
        
        # Update folder permission
        cNtfsPermissionEntry Website
        {
            Ensure    = 'Present'
            Principal = 'IIS_IUSRS'
            Path      = "$WwwRoot\$Website"
            AccessControlInformation = @(
                cNtfsAccessControlInformation
                {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn = '[File]Website'
        }

        cNtfsPermissionEntry JunctionLinks
        {
            Ensure    = 'Present'
            Principal = 'IIS_IUSRS'
            Path      = "$junctionlinks"
            AccessControlInformation = @(
                cNtfsAccessControlInformation
                {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn = '[File]JunctionLinks'
        }
    }
}

Configuration CreateKenticoMvcWebsite
{
    param
    (       
        [String[]]$NodeName = 'localhost',
        [String]$WwwRoot = 'f:\inetpub\wwwroot',
        [String]$Website = 'shop.bootshearingcare.com'
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration, cNtfsAccessControl

    $junctionlinks = "$($WwwRoot)\JunctionLinks\MVC"

    Node $NodeName
    {
        File Website
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$WwwRoot\$Website\v1.00"
        }

        File JunctionLinks
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$junctionlinks"
        }

        File Media
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\Media"
        }

        File SiteAttachments
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\SiteAttachments"
        }

        File SmartSearch
        {
            Ensure = 'Present'
            Type = 'Directory'
            DestinationPath = "$($junctionlinks)\SmartSearch"
        }

        # Create apppool
        xWebAppPool AppPool
        {
            Name                  = "$Website"
            managedRuntimeVersion = 'v4.0'
            identityType          = 'ApplicationPoolIdentity'
            Ensure                = 'Present'
            State                 = 'Started'
        }

        # Create website
        xWebsite Website
        {
            Name = "$Website"
            PhysicalPath = "$WwwRoot\$Website\v1.00"
            ApplicationPool = "$Website"
            BindingInfo = @(
                MSFT_xWebBindingInformation
                {
                    Protocol  = 'HTTP' 
                    Port      = '80'
                    IPAddress = '*'
                    HostName  = "$Website"

                }
            )
            Ensure = 'Present'
            State = 'Started'

            DependsOn = '[xWebAppPool]AppPool'
        }
        
        # Update folder permission
        cNtfsPermissionEntry Website
        {
            Ensure    = 'Present'
            Principal = 'IIS_IUSRS'
            Path      = "$WwwRoot\$Website"
            AccessControlInformation = @(
                cNtfsAccessControlInformation
                {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn = '[File]Website'
        }

        cNtfsPermissionEntry JunctionLinks
        {
            Ensure    = 'Present'
            Principal = 'IIS_IUSRS'
            Path      = "$junctionlinks"
            AccessControlInformation = @(
                cNtfsAccessControlInformation
                {
                    AccessControlType  = 'Allow'
                    FileSystemRights   = 'Modify'
                    Inheritance        = 'ThisFolderSubfoldersAndFiles'
                    NoPropagateInherit = $false
                }
            )
            DependsOn = '[File]JunctionLinks'
        }
    }
}

Configuration InboundRules
{
    Import-DSCResource -ModuleName NetworkingDsc

    Node localhost
    {
        Firewall AllowIISRemoteManagement
        {
            Name                  = 'AllowIISRemoteManagement'
            DisplayName           = 'Allow IIS Remote Management from Bastion'
            Ensure                = 'Present'
            Enabled               = 'True'
            Direction             = 'Inbound'
            LocalPort             = '8172'
            Protocol              = 'TCP'
            Description           = 'Allow IIS Remote Management from Bastion'
            RemoteAddress         = '10.0.1.0/24'
            Action                = 'Allow'
        }

        Firewall AllowWinrmBastion
        {
            Name                  = 'AllowWinrmBastion'
            DisplayName           = 'Allow Winrm from Bastion'
            Ensure                = 'Present'
            Enabled               = 'True'
            Direction             = 'Inbound'
            LocalPort             = ('5985','5986')
            Protocol              = 'TCP'
            Description           = 'Allow Winrm from Bastion'
            RemoteAddress         = '10.0.1.0/24'
            Action                = 'Allow'
        }
    }
}

Configuration WebConfig
{
  Import-DscResource -ModuleName PsDesiredStateConfiguration
  
  Node localhost
  {
    Registry IISConfig
    {
        Ensure = "Present"
        Key = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\InetStp\Configuration"
        ValueName = "MaxWebConfigFileSizeInKB"
        ValueData = "2000"
        ValueType = "Dword"
        Force = $true
        Hex = $false
    }
    Registry IISConfig2
    {
        Ensure = "Present"
        Key = "HKLM:\SOFTWARE\Microsoft\InetStp\Configuration"
        ValueName = "MaxWebConfigFileSizeInKB"
        ValueData = "2000"
        ValueType = "Dword"
        Force = $true
        Hex = $false
    }
  }
}
$ScriptBlock = {
    function chocoInstall 
    {
        $chocoExePath = 'C:\ProgramData\Chocolatey\bin'

        if ($($env:Path).ToLower().Contains($($chocoExePath).ToLower())) {
          echo "Chocolatey found in PATH, skipping install..."
          Exit
        }

        # Add to system PATH
        $systemPath = [Environment]::GetEnvironmentVariable('Path',[System.EnvironmentVariableTarget]::Machine)
        $systemPath += ';' + $chocoExePath
        [Environment]::SetEnvironmentVariable("PATH", $systemPath, [System.EnvironmentVariableTarget]::Machine)

        # Update local process' path
        $userPath = [Environment]::GetEnvironmentVariable('Path',[System.EnvironmentVariableTarget]::User)
        if($userPath) {
          $env:Path = $systemPath + ";" + $userPath
        } else {
          $env:Path = $systemPath
        }

        # Run the installer
        iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))

        refreshenv
    }

    function choco
    {

        choco install urlrewrite /y
        choco install dotnet4.7.2 /y
        #choco install dotnetcore-windowshosting /y

    }
    
    chocoInstall;
    Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Installed Chocolatey."
    choco;
    Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Installed Choco Features."
    iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/alexwatto/dsctest/master/ssl_hardening_v3.ps1'))



}
iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/alexwatto/dsctest/master/install-modules.ps1'))

Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Hi Ant Can You See Me?."
ConfigureDisk -NodeName 'localhost' -Drive 'F' -DiskNumber 2
ConfigureIIS -NodeName 'localhost' -InetpubRoot 'F:\inetpub'
CreateKenticoAdminWebsite -NodeName 'localhost' -WwwRoot 'F:\inetpub\wwwroot' -Website $admWebsite 
CreateKenticoMvcWebsite -NodeName 'localhost' -WwwRoot 'F:\inetpub\wwwroot' -Website $mvcWebsite 
InboundRules
WebConfig



Start-DSCConfiguration -Path .\ConfigureDisk -Wait -Verbose -Force
Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Configured Disk."
Start-DSCConfiguration -Path .\ConfigureIIS -Wait -Verbose -Force
Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Configured IIS."
Start-DSCConfiguration -Path .\CreateKenticoAdminWebsite -Wait -Verbose -Force
Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Created Admin Site."
Start-DSCConfiguration -Path .\CreateKenticoMvcWebsite -Wait -Verbose -Force
Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Created MVC Site."
Start-DSCConfiguration -Path .\InboundRules -Wait -Verbose -Force
Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Added Firewall Rules."
Start-DSCConfiguration -Path .\WebConfig -Wait -Verbose -Force
Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Changed Web.Config Max Size."
Invoke-Command -ScriptBlock $ScriptBlock

