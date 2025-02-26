#!/usr/bin/env bash

set -eu

# -----------------------------------------------------------------------------
# SYNOPSIS
# This script installs Docker and its dependencies, adds a user to the Docker
# group, and ensures all required packages are installed.
#
# USAGE
# ./Initialize-Ubuntu.sh
# -----------------------------------------------------------------------------

if ! [ $(id -u) = 0 ]; then
   echo "The script needs to be run as root." >&2
   return 1
fi

# Function to get UID and GID of a user
get_uid_gid() {
    local username=$1
    local user_info=$(id "$username")
    local uid=$(echo "$user_info" | grep -oP 'uid=\K[0-9]+')
    local gid=$(echo "$user_info" | grep -oP 'gid=\K[0-9]+')
    echo "$uid $gid"
}

# Function to check if a source file exists
check_and_copy_file() {
    local username=$1
    local src_file=$2
    local dest_dir=$3
    local dest_file=$4

    local uid_gid
    uid_gid=$(get_uid_gid "$username")
    local uid=$(echo "$uid_gid" | awk '{print $1}')
    local gid=$(echo "$uid_gid" | awk '{print $2}')

    if [ -f "$src_file" ]; then
        echo "Source file $src_file exists. Copying to $dest_dir..."
        mkdir -p "$dest_dir"
        cp "$src_file" "$dest_dir/$dest_file"
        chown -R "$uid:$gid" "$dest_dir"
        chmod 700 "$dest_dir"
        chmod 600 "$dest_dir/$dest_file"
        echo "File copied and permissions set."
    else
        echo "Source file $src_file does not exist."
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if all required packages are installed
check_required_packages() {
    echo "Updating packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -y > /dev/null 2>&1 && apt upgrade -y > /dev/null 2>&1
    echo "Checking and installing required packages..."
    # Install yq from GitHub if not installed
    if ! command_exists yq; then
        echo "yq is not installed. Installing yq..."
        wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq > /dev/null 2>&1 && chmod +x /usr/bin/yq
        if command_exists yq; then
            echo "yq installed successfully."
        else
            echo "Error: yq installation failed."
            return 1
        fi
    fi
    
    # List of packages to install via apt-get
    depsPkgs=(
        ca-certificates
        curl
        jq
        gh
        wslu
        mc
        htop
    )
    
    # Install packages using apt-get
    for package in "${depsPkgs[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            echo "$package is not installed. Installing $package..."
            apt-get install -y "$package" > /dev/null 2>&1
        else
            echo "$package is already installed."
        fi
    done
    
    # Check the exit code of the last apt-get install command
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install one or more required packages."
        return 1
    fi
    
    echo "All required packages are installed."
}

# Function to install Docker
install_docker() {
    echo "Adding Docker's official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc > /dev/null 2>&1
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "Adding Docker repository to Apt sources..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "Installing Docker..."
    apt-get update > /dev/null 2>&1
    
    # List of Docker packages to install via apt-get
    dockerPkgs=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )
    
    # Install Docker packages using apt-get
    apt-get install -y "${dockerPkgs[@]}" > /dev/null 2>&1

    echo "Checking if Docker group exists..."
    # Check if docker group exists, if not create it
    if ! getent group docker > /dev/null; then
      echo "Docker group does not exist. Creating Docker group..."
      groupadd docker
    else
      echo "Docker group already exists."
    fi

    echo "Enabling and starting Docker service..."
    # Enable and start Docker service, Docker socket, and containerd
    systemctl enable --now docker.{service,socket}
    systemctl enable --now containerd.service

    echo "Configuring Docker to listen on TCP socket without TLS..."
    # Extract current ExecStart command
    current_exec_start=$(sed -n 's/^ExecStart=//p' /lib/systemd/system/docker.service)
    
    # Check and add missing parameters before "--containerd="
    if [[ ! "$current_exec_start" =~ "-H unix:///var/run/docker.sock" ]]; then
        current_exec_start=$(echo "$current_exec_start" | sed 's|--containerd=|-H unix:///var/run/docker.sock --containerd=|')
    fi
    if [[ ! "$current_exec_start" =~ "-H tcp://0.0.0.0:2375" ]]; then
        current_exec_start=$(echo "$current_exec_start" | sed 's|--containerd=|-H tcp://0.0.0.0:2375 --tls=false --containerd=|')
    fi
    
    # Create the override directory if it doesn't exist
    mkdir -p /etc/systemd/system/docker.service.d
    
    override_conf_path="/etc/systemd/system/docker.service.d/override.conf"
    override_conf_content="[Service]\nExecStart=\nExecStart=$current_exec_start"
    
    if [[ -f "$override_conf_path" ]]; then
        existing_override_content=$(cat "$override_conf_path")
        if [[ "$existing_override_content" == "$override_conf_content" ]]; then
            echo "Docker override.conf is already configured correctly."
        else
            echo "Updating Docker override.conf with the correct configuration..."
            echo -e "$override_conf_content" > "$override_conf_path"
        fi
    else
        echo "Creating Docker override.conf..."
        echo -e "$override_conf_content" > "$override_conf_path"
    fi
    
    # Check if keepwsl.service already exists and contains the necessary configuration
    keepwsl_service_path="/etc/systemd/system/keepwsl.service"
    keepwsl_service_content="[Unit]\nDescription=keepwsl.service\n\n[Service]\nExecStart=/mnt/c/Windows/System32/wsl.exe sleep infinity\n\n[Install]\nWantedBy=default.target"
    
    if [[ -f "$keepwsl_service_path" ]]; then
        existing_keepwsl_content=$(cat "$keepwsl_service_path")
        if [[ "$existing_keepwsl_content" == "$keepwsl_service_content" ]]; then
            echo "keepwsl.service is already configured correctly."
        else
            echo "Updating keepwsl.service with the correct configuration..."
            echo -e "$keepwsl_service_content" > "$keepwsl_service_path"
        fi
    else
        echo "Creating keepwsl.service..."
        echo -e "$keepwsl_service_content" > "$keepwsl_service_path"
    fi
    echo "Reloading systemd configuration..."
    systemctl daemon-reload
    
    echo "Restarting Docker service..."
    systemctl restart docker.{service,socket}

    echo "Enabling and starting keepwsl.service..."
    systemctl enable --now keepwsl.service
}

# Function to add user to Docker group
add_user_to_docker_group() {
    local username=$1
    echo "Adding user $username to the Docker group..."
    usermod -aG docker "$username"
    if [ $? -eq 0 ]; then
        echo "User $username added to the Docker group."
    else
        echo "Error: Failed to add user $username to the Docker group."
        return 1
    fi
}

# Main function to call all other functions
main() {
    local username=$1
    echo "Starting setup for user $username..."
    check_required_packages || return 1
    # Define the source and destination paths
    SRC_DOCKER_CONFIG_FILE=$(wslpath "$(wslvar USERPROFILE)\.docker\config.json")
    DST_DOCKER_CONFIG_DIR="/home/$username/.docker"
    DST_DOCKER_CONFIG_FILE="config.json"

    # Check if the source file exists and copy it to the default WSL user home
    check_and_copy_file "$username" "$SRC_DOCKER_CONFIG_FILE" "$DST_DOCKER_CONFIG_DIR" "$DST_DOCKER_CONFIG_FILE"
    install_docker || return 1
    add_user_to_docker_group "$username" || return 1
    echo "Setup completed successfully for user $username."
}

# Extract the list of users with UID 1000 and above
users=$(getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 {print $1}')

# Count the number of users
user_count=$(echo "$users" | wc -l)

if [ "$user_count" -eq 0 ]; then
  echo "Error: No users with UID 1000 or above found."
  return 1
elif [ "$user_count" -eq 1 ]; then
  DEFAULT_USERNAME=$(echo "$users" | head -n 1)
else
  echo "Multiple users found:"
  echo "$users" | while read -r user; do
    echo "Username: $user"
  done

  while true; do
    read -p "Enter the username to be used: " DEFAULT_USERNAME
    if echo "$users" | grep -q "^$DEFAULT_USERNAME$"; then
      break
    else
      echo "Error: Invalid username entered. Please try again."
    fi
  done
fi

# Call the main function with the default username
main "$DEFAULT_USERNAME"
if [[ $? -ne 0 ]]; then
    echo "An error occurred during the execution of setup-ubuntu.sh."
else
    echo "setup-ubuntu.sh completed successfully."
fi