#!/bin/bash

# -----------------------------------------------------------------------------
# SYNOPSIS
# This script configures Git to use the Git Credential Manager (GCM) for Windows
# as the default credential helper in a WSL distribution.
#
# USAGE
# ./Install-GCM.sh
#
# DESCRIPTION
# The script determines the installed Git version and configures the appropriate
# Git Credential Manager path based on the version. If the Git version does not
# match the expected pattern, it attempts to determine the path to the Git
# Credential Manager using the provided Git path.
#
# LINKS
# https://gist.github.com/RichardBronosky/9ab50abb8698e02341629db21e5fa6bf#file-configure-git-credential-hellper-sh
# https://stackoverflow.com/questions/5343068/is-there-a-way-to-cache-https-credentials-for-pushing-commits
# https://github.com/Microsoft/Git-Credential-Manager-for-Windows
# -----------------------------------------------------------------------------

# Function to escape spaces in paths and remove Windows Unicode characters
escape_spaces() {
    sed -e 's?\r??g' -e 's? ?\\ ?g' <<<"$1"
}

# Function to find the path of git-credential-manager.exe using find
find_gcm() {
    local search_paths=(
        "$(wslpath "$(wslvar ProgramFiles)")"
        "$(wslpath "$(wslvar LOCALAPPDATA)")"
    )

    for path in "${search_paths[@]}"; do
        gcm_path=$(find "$path" -type f -name "git-credential-manager.exe" 2>/dev/null | head -n 1)
        if [[ -n "$gcm_path" ]]; then
            echo "$gcm_path"
            return 0
        fi
    done

    return 1
}

# Function to print information messages
info() {
    echo "$@" >/dev/stderr
}

# Main script execution
main() {
    echo "Running Install-GCM.sh..."
    path="$(find_gcm)"
    if [[ $? -ne 0 ]]; then
        echo "Failed to get Git Credential Manager path."
        return 1
    fi

    if ! [[ -x "$path" ]]; then
        echo "Did not find executable at '$path'"
        echo "Aborting"
        return 1
    fi

    info "Found Credential Manager at '$path'"
    info "Configuring git"
    git config --global credential.helper "$(escape_spaces "$path")"
}

# Run the main function
main
if [[ $? -ne 0 ]]; then
    echo "An error occurred during the execution of Install-GCM.sh."
else
    echo "Install-GCM.sh completed successfully."
fi