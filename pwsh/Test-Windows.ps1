param (
    [string]$DockerCredentialWincredPath = (Join-Path -Path $env:LocalAppData -ChildPath "Docker\docker-credential-wincred.exe")
)

$executables = @(
    "wsl.exe",
    "ubuntu.exe",
    "winget.exe",
    "git.exe",
    "gh.exe",
    "docker.exe",
    "docker-compose.exe",
    "code.cmd"
)

$wingetPackageIds = @{
    "winget.exe" = "Microsoft.AppInstaller"
    "git.exe" = "Git.Git"
    "gh.exe" = "GitHub.cli"
    "docker.exe" = "Docker.DockerCLI"
    "docker-compose.exe" = "Docker.DockerCompose"
    "code.cmd" = "Microsoft.VisualStudioCode"
}

# Functions
function Reload-EnvVars {
    Write-Output "Reloading system environment variables..."
    $systemEnvVars = [System.Environment]::GetEnvironmentVariables('Machine')
    foreach ($key in $systemEnvVars.Keys) {
        [System.Environment]::SetEnvironmentVariable($key, $systemEnvVars[$key], [System.EnvironmentVariableTarget]::Process)
    }

    Write-Output "Reloading user environment variables..."
    $userEnvVars = [System.Environment]::GetEnvironmentVariables('User')
    foreach ($key in $userEnvVars.Keys) {
        [System.Environment]::SetEnvironmentVariable($key, $userEnvVars[$key], [System.EnvironmentVariableTarget]::Process)
    }

    Write-Output "Reloading the PowerShell profile..."
    if (Test-Path $PROFILE) {
        . $PROFILE
    }
}

function CheckAndAddToPath {
    param (
        [string]$basePath = (Join-Path -Path $env:UserProfile -ChildPath "AppData\Local\Microsoft\WinGet\Packages"),
        [string]$exeName,
        [string]$pattern
    )

    # Find the directory containing the executable
    $exePath = Get-ChildItem -Path $basePath -Recurse -Filter $exeName | Select-Object -First 1 -ExpandProperty DirectoryName

    if ($exePath) {
        # Check if the pattern is already in the user PATH
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
        if ($userPath -notmatch $pattern) {
            # Add the whole value of $exePath to the user PATH
            [System.Environment]::SetEnvironmentVariable("Path", "$userPath`;$exePath", [System.EnvironmentVariableTarget]::User)
            Write-Output "Directory '$exePath' added to user PATH."
        } else {
            Write-Output "A directory containing '$pattern' is already in the user PATH."
        }
    } else {
        Write-Output "$exeName not found."
    }
}

function Test-WSL {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        return $false
    }
    if (-not (Get-Command ubuntu.exe -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $wslOutput = wsl -l -q | Where {$_.Replace("`0","") -match '^Ubuntu'}
        if ($wslOutput) {
            return $true
        }
    } catch {
        return $false
    }
}

function InstallOrUpdate-Winget {
    [CmdletBinding()]
    param (
        [switch]$Force
    )

    <#
    .SYNOPSIS
        Installs or updates WinGet to the latest version.
    .DESCRIPTION
        This function compares the local version of WinGet with the latest version available on GitHub.
        If the local version is lower or cannot be retrieved, it attempts to update WinGet using multiple methods.
    #>
    $ProgressPreference = "SilentlyContinue"
    $InformationPreference = 'Continue'

    # Function to get the local version of winget
    function Get-LocalWingetVersion {
        try {
            $localVersion = (winget --version).TrimStart('v')
            return $localVersion
        } catch {
            Write-Host "Failed to retrieve local WinGet version."
            return $null
        }
    }

    # Function to get the latest version of winget from GitHub
    function Get-LatestWingetVersion {
        try {
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $latestVersion = $latestRelease.tag_name.TrimStart('v')
            return $latestVersion
        } catch {
            Write-Host "Failed to retrieve latest WinGet version from GitHub."
            return $null
        }
    }

    # Function to update winget using the Asheroto method
    function Update-Winget-Asheroto-Method {
        try {
            Write-Host "Attempting to update WinGet using the Asheroto method..."
            $result = Start-Process -FilePath "powershell.exe" -ArgumentList "-Command &([ScriptBlock]::Create((irm https://github.com/asheroto/winget-install/releases/latest/download/winget-install.ps1))) -Force" -Wait -NoNewWindow -PassThru
            if ($result.ExitCode -ne 0) {
                throw "Asheroto method failed with exit code: $($result.ExitCode)"
            }
            return $true
        } catch {
            Write-Host "Asheroto method of updating WinGet failed."
            return $false
        }
    }

    # Function to update winget using the Microsoft Store
    function Update-Winget-MSStore-Method {
        try {
            Write-Host "Attempting to update WinGet using the Microsoft Store..."
            $result = Start-Process -FilePath "powershell.exe" -ArgumentList "-Command winget install --id Microsoft.AppInstaller -e --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow -PassThru
            if ($result.ExitCode -ne 0) {
                throw "Microsoft Store method failed with exit code: $($result.ExitCode)"
            }
            return $true
        } catch {
            Write-Host "Microsoft Store method of updating WinGet failed."
            return $false
        }
    }

    # Function to update winget using manual download
    function Update-Winget-Manual-Method {
        try {
            Write-Host "Attempting to update WinGet using manual download..."
            # Try to close any running WinGet processes
            Get-Process -Name "DesktopAppInstaller", "winget" -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host "Stopping running WinGet process..."
                $_.Kill()
                Start-Sleep -Seconds 2
            }

            # Fallback to direct download from GitHub
            $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl
            $msixBundleUrl = ($release.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url

            $tempFile = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
            Invoke-WebRequest -Uri $msixBundleUrl -OutFile $tempFile

            Add-AppxPackage -Path $tempFile -ErrorAction Stop
            Remove-Item $tempFile -Force

            Write-Host "Successfully installed WinGet from GitHub release"
            return $true
        } catch {
            Write-Error "Manual download method of updating WinGet failed: $_"
            return $false
        }
    }

    # Main function logic
    function Main {
        try {
            if ($Force) {
                Write-Host "Forcing update of WinGet..."
                $updated = Update-Winget-Manual-Method
                if (-not $updated) {
                    $updated = Update-Winget-MSStore-Method
                    if (-not $updated) {
                        Update-Winget-Asheroto-Method
                    }
                }
            } else {
                $localVersion = Get-LocalWingetVersion
                $latestVersion = Get-LatestWingetVersion

                if ($null -eq $localVersion -or $null -eq $latestVersion -or ([Version]$localVersion -lt [Version]$latestVersion)) {
                    Write-Host "Updating WinGet..."
                    $updated = Update-Winget-Manual-Method
                    if (-not $updated) {
                        $updated = Update-Winget-MSStore-Method
                        if (-not $updated) {
                            Update-Winget-Asheroto-Method
                        }
                    }
                } else {
                    Write-Host "WinGet is up to date (version $localVersion)."
                }
            }
        } catch {
            Write-Error "An error occurred during the update process: $_"
        }
    }

    # Call the main function
    Main
}

function Configure-DockerCredentialHelper {
    try {
        $configPath = "${env:USERPROFILE}\.docker\config.json"
        if (-Not (Test-Path -Path $configPath)) {
            New-Item -Path $configPath -ItemType File -Force | Out-Null
        }

        $configContent = Get-Content -Path $configPath -Raw
        if ($configContent -eq "") {
            $config = [PSCustomObject]@{}
        } else {
            $config = $configContent | ConvertFrom-Json
        }

        # Ensure $config is a [PSCustomObject] to allow property assignment
        if (-not ($config -is [PSCustomObject])) {
            $config = [PSCustomObject]$config
        }

        # Add or update the credsStore property if not already set to wincred
        if ($null -eq $config.credsStore -or $config.credsStore -ne "wincred") {
            $config | Add-Member -MemberType NoteProperty -Name "credsStore" -Value "wincred" -Force

            # Write the updated JSON back to the config.json file
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath

            Write-Output "Configured Docker to use wincred as the credential store."
        } else {
            Write-Output "Docker is already configured to use wincred as the credential store."
        }

        Write-Output "Content of Docker config file:"
        Get-Content -Path $configPath | Write-Output
    } catch {
        Write-Error "Failed to configure Docker credential helper: $_"
        throw "Failed to configure Docker credential helper."
    }
}

function Get-LocalVersion {
    param (
        [string]$executable
    )

    switch ($executable) {
        "git.exe" { return (git --version) -replace 'git version ', '' -replace '\.windows.*', '' }
        "gh.exe" { return (gh --version) -replace 'gh version ', '' -split ' ' | Select-Object -First 1 }
        "docker.exe" { return (docker --version) -replace 'Docker version ', '' -split ', ' | Select-Object -First 1 }
        "docker-compose.exe" { return (docker-compose --version) -replace 'Docker Compose version v', '' }
        "winget.exe" {
            $wingetInfo = winget --info
            $installedVersion = $wingetInfo | Select-String -Pattern 'Package: Microsoft.DesktopAppInstaller v' | ForEach-Object {
                $_ -replace 'Package: Microsoft.DesktopAppInstaller v', ''
            }
            return $installedVersion
        }
        default { return $null }
    }
}

function Get-LatestVersion {
    param (
        [string]$packageId
    )

    $versions = winget show $packageId --versions --accept-source-agreements | Select-String -Pattern '^\d' | ForEach-Object { $_.Line }
    return $versions[0]
}

function InstallOrUpdate {
    param (
        [string]$executable,
        [string]$latestVersion
    )

    switch ($executable) {
        "git.exe" {
            Write-Output "Updating Git to version $latestVersion..."
            winget install --force --id Git.Git -e --accept-source-agreements --accept-package-agreements
        }
        "gh.exe" {
            Write-Output "Updating GitHub CLI to version $latestVersion..."
            winget install --force --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
        }
        "docker.exe" {
            Write-Output "Updating Docker CLI to version $latestVersion..."
            winget install --force --id Docker.DockerCLI -e --accept-source-agreements --accept-package-agreements
        }
        "docker-compose.exe" {
            Write-Output "Updating Docker Compose to version $latestVersion..."
            winget install --force --id Docker.DockerCompose -e --accept-source-agreements --accept-package-agreements
        }
        "winget.exe" {
            Write-Output "Updating WinGet to version $latestVersion..."
            InstallOrUpdate-Winget
        }
        "code.cmd" {
            Write-Output "Updating Visual Studio Code to version $latestVersion..."
            $encodedCommand = 'IAB3AGkAbgBnAGUAdAAgAGkAbgBzAHQAYQBsAGwAIAAtAC0AZgBvAHIAYwBlACAATQBpAGMAcgBvAHMAbwBmAHQALgBWAGkAcwB1AGEAbABTAHQAdQBkAGkAbwBDAG8AZABlACAALQAtAHMAYwBvAHAAZQAgAE0AYQBjAGgAaQBuAGUAIAAtAC0AbwB2AGUAcgByAGkAZABlACAAJwAvAFYARQBSAFkAUwBJAEwARQBOAFQAIAAvAFMAUAAtACAALwBNAEUAUgBHAEUAVABBAFMASwBTAD0AIgAhAHIAdQBuAGMAbwBkAGUALAAhAGQAZQBzAGsAdABvAHAAaQBjAG8AbgAsAGEAZABkAGMAbwBuAHQAZQB4AHQAbQBlAG4AdQBmAGkAbABlAHMALABhAGQAZABjAG8AbgB0AGUAeAB0AG0AZQBuAHUAZgBvAGwAZABlAHIAcwAsAGEAcwBzAG8AYwBpAGEAdABlAHcAaQB0AGgAZgBpAGwAZQBzACwAYQBkAGQAdABvAHAAYQB0AGgAIgAnACAA'
            powershell -ExecutionPolicy Bypass -encodedCommand $encodedCommand
        }
    }
}

function Show-GreenCheckmark {
    Write-Host -ForegroundColor Green "OK"
}

function Show-RedCross {
    Write-Host -ForegroundColor Red "BAD"
}

function Show-Separator {
    Write-Host "----------------------------------------"
}

function Add-Path {
    param (
        [string]$path
    )

    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
    if ($currentPath -notlike "*$path*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$currentPath`;$path", [System.EnvironmentVariableTarget]::User)
    }
}


function InstallOrUpdate-DockerCredentialHelper {
    param (
        [string]$apiUrl = "https://api.github.com/repos/docker/docker-credential-helpers/releases/latest",
        [string]$DockerCredentialWincredPath
    )
    try {
        # Fetch the latest release information from GitHub API
        $latestRelease = Invoke-RestMethod -Uri $apiUrl

        # Find the asset URL for the Windows binary
        $assetUrl = $latestRelease.assets | Where-Object { $_.name -like "docker-credential-wincred-v*.windows-amd64.exe" } | Select-Object -ExpandProperty browser_download_url

        if (-not $assetUrl) {
            Write-Error "Error: Could not find the docker-credential-wincred asset in the latest release."
            throw "Could not find the docker-credential-wincred asset in the latest release."
        }

        # Get the latest version from the release tag
        $latestVersion = $latestRelease.tag_name -replace 'v', ''

        # Check if the directory for docker-credential-wincred.exe exists
        $DockerCredentialWincredDir = (Split-Path -Parent $DockerCredentialWincredPath)
        if (-not (Test-Path $DockerCredentialWincredDir)) {
            Write-Output "Directory '$DockerCredentialWincredDir' does not exist. Creating directory..."
            New-Item -Path $DockerCredentialWincredDir -ItemType Directory -Force | Out-Null
        }

        # Check if docker-credential-wincred.exe is installed
        if (Test-Path $DockerCredentialWincredPath) {
            # Get the current version
            $currentVersionOutput = & $DockerCredentialWincredPath version
            $currentVersion = $currentVersionOutput -replace 'docker-credential-wincred \(github.com/docker/docker-credential-helpers\) v', ''

            Write-Output "Current version of docker-credential-wincred: $currentVersion"
            Write-Output "Latest version of docker-credential-wincred: $latestVersion"

            # Compare versions and update if necessary
            if ([string]::IsNullOrEmpty($currentVersion) -or ([Version]$latestVersion -gt [Version]$currentVersion)) {
                Write-Output "Updating docker-credential-wincred to version $latestVersion..."
                Invoke-WebRequest -Uri $assetUrl -OutFile $DockerCredentialWincredPath
                Write-Output "Successfully updated docker-credential-wincred to version $latestVersion in path: `"$DockerCredentialWincredPath`"."
            } else {
                Write-Output "docker-credential-wincred version: $currentVersion is up to date in path: `"$DockerCredentialWincredPath`"."
            }
        } else {
            # Download the binary file
            Write-Output "Installing docker-credential-wincred version $latestVersion..."
            Invoke-WebRequest -Uri $assetUrl -OutFile $DockerCredentialWincredPath
            Write-Output "Successfully installed docker-credential-wincred version $latestVersion in path: `"$DockerCredentialWincredPath`"."
        }

        Add-Path -path (Split-Path -Parent $DockerCredentialWincredPath)

        # Configure Docker to use wincred.exe as the credential store
        Configure-DockerCredentialHelper
    } catch {`
        Write-Error "Failed to install or update docker-credential-wincred: $_"
        throw "Failed to install or update docker-credential-wincred."
    }
}

function Validate-Windows {
    param (
        [string]$DockerCredentialWincredPath
    )

    try {
        Show-Separator

        # Force run the Asheroto script to ensure winget is working properly
        Write-Output "Forcing update of WinGet using the Asheroto method..."
        InstallOrUpdate-Winget -Force
        Show-Separator

        # Check if WSL is available
        if (-not (Test-WSL)) {
            Show-RedCross
            Write-Output "Error: WSL is not available or no distributions are installed."
            Write-Output "Please run the following commands to install 'Ubuntu' and set up a UNIX user:"
            Write-Output "1. Install Ubuntu, best in PowerShell (Admin):"
            Write-Output "   wsl --install -d Ubuntu"
            Write-Output "  (it might require a restart)"
            Write-Output "2. Set up a UNIX user with init start wizard"
            Write-Output "3. After completing the above steps, please run this script again."
            throw "WSL is not available or no distributions are installed."
        } else {
            Show-GreenCheckmark
            Write-Output "WSL is available."
        }
        Show-Separator

        $compareKBUpdatesScript = Join-Path -Path $PSScriptRoot -ChildPath "Compare-KBUpdates.ps1"
        $updateStatus = & $compareKBUpdatesScript

        # Check the output of Compare-KBUpdates.ps1
        if ($updateStatus -eq 0) {
            Show-GreenCheckmark
            Write-Output "System is up to date."
        } else {
            Show-RedCross
            Write-Output "System is missing updates. Please update your system."
            
            $response = Read-Host "Would you like to continue anyway? (y/N)"
            if ($response -ne "y") {
                Write-Output "Exiting script as per user request."
                exit 1
            }
        }
        Show-Separator

        # Check if WinGet is available and install/update if necessary
        InstallOrUpdate-Winget
        Show-Separator

        # Check each executable
        foreach ($executable in $executables) {
            Write-Output "Checking $executable..."
            $command = Get-Command $executable -ErrorAction SilentlyContinue
            if ($command) {
                if ($executable -notin @("wsl.exe", "ubuntu.exe")) {
                    $localVersion = Get-LocalVersion -executable $executable
                    $latestVersion = Get-LatestVersion -packageId $wingetPackageIds[$executable]

                    Write-Output "$executable local version: $localVersion"
                    Write-Output "$executable latest version: $latestVersion"

                    if ([Version]$latestVersion -gt [Version]$localVersion) {
                        Show-RedCross
                        Write-Output "$executable is outdated. Updating..."
                        InstallOrUpdate -executable $executable -latestVersion $latestVersion
                    } else {
                        Show-GreenCheckmark
                        Write-Output "$executable is up to date."
                    }
                } else {
                    Show-GreenCheckmark
                    Write-Output "$executable is available."
                }
            } else {
                if ($executable -in @("wsl.exe", "ubuntu.exe")) {
                    Show-RedCross
                    Write-Output "Error: $executable is not available."
                    Write-Output "Please run the following commands to install 'Ubuntu' and set up a UNIX user:"
                    Write-Output "1. Install Ubuntu, best in PowerShell (Admin):"
                    Write-Output "   wsl --install -d Ubuntu"
                    Write-Output "  (it might require a restart)"
                    Write-Output "2. Set up a UNIX user with init start wizard"
                    Write-Output "3. After completing the above steps, please run this script again."
                    throw "$executable is not available."
                } else {
                    Show-RedCross
                    Write-Output "$executable is not installed. Installing..."
                    InstallOrUpdate -executable $executable -latestVersion (Get-LatestVersion -packageId $wingetPackageIds[$executable])
                }
            }

            Show-Separator
        }

        # Reload environment variables if any package was added or updated
        Reload-EnvVars

        # Check if docker.exe is available
        if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
            Write-Output "docker.exe is not available. Checking and updating PATH..."
            CheckAndAddToPath -basePath $basePath -exeName "docker.exe" -pattern "DockerCLI"
        }

        # Check if docker-compose.exe is available
        if (-not (Get-Command docker-compose.exe -ErrorAction SilentlyContinue)) {
            Write-Output "docker-compose.exe is not available. Checking and updating PATH..."
            CheckAndAddToPath -basePath $basePath -exeName "docker-compose.exe" -pattern "DockerCompose"
        }

        Show-Separator

        # Install or update docker-credential-wincred
        InstallOrUpdate-DockerCredentialHelper -DockerCredentialWincredPath $DockerCredentialWincredPath
    } catch {
        Write-Error "An error occurred: $_"
        throw "An error occurred during the validation process."
    }
}

# Run the main function
Validate-Windows -DockerCredentialWincredPath $DockerCredentialWincredPath
