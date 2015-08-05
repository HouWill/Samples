﻿# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#

function OSSetup ($Ensure = "Present")
{
    configuration WebConfig
    {
        WindowsFeature IIS
        {
            Name="Web-Server"
            Ensure=$Ensure
        }
        <#
        cCreateFileShare CreateShare
        {
            ShareName = 'temp'
            Path      = 'c:\temp'
            Ensure    = 'Present'
        }
        xHotfix m1
        {
            Uri = "http://hotfixv4.microsoft.com/Microsoft%20Office%20SharePoint%20Server%202007/sp2/officekb956056fullfilex64glb/12.0000.6327.5000/free/358323_intl_x64_zip.exe"
            Id = "KB956056" 
            Ensure="Present"
        }#>
    }
    md c:\temp -ea 0
    
    WebConfig -OutputPath C:\temp\config  -ConfigurationData $AllNodes
    
    Start-DscConfiguration c:\temp\config -ComputerName localhost -Wait -verbose -force
}

function ChefInstall ([string]$MSIPath)
{

    $recipe = @"
file 'c:/temp/helloworld.txt' do
  content 'hello world'
end

remote_file 'c:/temp/7zip.msi' do
  source "http://www.7-zip.org/a/7z938-x64.msi"
end

windows_package '7-Zip 9.38 (x64 edition)' do
  source 'c:/temp/7zip.msi'
  action :install
end
"@
    configuration ChefConfig
    {
        File SevenZip
        {
            DestinationPath = 'c:\temp\7zip.rb'
            Contents = $Recipe
        }
        Package ChefPackage
        {
            Path = $MSIPath
            Name = "Chef Client v12.3.0"
            Ensure = "Present"
            ProductId = ""
        }
    }

    ChefConfig -OutputPath C:\temp\config  -ConfigurationData $AllNodes
    Start-DscConfiguration c:\temp\config -ComputerName localhost -Wait -verbose -force

    C:\opscode\chef\bin\chef-apply.bat C:\temp\7zip.rb | Out-File 'c:\temp\chef-apply.log'
}

#ChefInstall -MSIPath 'https://opscode-omnibus-packages.s3.amazonaws.com/windows/2008r2/x86_64/chef-client-12.3.0-1.msi'