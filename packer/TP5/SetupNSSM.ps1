#-----------------------
# SetupNSSM.ps1
# Note this runs post-sysprep, so have to delete the scheduled task
#-----------------------

Write-Host "INFO: Executing SetupNSSM.ps1"

# Stop on error
$ErrorActionPreference="stop"


# Create directory for storing the nssm configuration
mkdir $env:ProgramData\docker -ErrorAction SilentlyContinue 2>&1 | Out-Null


# Install NSSM by extracting archive and placing in system32
Write-Host "INFO: Downloading NSSM configuration file..."
$wc=New-Object net.webclient;$wc.Downloadfile("https://raw.githubusercontent.com/jhowardmsft/docker-w2wCIScripts/master/nssmdocker.W2WCIServers.cmd","$env:ProgramData\docker\nssmdocker.cmd")
Write-Host "INFO: Downloading NSSM..."
$wc=New-Object net.webclient;$wc.Downloadfile("https://nssm.cc/release/nssm-2.24.zip","$env:Temp\nssm.zip")
Write-Host "INFO: Extracting NSSM..."
Expand-Archive -Path $env:Temp\nssm.zip -DestinationPath $env:Temp
Write-Host "INFO: Installing NSSM..."
Copy-Item $env:Temp\nssm-2.24\win64\nssm.exe $env:SystemRoot\System32


# Configure the docker NSSM service
Write-Host "INFO: Configuring NSSM..."
Start-Process -Wait "nssm" -ArgumentList "install docker $($env:SystemRoot)\System32\cmd.exe /s /c $env:Programdata\docker\nssmdocker.cmd < nul"
Start-Process -Wait "nssm" -ArgumentList "set docker DisplayName Docker Daemon"
Start-Process -Wait "nssm" -ArgumentList "set docker Description Docker control daemon for CI testing"
Start-Process -Wait "nssm" -ArgumentList "set docker AppStderr $env:Programdata\docker\nssmdaemon.log"
Start-Process -Wait "nssm" -ArgumentList "set docker AppStdout $env:Programdata\docker\nssmdaemon.log"
Start-Process -Wait "nssm" -ArgumentList "set docker AppStopMethodConsole 30000"

echo "SetupNSSM.ps1 ran" > $env:SystemDrive\packer\SetupNSSM.txt

# Delete the scheduled task
$ConfirmPreference='none'
Get-ScheduledTask 'SetupNSSM' | Unregister-ScheduledTask

Write-Host "INFO: SetupNSSM.ps1 completed"
