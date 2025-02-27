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

function Find-DockerExecutable {
    $searchPaths = @(
        (Join-Path -Path "${env:LocalAppData}" -ChildPath "Microsoft\WinGet\Packages"),
        (Join-Path -Path "${env:ProgramW6432}" -ChildPath "Docker"),
        (Join-Path -Path "${env:ProgramFiles(x86)}" -ChildPath "Docker")
    )

    foreach ($path in $searchPaths) {
        $dockerPath = Get-ChildItem -Path $path -Recurse -Filter "docker.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($dockerPath) {
            return $dockerPath
        }
    }

    throw "docker.exe not found in common locations. Please ensure Docker CLI is installed."
}

Write-Output "Searching for docker.exe in common locations..."
# Find the docker executable path
$dockerPath = Find-DockerExecutable

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
    wsl -u root -e bash -c "systemctl restart docker.service docker.socket"
    Start-Sleep -Seconds 5
    $dockerServiceStatus = wsl -u root -e bash -c "systemctl is-active docker.service"
    if ($dockerServiceStatus -ne "active") {
        Write-Output "Error: Failed to restart Docker service."
        throw "Failed to restart Docker service."
    }
    Write-Output "Docker service and socket restarted successfully."
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
                return
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