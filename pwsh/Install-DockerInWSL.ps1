# Variables and Arrays
$packages = @(
    "Microsoft.AppInstaller",
    "Docker.DockerCompose",
    "Docker.DockerCLI"
)

# Function to check winget packages
function Check-Package-Availability {
    param (
        [string[]]$packages
    )

    foreach ($package in $packages) {
        $packageInfo = winget list --id $package

        if ($packageInfo -match "No installed package found matching input criteria.") {
            Write-Error "$package not found. Please install it manually."
            throw "$package not found. Please install it manually."
        } else {
            Write-Output "$package is available."
        }
    }
}

# Retrieve WSL network address from registry entry
function Get-WSLNetworkAddress {
    $wslIp = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss").NatIpAddress

    if ($wslIp -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
        return $wslIp
    } else {
        throw "The retrieved value is not a valid IP address: $wslIp"
    }
}

# Test connection to WSL Docker socket
function Test-WSLDockerSocket {
    param (
        [string]$wslIp
    )
    Write-Output "Testing connection to WSL Docker socket at ${wslIp}:2375..."
    $progressPreference = 'silentlyContinue'
    $testConnection = Test-NetConnection -InformationLevel Quiet -ComputerName ${wslIp} -Port 2375 -WarningAction SilentlyContinue | Out-Null
    $progressPreference = 'Continue'
    return $testConnection
}

# Setup Windows user environment for DOCKER_HOST
function Setup-DockerHostEnv {
    param (
        [string]$wslIp
    )
    Write-Output "Setting up Windows user environment for DOCKER_HOST..."
    [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', "tcp://${wslIp}:2375", [System.EnvironmentVariableTarget]::User)
    [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', "tcp://${wslIp}:2375", [System.EnvironmentVariableTarget]::Process)
}

# Reload user/system Windows environment variables
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

# Function to find the path of gh.exe using find
function Find-Executable {
    param (
        [string]$exeName
    )

    $searchPaths = @(
        (Join-Path -Path "${env:LocalAppData}" -ChildPath "Microsoft\WinGet\Packages"),
        "${env:ProgramW6432}",
        "${env:ProgramFiles(x86)}"
    )

    foreach ($path in $searchPaths) {
        $exePath = Get-ChildItem -Path $path -Recurse -Filter $exeName -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($exePath) {
            $exeDir = Split-Path -Parent $exePath
            $userPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
            if ($userPath -notlike "*$exeDir*") {
                [System.Environment]::SetEnvironmentVariable("Path", "$userPath`;$exeDir", [System.EnvironmentVariableTarget]::User)
            }
            return $exePath
        }
    }

    throw "$exeName not found in common locations. Please ensure it is installed."
}

Write-Output "Searching for docker-compose.exe in common locations..."
$dockerComposePath = Find-Executable -exeName "docker-compose.exe"
Write-Output "Found docker-compose.exe at: $dockerComposePath"

Write-Output "Searching for docker.exe in common locations..."
$dockerPath = Find-Executable -exeName "docker.exe"
Write-Output "Found docker.exe at: $dockerPath"

Write-Output "Searching for gh.exe in common locations..."
$ghPath = Find-Executable -exeName "gh.exe"
Write-Output "Found gh.exe at: $ghPath"

function Check-GitHubLogin {
    try {
        $authStatus = & $ghPath auth status 2>&1

        # Get the original output encoding
        $originalEncoding = [Console]::OutputEncoding
        # Set the output encoding to UTF-8
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

        # Parse the output to check the login status
        $isLoggedIn = $false
        $authStatus -split "`n" | ForEach-Object {
            if ($_ -match "Logged in to github.com account" -or $_ -match "Active account: true") {
                $isLoggedIn = $true
            }
        }

        # Reset the output encoding to the original value
        [Console]::OutputEncoding = $originalEncoding

        return $isLoggedIn
    } catch {
        return $false
    }
}

function Get-GitHubUsername {
    $authStatus = & $ghPath auth status 2>&1

    # Get the original output encoding
    $originalEncoding = [Console]::OutputEncoding
    # Set the output encoding to UTF-8
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

    # Parse the output to find the username
    $username = $authStatus | ForEach-Object {
        if ($_ -match "Logged in to github.com account (\S+)") {
            return $matches[1]
        }
    }

    # Reset the output encoding to the original value
    [Console]::OutputEncoding = $originalEncoding

    if ($username) {
        return $username
    } else {
        Write-Output "Error: Failed to retrieve GitHub username."
        exit 1
    }
}

# Test if Docker CLI can access WSL Docker socket
function Test-DockerCLI {
    Write-Output "Testing if Docker CLI can access WSL Docker socket..."
    $dockerInfo = & $dockerPath info 2>&1 | Out-String
    $dockerInfo = $dockerInfo -replace "(?s)\[DEPRECATION NOTICE\].*?(?=\n\n|\z)", ""
    $dockerInfo = $dockerInfo -replace "(?s)WARNING:.*?(?=\n\n|\z)", ""

    if ($dockerInfo -match "Server:\s+Containers:") {
        Write-Output "Docker instance in WSL is accessible."
        return $true
    } else {
        Write-Output "Docker instance in WSL is not accessible."
        return $false
    }
}

# Function to restart Docker service and socket in WSL
function Restart-DockerServiceAndSocket {
    Write-Output "Restarting Docker service and socket in WSL..."
    wsl -d Ubuntu -u root -e bash -c "systemctl restart docker.service docker.socket"
    Start-Sleep -Seconds 5
    $dockerServiceStatus = wsl -d Ubuntu -u root -e bash -c "systemctl is-active docker.service"
    if ($dockerServiceStatus -ne "active") {
        Write-Output "Error: Failed to restart Docker service."
        throw "Failed to restart Docker service."
    }
    Write-Output "Docker service and socket restarted successfully."
}

function Login-Docker {
    param (
        [string]$username,
        [string]$githubPAT
    )

    Write-Output "Logging into Docker GitHub repo 'ghcr.io'..."
    $githubPAT | & $dockerPath login ghcr.io -u $username --password-stdin

    if ($LASTEXITCODE -eq 0) {
        Write-Output "Docker login successful."
    } else {
        Write-Output "Error: Docker login failed."
        return $false
    }

    return $true
}

# Main function to setup Docker in WSL
function Setup-DockerInWSL {
    param (
        [switch]$SkipValidation
    )
    try {
        if (-not $SkipValidation) {
            Write-Output "Checking and installing necessary packages..."
            Check-Package-Availability -packages $packages
            Reload-EnvVars
        }

        Restart-DockerServiceAndSocket

        $wslIp = Get-WSLNetworkAddress
        Setup-DockerHostEnv -wslIp $wslIp
        Reload-EnvVars

        
        if (Test-WSLDockerSocket -wslIp $wslIp) {
            if (Test-DockerCLI) {
                Write-Output "Docker CLI can access WSL Docker socket successfully."
                Write-Output "Checking GitHub login status..."
                # Check if user is logged in to GitHub
                $isLoggedIn = Check-GitHubLogin
                if (-not $isLoggedIn) {
                    Write-Output "User is not logged in to GitHub. Skipping login into Docker GitHub (ghcr.io) registry..."
                    return
                } else {
                    Write-Output "User is logged in to GitHub. Logging into Docker GitHub (ghcr.io) registry..."
                    $githubPAT = & $ghPath auth token
                    $username = Get-GitHubUsername
                    Login-Docker -username $username -githubPAT $githubPAT
                    return
                }
            } else {
                Write-Warning "Warning: Docker CLI cannot access WSL Docker socket but the socket is available, so it looks like you need to restart the PowerShell session to reload env vars."
                return
            }
        } else {
            Write-Error "Error: WSL Docker socket is not available."
            throw "WSL Docker socket is not available."
        }
    } catch {
        Write-Error "An error occurred: $_"
    }
}

# Run the main function
Setup-DockerInWSL @args