<#
.SYNOPSIS
    This script sets up the WSL Docker environment by downloading and extracting the necessary files from a GitHub repository and running the setup script with specified parameters.

.DESCRIPTION
    The script performs the following steps:
    1. Sets the necessary variables.
    2. Removes existing elements if they exist.
    3. Downloads the zip file from the GitHub repository.
    4. Extracts the archive.
    5. Navigates to the extracted directory.
    6. Runs setup.ps1 with the declared parameters.
    7. Supports all available parameters for setup.ps1.
    8. Uses $env:TEMP as the default path.
    9. Adds verbose flag and verbose logs.

.PARAMETER DescriptionPattern
    The description pattern to be used in the setup script.

.PARAMETER DockerCredentialWincredPath
    The path to the Docker credential wincred executable.

.PARAMETER SkipInitTest
    A switch to skip the initial test in the setup script.

.PARAMETER Verbose
    A switch to enable verbose logging.

.EXAMPLE
    .\start.ps1 -DescriptionPattern 'Example Cert Pattern' -DockerCredentialWincredPath 'C:\path\to\docker-credential-wincred.exe' -SkipInitTest -Verbose

    This command runs the script with the specified description pattern, Docker credential wincred path, skips the initial test, and enables verbose logging.
#>

param (
    [string]$DescriptionPattern,
    [string]$DockerCredentialWincredPath,
    [switch]$SkipInitTest,
    [switch]$Verbose
)

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

# Set variables
$downloadDir = (Join-Path -Path $env:TEMP -ChildPath "wsl-docker-setup")
$downloadPath = (Join-Path -Path $downloadDir -ChildPath "wsl-docker-setup.zip")
$wslDockerSetupDir = (Join-Path -Path $downloadDir -ChildPath "wsl-docker-setup-main")

# Create download directory if it doesn't exist
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Verbose:$Verbose
}

# Remove the existing zip file and extracted directory if they exist
if (Test-Path $downloadPath) {
    Remove-Item -Recurse -Force $downloadPath -Verbose:$Verbose
}
if (Test-Path $wslDockerSetupDir) {
    Remove-Item -Recurse -Force $wslDockerSetupDir -Verbose:$Verbose
}

# Download the zip file from GitHub
Write-Verbose "Downloading zip file from GitHub..."
Invoke-WebRequest -Uri "https://github.com/emilwojcik93/wsl-docker-setup/archive/refs/heads/main.zip" -OutFile $downloadPath -Verbose:$Verbose

# Extract the zip file
Write-Verbose "Extracting zip file..."
Expand-Archive -Path $downloadPath -DestinationPath $downloadDir -Verbose:$Verbose

# Navigate to the extracted directory
Set-Location -Path $wslDockerSetupDir -Verbose:$Verbose

# Build the command to run setup.ps1 with the provided parameters
$setupCommand = ".\setup.ps1"
if ($DescriptionPattern) {
    $setupCommand += " -DescriptionPattern `"$DescriptionPattern`""
}
if ($DockerCredentialWincredPath) {
    $setupCommand += " -DockerCredentialWincredPath `"$DockerCredentialWincredPath`""
}
if ($SkipInitTest) {
    $setupCommand += " -SkipInitTest"
}
if ($Verbose) {
    $setupCommand += " -Verbose"
}

# Run setup.ps1 with the declared parameters
Write-Verbose "Running setup.ps1 with the following command: $setupCommand"
powershell.exe -NoExit -Command $setupCommand -Verbose:$Verbose