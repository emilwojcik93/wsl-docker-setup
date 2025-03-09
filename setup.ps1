param (
    [string]$DescriptionPattern,
    [string]$DockerCredentialWincredPath,
    [switch]$SkipInitTest,
    [switch]$Verbose
)

if ($Verbose) {
    $VerbosePreference = "Continue"
}

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "Script needs to be run as Administrator. Attempting to relaunch."
    $argList = @()

    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        $argList += if ($_.Value -is [switch] -and $_.Value) {
            "-$($_.Key)"
        } elseif ($_.Value -is [array]) {
            "-$($_.Key) $($_.Value -join ',')"
        } elseif ($_.Value) {
            "-$($_.Key) '$($_.Value)'"
        }
    }

    $script = if ($PSCommandPath) {
        "& { & `'$($PSCommandPath)`' $($argList -join ' ') }"
    } else {
        "&([ScriptBlock]::Create((irm https://github.com/emilwojcik93/wsl-docker-setup/releases/latest/download/start.ps1))) $($argList -join ' ')"
    }

    $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { "$powershellCmd" }

    if ($processCmd -eq "wt.exe") {
        Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    } else {
        Start-Process $processCmd -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
    }

    break
} else {
    # Check and set execution policy for CurrentUser, Process, and LocalMachine
    $executionPolicies = Get-ExecutionPolicy -List

    $currentUserPolicy = $executionPolicies | Where-Object { $_.Scope -eq 'CurrentUser' }
    $processPolicy = $executionPolicies | Where-Object { $_.Scope -eq 'Process' }
    $localMachinePolicy = $executionPolicies | Where-Object { $_.Scope -eq 'LocalMachine' }

    if ($currentUserPolicy.ExecutionPolicy -ne 'Bypass') {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    }
    if ($processPolicy.ExecutionPolicy -ne 'Bypass') {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    }
    if ($localMachinePolicy.ExecutionPolicy -ne 'Bypass') {
        Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force
    }
    # Continue with the rest of your script
    Write-Output "Execution policy checked and set to Bypass where necessary."
    # Add any additional script logic here
}

# Define paths to the scripts
#POWERSHELL
$testWindows = Join-Path -Path $PSScriptRoot -ChildPath ".\pwsh\Test-Windows.ps1"
$installCertificatesInWSL = Join-Path -Path $PSScriptRoot -ChildPath ".\pwsh\Install-CertificatesInWSL.ps1"
$installDockerInWSL = Join-Path -Path $PSScriptRoot -ChildPath ".\pwsh\Install-DockerInWSL.ps1"
$installGithubPAT = Join-Path -Path $PSScriptRoot -ChildPath ".\pwsh\Install-GithubPAT.ps1"

#BASH
$initializeUbuntuScript = "./bash/Initialize-Ubuntu.sh"
$installGCM = "./bash/Install-GCM.sh"

# Function to validate Windows
function Test-Windows {
    param (
        [string]$DockerCredentialWincredPath,
        [switch]$SkipInitTest
    )
    Write-Output "Running Test-Windows.ps1..."
    Write-Verbose "DockerCredentialWincredPath: $DockerCredentialWincredPath"
    $params = @{}
    if ($PSBoundParameters.ContainsKey('DockerCredentialWincredPath')) {
        $params['DockerCredentialWincredPath'] = $DockerCredentialWincredPath
    }
    & $testWindows @params
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: Test-Windows.ps1 failed."
        throw "Test-Windows.ps1 failed."
    }
    Write-Verbose "Test-Windows.ps1 completed successfully."
}

# Function to automatic install of certificates
function Install-CertificatesInWSL {
    param (
        [string]$DescriptionPattern,
        [switch]$SkipInitTest
    )

    Write-Output "Running Install-CertificatesInWSL.ps1..."
    Write-Verbose "DescriptionPattern: $DescriptionPattern"
    Write-Verbose "SkipInitTest: $SkipInitTest"

    $params = @{}
    if ($PSBoundParameters.ContainsKey('DescriptionPattern')) {
        $params['DescriptionPattern'] = $DescriptionPattern
    }
    if ($PSBoundParameters.ContainsKey('SkipInitTest') -and $SkipInitTest) {
        $params['SkipInitTest'] = $true
    }
    & $installCertificatesInWSL @params
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: Install-CertificatesInWSL.ps1 failed."
        throw "Install-CertificatesInWSL.ps1 failed."
    }
    Write-Verbose "Install-CertificatesInWSL.ps1 completed successfully."
}

# Function to set up Ubuntu in WSL
function Initialize-Ubuntu {
    Write-Output "Running Initialize-Ubuntu.sh in WSL..."
    wsl --cd "$PSScriptRoot" -d Ubuntu -u root -e bash -c "$initializeUbuntuScript"
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: Initialize-Ubuntu.sh failed."
        throw "Initialize-Ubuntu.sh failed."
    }
    Write-Verbose "Initialize-Ubuntu.sh completed successfully."
}

# Function to setup Docker in WSL
function Install-DockerInWSL {
    Write-Output "Running Install-DockerInWSL.ps1..."
    & $installDockerInWSL -SkipValidation
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: Install-DockerInWSL.ps1 failed."
        throw "Install-DockerInWSL.ps1 failed."
    }
    Write-Verbose "Install-DockerInWSL.ps1 completed successfully."
}

# Function to setup GitHub PAT
function Install-GithubPAT {
    Write-Output "Running Install-GithubPAT.ps1..."
    & $installGithubPAT -SkipValidation
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: Install-GithubPAT.ps1 failed."
        throw "Install-GithubPAT.ps1 failed."
    }
    Write-Verbose "Install-GithubPAT.ps1 completed successfully."
}

# Function to set up Git Credential Manager
function Install-GCM {
    Write-Output "Running Install-GCM.sh..."
    wsl --cd "$PSScriptRoot" -d Ubuntu  -e bash -c "$installGCM"
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Error: Install-GCM.sh failed."
        throw "Install-GCM.sh failed."
    }
    Write-Verbose "Install-GCM.sh completed successfully."
}

function Main {
    param (
        [string]$DescriptionPattern,
        [switch]$SkipInitTest,
        [switch]$Verbose
    )

    Write-Verbose "Starting the main function..."
    Write-Verbose "DescriptionPattern: $DescriptionPattern"
    Write-Verbose "DockerCredentialWincredPath: $DockerCredentialWincredPath"
    Write-Verbose "SkipInitTest: $SkipInitTest"
    Write-Verbose "Verbose: $Verbose"

    try {
        Test-Windows -DockerCredentialWincredPath $DockerCredentialWincredPath
        Install-CertificatesInWSL -DescriptionPattern $DescriptionPattern -SkipInitTest:$SkipInitTest
        Initialize-Ubuntu
        Install-DockerInWSL
        Install-GithubPAT
        Install-GCM
        Write-Output "All tasks completed successfully."
        Read-Host "Press Enter to exit"
    } catch {
        Write-Error "An error occurred: $_"
        Write-Output "Detailed logs can be found at the following location: $transcriptPath"
        $userInput = Read-Host "An error occurred. Type 'restart' to retry or press Enter to exit"
        if ($userInput -eq 'restart') {
            Write-Output "Restarting the script..."
            Main @args
        } else {
            Stop-Transcript
            return
        }
    }
}


# Start transcript
$transcriptPath = Join-Path -Path $env:TEMP -ChildPath "setup_transcript_$((Get-Date).ToString('yyyyMMdd')).txt"
Start-Transcript -Path $transcriptPath

Write-Output "In the event of any issues, detailed logs can be found at the following location: $transcriptPath"
Start-Sleep -Seconds 0

# Collect parameters into a hashtable
$args = @{}

if ($PSBoundParameters.ContainsKey('DescriptionPattern')) {
    $args['DescriptionPattern'] = $DescriptionPattern
}
if ($PSBoundParameters.ContainsKey('DockerCredentialWincredPath')) {
    $args['DockerCredentialWincredPath'] = $DockerCredentialWincredPath
}
if ($PSBoundParameters.ContainsKey('SkipInitTest')) {
    $args['SkipInitTest'] = $SkipInitTest
}
if ($PSBoundParameters.ContainsKey('Verbose')) {
    $args['Verbose'] = $Verbose
}

# Call the main function
Main @args

# Stop transcript
Stop-Transcript
