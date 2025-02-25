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

# Function to get the manager path from the Git path
manager_path_from_git() {
    sed -e 's?/cmd/git.exe?/mingw64/bin/git-credential-manager.exe?' <<<"$1"
}

# Function to escape spaces in paths and remove Windows Unicode characters
escape_spaces() {
    sed -e 's?\r??g' -e 's? ?\\ ?g' <<<"$1"
}

# Function to find the path of an executable using where.exe
find_where() {
    out="$(wslpath "$(where.exe "$1" 2>/dev/null)")"
    status=$?
    if ! $(exit $status); then
        return $status
    fi
    sed -e 's/[[:space:]]*$//' <<<"$out"
}

# Function to print information messages
info() {
    echo "$@" >/dev/stderr
}

# Function to get the Git Credential Manager path based on the Git version
get_manager_path() {
    git_path="$(find_where git.exe)"
    if [[ -z "$git_path" ]]; then
        echo "Error: Git is not installed or not found in the PATH."
        return 1
    fi

    git_version=$("$git_path" --version | awk '{print $3}')
    if [[ -z "$git_version" ]]; then
        echo "Error: Unable to determine Git version."
        return 1
    fi

    # Extract the raw version number (e.g., 2.47.1 from 2.47.1.windows.1)
    raw_version="$(echo "$git_version" | grep -oP '^\d+\.\d+\.\d+')"
    manager_path="$(manager_path_from_git "$git_path")"

    echo "$manager_path"
}

# Main script execution
main() {
    echo "Running install-gcm.sh..."
    path="$(get_manager_path)"
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
    echo "An error occurred during the execution of install-gcm.sh."
else
    echo "install-gcm.sh completed successfully."
fi