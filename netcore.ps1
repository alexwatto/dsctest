New-EventLog -LogName Application -Source "Terraform Setup Script"
iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/alexwatto/dsctest/master/install-modules.ps1'))
Install-Module -Name xWebAdministration -Force


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
$newScript = {
    function choco
    {

        choco install urlrewrite /y
        choco install dotnet4.7.2 /y
        choco install dotnetcore-windowshosting /y

    }
  }
    chocoInstall;
    Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Installed Chocolatey."
    Invoke-Command -ScriptBlock $newScript
    Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Installed Choco Features."
    iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/alexwatto/dsctest/master/ssl_hardening_v3.ps1'))



}

ConfigureIIS -NodeName 'localhost' -InetpubRoot 'F:\inetpub'

Start-DSCConfiguration -Path .\ConfigureIIS -Wait -Verbose -Force

Write-EventLog -LogName Application -Source "Terraform Setup Script" -EventID 3001 -Message "Configured IIS."

Invoke-Command -ScriptBlock $ScriptBlock
