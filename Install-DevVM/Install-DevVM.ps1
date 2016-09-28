#-----------------------
# Install-DevVM.ps1
#-----------------------

# Wrapper for installing a development VM on Microsoft corpnet.
# Currently has a few hard-coded things for me (@jhowardmsft)
# Invokes the same processing for setting up a production CI
# server, but also turns on KD, net uses to the machine where
# the development sources are, installs VSCode & LiteIDE,
# creates a shortcut for a development prompt, plus sets auto-logon.
# Also assumes that this is running from \\redmond\osg\teams\....\team\jhoward\docker\ci\w2w\Install-DevVM

param(
    [Parameter(Mandatory=$true)][string]$Username,
    [Parameter(Mandatory=$true)][string]$Password,
    [Parameter(Mandatory=$false)][string]$Branch
)
$ErrorActionPreference = 'Stop'

#$DEV_MACHINE="jhoward-z420"
$DEV_MACHINE_DRIVE="c"

function Test-Nano() {
    $EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID').EditionId
    return (($EditionId -eq "ServerStandardNano") -or
            ($EditionId -eq "ServerDataCenterNano") -or
            ($EditionId -eq "NanoServer") -or
            ($EditionId -eq "ServerTuva"))
}

function Copy-File {
    [CmdletBinding()]
    param(
        [string] $SourcePath,
        [string] $DestinationPath
    )

    if ($SourcePath -eq $DestinationPath) { return }

    if (Test-Path $SourcePath) {
        Copy-Item -Path $SourcePath -Destination $DestinationPath
    } elseif (($SourcePath -as [System.URI]).AbsoluteURI -ne $null) {
        if (Test-Nano) {
            $handler = New-Object System.Net.Http.HttpClientHandler
            $client = New-Object System.Net.Http.HttpClient($handler)
            $client.Timeout = New-Object System.TimeSpan(0, 30, 0)
            $cancelTokenSource = [System.Threading.CancellationTokenSource]::new()
            $responseMsg = $client.GetAsync([System.Uri]::new($SourcePath), $cancelTokenSource.Token)
            $responseMsg.Wait()

            if (!$responseMsg.IsCanceled) {
                $response = $responseMsg.Result
                if ($response.IsSuccessStatusCode) {
                    $downloadedFileStream = [System.IO.FileStream]::new($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                    $copyStreamOp = $response.Content.CopyToAsync($downloadedFileStream)
                    $copyStreamOp.Wait()
                    $downloadedFileStream.Close()
                    if ($copyStreamOp.Exception -ne $null) {
                        throw $copyStreamOp.Exception
                    }
                }
            }
        }
        elseif ($PSVersionTable.PSVersion.Major -ge 5) {
            # We disable progress display because it kills performance for large downloads (at least on 64-bit PowerShell)
            $ProgressPreference = 'SilentlyContinue'
            wget -Uri $SourcePath -OutFile $DestinationPath -UseBasicParsing
            $ProgressPreference = 'Continue'
        } else {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($SourcePath, $DestinationPath)
        }
    } else {
        throw "Cannot copy from $SourcePath"
    }
}



Try {
    Write-Host -ForegroundColor Yellow "INFO: John's dev script for dev VM installation"
    set-PSDebug -Trace 0  # 1 to turn on

    if ([string]::IsNullOrWhiteSpace($Branch)) {
        $Branch=""

        $hostname=$env:COMPUTERNAME.ToLower()
        Write-Host "Matching $hostname for a branch type..."

        foreach ($line in Get-Content ..\config\config.txt) {
            $line=$line.Trim()
            if (($line[0] -eq "#") -or ($line -eq "")) {
                continue
            }
            $elements=$line.Split(",")
            if ($elements.Length -ne 2) {
                continue
            }
            if (($elements[0].Length -eq 0) -or ($elements[1].Length -eq 0)) {
                continue
            }
            if ($hostname -match $elements[0]) {
                $Branch=$elements[1]
                Write-Host $hostname matches $elements[0]
                break
            }
        }
        if ($Branch.Length -eq 0) { Throw "Branch not supplied and $hostname regex match not found in configuration" }
        Write-Host "Branch matches $Branch through "$elements[0]
    }
    $Branch = $Branch.ToLower()

    # Check if branch is valid by looking if directory exists
    if ($False -eq $(Test-Path -PathType Container ..\$Branch)) {
        Throw "Branch doesn't appear to be valid"
    }

    # Setup Debugging
    if ($(Test-Path "HKLM:software\microsoft\virtual machine\guest") -eq $True) {
        Write-Host "INFO: KD to COM1. Configure COM1 to \\.\pipe\<VMName>"
        bcdedit /debug on
        bcdedit /dbgsettings serial debugport:1 baudrate:115200
    }

    if (-not (Test-Nano)) {
        if ($null -eq $(Get-Command code -erroraction silentlycontinue)) {
            # VSCode (useful for markdown editing). But really annoying as I can't find a way to
            # not make it launch after setup completes, so blocks. Workaround isn't nice but works
            $ErrorActionPreference = 'Stop'
            if (-not (Test-Path $env:Temp\vscodeinstaller.exe)) {
                Write-Host "INFO: Downloading VSCode installer"
                Copy-File -SourcePath "https://go.microsoft.com/fwlink/?LinkID=623230" -DestinationPath "$env:Temp\vscodeinstaller.exe"
            }
            Write-Host "INFO: Installing VSCode"
            $j = Start-Job -ScriptBlock {Start-Process -wait "$env:Temp\vscodeinstaller.exe" -ArgumentList "/silent /dir:c:\vscode"}
            Write-Host "INFO: Waiting for installer to complete"
            Start-Sleep 60
            Write-Host "INFO: Force stopping vscode, iexplore and edge (annoying workaround...)"
            Get-Process *code* -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
            Get-Process *iexplore* -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
            Get-Process *MicrosoftEdge* -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
            Write-Host "INFO: Waiting on job"
            wait-Job $j.id | Out-Null
         }
    }

    Write-Host "INFO: Configuring automatic logon"
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" /v AutoAdminLogon /t REG_DWORD /d 1 /f
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" /v DefaultUserName /t REG_SZ /d "$Username" /f
    REG ADD "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" /v DefaultPassword /t REG_SZ /d "$Password" /f

    if (-not (Test-Nano)) {
        Write-Host "INFO: Disabling real time monitoring"
        set-mppreference -disablerealtimemonitoring $true
    }
    Write-Host "INFO: Setting execution policy"
    Set-ExecutionPolicy bypass

    if (-not (Test-Nano)) {
        Write-Host "INFO: Unblocking the shortcut file"
        Unblock-File .\docker-docker-shortcut.ps1
        Write-Host "INFO: Running the shortcut file"
        powershell -command .\docker-docker-shortcut.ps1
    }

    Write-Host "INFO: Removing docker.exe if it exists"
    Remove-Item c:\windows\system32\docker.exe -ErrorAction SilentlyContinue
    Write-Host "INFO: Removing dockerd.exe if it exists"
    Remove-Item c:\windows\system32\dockerd.exe -ErrorAction SilentlyContinue

    if (-not (Test-Nano)) {
        Write-Host "INFO: Enabling remote desktop in registry"
        set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server'-name "fDenyTSConnections" -Value 0
        set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -Value 0
        Write-Host "INFO: Enabling remote desktop in firewall"
        enable-netfirewallrule -displaygroup 'Remote Desktop'
    }

    Write-Host "INFO: Turning off the firewall"
    NetSh Advfirewall set allprofiles state off

    Write-Host "INFO: Copying some utilities (pipelist, sfpcopy, windiff)"
    Copy-Item pipelist.exe c:\windows\system32  -ErrorAction SilentlyContinue
    Copy-Item sfpcopy.exe c:\windows\system32 -ErrorAction SilentlyContinue
    Copy-Item windiff.exe c:\windows\system32 -ErrorAction SilentlyContinue

    Write-Host "INFO: Setting environment variables"
    $env:GOPATH=$DEV_MACHINE_DRIVE+":\go\src\github.com\docker\docker\vendor;"+$DEV_MACHINE_DRIVE+":\go"
    $env:Path="$env:Path;c:\gopath\bin;"+$DEV_MACHINE_DRIVE+":\docker\utils"
    $env:LOCAL_CI_INSTALL="1"
    $env:Branch="$Branch"

    # Persist them. Note this way for coreCLR compatibility.
    setx GOPATH $env:GOPATH /M
    setx PATH $env:Path /M
    setx LOCAL_CI_INSTALL $env:LOCAL_CI_INSTALL /M
    setx BRANCH $env:BRANCH /M

    mkdir c:\packer -ErrorAction SilentlyContinue
    Copy-Item "..\common\Bootstrap.ps1" c:\packer\ -ErrorAction SilentlyContinue
    Unblock-File c:\packer\Bootstrap.ps1
    . "$env:SystemDrive\packer\Bootstrap.ps1" -Branch $Branch -Doitanyway

    if (-not (Test-Nano)) {
        echo $(date) > "c:\users\public\desktop\$Branch.txt"
    }

} Catch [Exception] {
    Write-Host -ForegroundColor Red ("`r`n`r`nERROR: Failed '$_'")
    exit 1
}
Finally {
    Write-Host -ForegroundColor Yellow "INFO: Install completed at $(date)"
}
