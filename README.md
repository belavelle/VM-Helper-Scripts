# VM-Helper-Scripts

These are a collection of helper scripts that I use in my homelab to quickly setup linux clients and servers based on common tasks that I perform.

All scripts are provided as-is.

This script is meant to be run as a user not root which is why it's called with sudo.  Best practice is to never log into a server as root but always sudo when you want root access.

Install Docker
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/belavelle/VM-Helper-Scripts/refs/heads/main/install_docker_deb.sh)"

PVE Stacks - Has been removed from this repo and placed in it's own dedicated repository

Install Xmrig
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/belavelle/VM-Helper-Scripts/refs/heads/main/install_xmrig.sh)"

Copyright 2026 All Rights Reserved
