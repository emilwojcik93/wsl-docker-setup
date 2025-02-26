<#
.SYNOPSIS
    Compares the currently installed KB ID with remote KB IDs and checks if the local system is up to date.

.DESCRIPTION
    This script retrieves the latest installed KB ID along with the installation date and OS build version, fetches the remote KB IDs (excluding preview updates), and compares them. It checks if the currently installed KB/OS Build is updated or counts how many updates it is behind.

.PARAMETER Verbose
    Optional parameter to write all details about retrieved data.

.EXAMPLE
    .\Compare-KBUpdates.ps1

    Compares the currently installed KB ID with remote KB IDs and checks if the local system is up to date.

.EXAMPLE
    .\Compare-KBUpdates.ps1 -Verbose

    Compares the currently installed KB ID with remote KB IDs and checks if the local system is up to date, with detailed output.
#>

param (
    [switch]$Verbose
)

Function Get-LatestKBUpdate {
    # Define the regex pattern to match the KB ID
    $regex = "(KB[0-9]*)"

    # Create an update session and searcher
    $Session = New-Object -ComObject "Microsoft.Update.Session"
    $Searcher = $Session.CreateUpdateSearcher()

    # Get the total number of updates in the history
    $historyCount = $Searcher.GetTotalHistoryCount()

    # Query the update history, filter updates with KB IDs, sort by date, and select the latest one
    $latestUpdate = $Searcher.QueryHistory(0, $historyCount) |
        Where-Object { $_.Title -match $regex } |
        Sort-Object Date -Descending |
        Select-Object -First 1

    # Extract the KB ID from the title
    $kb = ($latestUpdate.Title | Select-String -Pattern $regex).Matches.Groups[1].Value

    # Format the date
    $date = $latestUpdate.Date.ToString("MMMM dd, yyyy")

    # Get the OS build version
    $osBuild = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild + "." +
               (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR

    # Format the output
    $output = "$date - $kb (OS Builds $osBuild)"
    return [PSCustomObject]@{
        Output = $output
        KB = $kb
        OSBuild = $osBuild
        Date = $latestUpdate.Date
    }
}

Function Get-RemoteKBUpdates {
    # Fetch the content from the Windows Update History URL
    $uri = "https://aka.ms/WindowsUpdateHistory"
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop

    # Extract the links from the response
    $links = $response.Links

    # Filter the links to include only those that match "supLeftNavLink" and contain "KB", and exclude those that contain "Preview"
    $filteredLinks = $links | Where-Object { $_.outerHTML -match "supLeftNavLink" -and $_.outerHTML -match "KB" -and $_.outerHTML -notmatch "Preview" }

    # Extract KB IDs and raw details
    $kbList = $filteredLinks | ForEach-Object {
        if ($_.outerHTML -match "OS Builds") {
            [PSCustomObject]@{
                RawDetails = $_.outerHTML
            }
        }
    }

    # Return the raw KB list
    return $kbList
}

Function Parse-KBDetails {
    param (
        [string]$rawDetails
    )

    $kb = $null
    $osBuilds = $null
    $date = $null

    # Extract KB ID
    if ($rawDetails -match "KB[0-9]+") {
        $kb = $matches[0]
    }

    # Extract OS Builds
    if ($rawDetails -match "OS Builds ([^<]+)") {
        $osBuilds = $matches[1] -split " and "
    }

    # Extract Date
    if ($rawDetails -match ">([^<]+)&#x2014;") {
        $dateString = $matches[1].Trim()
        $parsedDate = $null
        $dateFormats = @("MMMM d, yyyy", "MMMM dd, yyyy", "MMMM d, yyyy h:mm tt", "MMMM dd, yyyy h:mm tt", "MMMM d", "MMMM dd", "MMMM", "MMMM yyyy")
        foreach ($format in $dateFormats) {
            try {
                $parsedDate = [datetime]::ParseExact($dateString, $format, $null)
                break
            } catch {
                continue
            }
        }
        $date = $parsedDate
    }

    return [PSCustomObject]@{
        KB = $kb
        OSBuilds = $osBuilds
        Date = $date
    }
}

Function Compare-KBUpdates {
    param (
        [switch]$Verbose
    )

    # Get local installed KB ID and OS Build
    $localKBUpdate = Get-LatestKBUpdate
    $localKB = $localKBUpdate.KB
    $localOSBuild = $localKBUpdate.OSBuild
    $localDate = $localKBUpdate.Date

    # Get remote KB IDs and OS Builds
    $remoteKBList = Get-RemoteKBUpdates
    $parsedKBList = $remoteKBList | ForEach-Object { Parse-KBDetails -rawDetails $_.RawDetails }

    if ($Verbose) {
        Write-Output "Local KB Update: $($localKBUpdate.Output)"
        Write-Output "Local KB ID: $localKB"
        Write-Output "Local OS Build: $localOSBuild"
        Write-Output "Local KB Date: $($localKBUpdate.Date.ToString('MM/dd/yyyy'))"
        Write-Output "----------------------"
        Write-Output "Remote KB List:"
        $parsedKBList | ForEach-Object { Write-Output $_ }
        Write-Output "----------------------"
    }

    # Find the index of the local KB in the remote KB list
    $localKBIndex = $parsedKBList.KB.IndexOf($localKB)
    if ($localKBIndex -ge 0) {
        $updatesBehind = $localKBIndex
        if ($Verbose) {
            Write-Output "Local KB is up to date with the latest remote KB."
            Write-Output "Days behind: 0"
            Write-Output "Latest remote KB Update: $($parsedKBList[0].KB) (OS Builds $($parsedKBList[0].OSBuilds -join ', '))"
            Write-Output "Latest remote KB ID: $($parsedKBList[0].KB)"
            Write-Output "Latest remote OS Build: $($parsedKBList[0].OSBuilds -join ', ')"
            Write-Output "Latest remote KB Date: $($parsedKBList[0].Date.ToString('MM/dd/yyyy'))"
        }
        return $updatesBehind
    }

    # If local KB is not found, calculate how many updates it is behind
    $updatesBehind = ($parsedKBList | Where-Object { $_.Date -gt $localDate }).Count
    if ($Verbose) {
        Write-Output "Local KB is behind the latest remote KB by $updatesBehind updates."
        Write-Output "Days behind: $($updatesBehind)"
        Write-Output "Latest remote KB Update: $($parsedKBList[0].KB) (OS Builds $($parsedKBList[0].OSBuilds -join ', '))"
        Write-Output "Latest remote KB ID: $($parsedKBList[0].KB)"
        Write-Output "Latest remote OS Build: $($parsedKBList[0].OSBuilds -join ', ')"
        Write-Output "Latest remote KB Date: $($parsedKBList[0].Date.ToString('MM/dd/yyyy'))"
    }
    return $updatesBehind
}

# Main section to call the function
Function Main {
    param (
        [switch]$Verbose
    )

    try {
        $result = Compare-KBUpdates -Verbose:$Verbose
        Write-Output $result
    } catch {
        Write-Error $_.Exception.Message
    }
}

# Call the main function
Main -Verbose:$Verbose