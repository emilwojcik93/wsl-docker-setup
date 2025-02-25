# wsl-docker-setup

A PowerShell script for managing and automating various WSL components, including checking and setting execution policies, installing Windows features, and ensuring the script runs with administrative privileges.

## Table of Contents

- [wsl-docker-setup](#wsl-docker-setup)
  - [Table of Contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Scripts Overview](#scripts-overview)
    - [Test-Windows.ps1](#test-windowsps1)
    - [Install-CertificatesInWSL.ps1](#install-certificatesinwslps1)
    - [Install-DockerInWSL.ps1](#install-dockerinwslps1)
    - [Install-GithubPAT.ps1](#install-githubpatps1)
    - [Compare-KBUpdates.ps1](#compare-kbupdatesps1)
  - [Bash Scripts](#bash-scripts)
    - [Initialize-Ubuntu.sh](#initialize-ubuntush)
    - [Install-GCM.sh](#install-gcmsh)

## Introduction

This repository contains a set of PowerShell and Bash scripts designed to automate the setup and management of various components within Windows Subsystem for Linux (WSL). The scripts handle tasks such as installing Docker, configuring certificates, setting up GitHub PAT, and more.

## Prerequisites

- Windows 10 or later with WSL installed
- PowerShell 5.1 or later
- Administrator privileges
- clean installation of Ubuntu WSL

## Installation

1. Clone the repository:
    ```sh
    git clone https://github.com/emilwojcik93/wsl-docker-setup.git
    cd wsl-docker-setup
    ```

2. Ensure you have the necessary execution policies set:
    ```ps1
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    ```

## Usage

Default exectuion
```ps1
& ".\setup.ps1"
```

Run the main setup script with the required parameters:
```ps1
& ".\setup.ps1" -DescriptionPattern "CA" -DockerCredentialWincredPath "path\to\docker-credential-wincred.exe" -Verbose
```

## Scripts Overview

### Test-Windows.ps1

This script checks the availability and versions of various executables and installs or updates them if necessary. It also validates the Windows environment for WSL and Docker setup.

### Install-CertificatesInWSL.ps1

This script searches for certificates with a specific description pattern, exports them, installs them in WSL, and verifies the installation using curl.

### Install-DockerInWSL.ps1

This script sets up Docker within WSL, including checking and installing necessary packages, configuring the Docker service, and setting up the Docker host environment.

### Install-GithubPAT.ps1

This script checks the availability of required packages, verifies GitHub login status, and sets up a GitHub Personal Access Token (PAT) for authentication.

### Compare-KBUpdates.ps1

This script compares the currently installed KB ID with remote KB IDs to check if the local system is up to date.

## Bash Scripts

### Initialize-Ubuntu.sh

This script installs Docker and its dependencies, adds a user to the Docker group, and ensures all required packages are installed within an Ubuntu WSL distribution.

### Install-GCM.sh

This script configures Git to use the Git Credential Manager (GCM) for Windows as the default credential helper in a WSL distribution.
