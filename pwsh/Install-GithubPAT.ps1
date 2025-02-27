# Variables and Arrays
$packages = @(
    "Microsoft.AppInstaller",
    "GitHub.cli",
    "Git.Git"
)

# Function to find the path of gh.exe using find
function Find-GhExecutable {
    $searchPaths = @(
        "$env:ProgramFiles\GitHub CLI",
        "$env:ProgramFiles (x86)\GitHub CLI",
        "$env:LOCALAPPDATA\GitHub CLI"
    )

    foreach ($path in $searchPaths) {
        $ghPath = Get-ChildItem -Path $path -Recurse -Filter "gh.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($ghPath) {
            return $ghPath
        }
    }

    throw "gh.exe not found in common locations. Please ensure GitHub CLI is installed."
}

# Find the gh executable path
$ghPath = Find-GhExecutable


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

# Function to format a hyperlink for display in the terminal
# This function takes a URI and an optional label, and formats it as a clickable hyperlink
# if the terminal supports it. For Windows users not inside Windows Terminal, it falls back
# to displaying the URI with the label in parentheses.
function Format-Hyperlink {
    param(
      [Parameter(ValueFromPipeline = $true, Position = 0)]
      [ValidateNotNullOrEmpty()]
      [Uri]$Uri,

      [Parameter(Mandatory=$false, Position = 1)]
      [string]$Label
    )

    if (($PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows) -and -not $Env:WT_SESSION) {
      # Fallback for Windows users not inside Windows Terminal
      if ($Label) {
        return "$Label ($Uri)"
      }
      return "$Uri"
    }

    if ($Label) {
      return "`e]8;;$Uri`e\$Label`e]8;;`e\"
    }

    return "$Uri"
}

function Get-GitHubPAT {
    $azureDevOpsLink = Format-Hyperlink -Uri "https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate" -Label "Use personal access tokens - Azure DevOps | Microsoft Learn"
    $githubDocsLink = Format-Hyperlink -Uri "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens" -Label "Managing your personal access tokens - GitHub Docs"

    Write-Host "If you have not generated a Personal Access Token (PAT) yet, please refer to the following resources:"
    Write-Host "  - $azureDevOpsLink"
    Write-Host "  - $githubDocsLink"
    Write-Host ""
    Write-Host "Please generate a classic PAT with the following token scopes/roles:"
    Write-Host "'admin:enterprise', 'admin:org', 'delete:packages', 'delete_repo', 'gist', 'notifications', 'project', 'repo', 'user', 'workflow', 'write:discussion', 'write:packages'"
    Write-Host ""

    $githubPAT = Read-Host -AsSecureString "Please provide your GitHub Personal Access Token (PAT)"
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($githubPAT))
}

function Login-GitHub {
    param (
        [string]$githubPAT
    )

    while ($true) {
        $githubPAT | & $ghPath auth login --with-token

        if ($LASTEXITCODE -eq 0) {
            Write-Output "GitHub login successful."
            return $true
        } else {
            Write-Output "Error: GitHub login failed. Please try again or press CTRL+C to exit."
            $githubPAT = Get-GitHubPAT
        }
    }
}

function Setup-GitHubPAT {
    param (
        [switch]$SkipValidation
    )

    try {
        if (-not $SkipValidation) {
            # Check package availability
            Check-Package-Availability -packages $packages
        }

        Write-Output "Checking GitHub login status..."
        # Check if user is logged in to GitHub
        $isLoggedIn = Check-GitHubLogin
        if (-not $isLoggedIn) {
            Write-Output "User is not logged in to GitHub. Starting GitHub PAT setup process..."
            $githubPAT = Get-GitHubPAT
            Login-GitHub -githubPAT $githubPAT
        } else {
            Write-Output "User is already logged in to GitHub."
        }

        Write-Output "GitHub PAT setup process completed successfully."
    } catch {
        Write-Error "An error occurred: $_"
    }
}

# Run the main function
Setup-GitHubPAT @args