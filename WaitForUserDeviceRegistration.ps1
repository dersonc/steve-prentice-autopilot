# WaitForUserDeviceRegistration.ps1
#
# Version 1.9
#
# Steve Prentice, 2020
# Modified by Anderson Cassimiro, 2023
#
# Used to pause device ESP during Autopilot Hybrid Join to wait for
# the device to sucesfully register into AzureAD before continuing.
#
# Will only continue execution if device is connected to domain.
#
# Use IntuneWinAppUtil to wrap and deploy as a Windows app (Win32).
# See ReadMe.md for more information.
#
# Tip: Win32 apps only work as tracked apps in device ESP from 1903.
#
# Exits with return code 0 to indicate script completed.
#
# Using Check connectivity to DC from https://github.com/Azure-Samples/DSRegTool/blob/main/DSRegTool.ps1
#

# Create a tag file just so Intune knows this was installed
If (-Not (Test-Path "$($env:ProgramData)\DeviceRegistration\WaitForUserDeviceRegistration"))
{
    Mkdir "$($env:ProgramData)\DeviceRegistration\WaitForUserDeviceRegistration"
}
Set-Content -Path "$($env:ProgramData)\DeviceRegistration\WaitForUserDeviceRegistration\WaitForUserDeviceRegistration.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\DeviceRegistration\WaitForUserDeviceRegistration\WaitForUserDeviceRegistration.log"

# Check connectivity to DC
$now = (Get-Date).ToString()
Write-Host "$now - Testing Domain Controller connectivity..." -ForegroundColor Yellow
$DCName=""
$DCTest=nltest /dsgetdc:
$DCName = $DCTest | Select-String DC | Select-Object -first 1
$DCName =($DCName.tostring() -split "DC: \\")[1].trim()
If (($DCName.length) -eq 0){
    $now = (Get-Date).ToString()
    Write-Host "$now - Test failed: connection to Domain Controller failed. Exit." -ForegroundColor Red
    Stop-Transcript
    Exit 0
} Else {
    $now = (Get-Date).ToString()
    Write-Host "$now - Test passed: connection to Domain Controller succeeded. Continue script execution." -ForegroundColor Green
}

# Start Automatic-Device-Join
$now = (Get-Date).ToString()
Write-Host "$now - Start Automatic-Device-Join..." -ForegroundColor Yellow
Start-ScheduledTask "\Microsoft\Windows\Workplace Join\Automatic-Device-Join"
$now = (Get-Date).ToString()
Write-Host "$now - Sleeping for 10s..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$filter304 = @{
  LogName = 'Microsoft-Windows-User Device Registration/Admin'
  Id = '304' # Automatic registration failed at join phase
}

$filter306 = @{
  LogName = 'Microsoft-Windows-User Device Registration/Admin'
  Id = '306' # Automatic registration Succeeded
}

$filter334 = @{
  LogName = 'Microsoft-Windows-User Device Registration/Admin'
  Id = '334' # Automatic device join pre-check tasks completed. The device can NOT be joined because a domain controller could not be located.
}

$filter335 = @{
  LogName = 'Microsoft-Windows-User Device Registration/Admin'
  Id = '335' # Automatic device join pre-check tasks completed. The device is already joined.
}

$filter20225 = @{
  LogName = 'Application'
  Id = '20225' # A dialled connection to RRAS has sucesfully connected.
}

# Wait for up to 60 minutes, re-checking once a minute...
While (($counter++ -lt 60) -and (!$exitWhile)) {
    # Let's get some events...
    $events304   = Get-WinEvent -FilterHashtable $filter304   -MaxEvents 1 -EA SilentlyContinue
    $events306   = Get-WinEvent -FilterHashtable $filter306   -MaxEvents 1 -EA SilentlyContinue
    $events334   = Get-WinEvent -FilterHashtable $filter334   -MaxEvents 1 -EA SilentlyContinue
    $events335   = Get-WinEvent -FilterHashtable $filter335   -MaxEvents 1 -EA SilentlyContinue
    $events20225 = Get-WinEvent -FilterHashtable $filter20225 -MaxEvents 1 -EA SilentlyContinue

    $now = (Get-Date).ToString()
    
    If ($events335) { $exitWhile = "True" }

    ElseIf ($events306) { $exitWhile = "True" }

    ElseIf ($events20225 -And $events334 -And !$events304) {
        Write-Host "$now - RRAS dialled sucesfully. Trying Automatic-Device-Join task to create userCertificate attribute on computer object..." -ForegroundColor Yellow
        Start-ScheduledTask "\Microsoft\Windows\Workplace Join\Automatic-Device-Join"
        Write-Host "$now - Sleeping for 60s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
    }

    Else {
        Write-Host "$now - No events indicating successful device registration with Azure AD." -ForegroundColor Yellow
        Write-Host "$now - Sleeping for 60s..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
        If ($events304) {
            $now = (Get-Date).ToString()
            Write-Host "$now - Trying Automatic-Device-Join task again..." -ForegroundColor Yellow
            Start-ScheduledTask "\Microsoft\Windows\Workplace Join\Automatic-Device-Join"
            $now = (Get-Date).ToString()
            Write-Host "$now - Sleeping for 5s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }
}

If ($events306) { 
    Write-Host $events306.Message
    $now = (Get-Date).ToString()
    Write-Host "$now - Exiting with return code 0 to indicate that the script completed." -ForegroundColor Green
    Stop-Transcript
    Exit 0
}

If ($events335) { Write-Host $events335.Message }

$now = (Get-Date).ToString()
Write-Host "$now - Script complete, exiting." -ForegroundColor Green

Stop-Transcript
