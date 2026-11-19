# small-tailscale-client

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-v1.2.4-brightgreen)
![Shell](https://img.shields.io/badge/shell-sh-blue)

`small-tailscale-client` installs and manages Tailscale on OpenWrt routers. The `tailscale-helper` menu lets you install Tailscale on local storage or in RAM and configure automatic updates.

The installer downloads the management scripts from this repository. To install the latest release, it reads the upstream `version.txt`, downloads the binary for your router’s architecture, and verifies its checksum. [Upstream Tailscale builds](https://github.com/CH3NGYZ/small-tailscale-openwrt/releases)

## 📋 Table of Contents

- [Core Features](#-core-features)
- [Quick Start](#-quick-start)
- [Installation Modes](#-installation-modes)
- [Script Index](#-script-index)
- [Management Tools](#-management-tools)
- [Configuration Guide](#-configuration-guide)
- [FAQ](#-faq)
- [Log Locations](#-log-locations)
- [Notification System](#-notification-system)
- [Contributing & License](#-contributing--license)

## ✨ Core Features

- **🚀 One-Click Installation** - Automated installation process with local and memory modes
- **🔄 Auto Update** - Scheduled version detection and automatic Tailscale updates
- **🌐 GitHub downloads** - Use GitHub directly by default or set a download mirror with `GITHUB_DOWNLOAD_BASE_URL`
- **📦 Version Management** - Install the latest upstream release by default or specify a release tag on the command line
- **🔔 Push Notifications** - Multiple notification methods (Server Chan, Bark, NTFY, PushPlus)
- **⚙️ Multi-Architecture Support** - Compatible with x86, ARM, MIPS and other architectures
- **🛠️ Script Updates** - Online update support for management script packages

## 🚀 Quick Start

### LuCI installation

| Official OpenWrt version | LuCI package |
| --- | --- |
| 24.10 | [Download the IPK (1.0.1-r1)](https://github.com/xubiaolin/small-tailscale-client/releases/download/luci-v1.0.1-r1/luci-app-small-tailscale_1.0.1-r1_all.ipk) |
| 25.12 | [Download the APK (1.0.1-r1)](https://github.com/xubiaolin/small-tailscale-client/releases/download/luci-v1.0.1-r1/luci-app-small-tailscale-1.0.1-r1.apk) · [APK signing key](https://github.com/xubiaolin/small-tailscale-client/releases/download/luci-v1.0.1-r1/small-tailscale.pem) |

Verify the downloads against the checksum list. [SHA256SUMS](https://github.com/xubiaolin/small-tailscale-client/releases/download/luci-v1.0.1-r1/SHA256SUMS) · [All release assets](https://github.com/xubiaolin/small-tailscale-client/releases/tag/luci-v1.0.1-r1)

On 25.12, copy the matching trusted `small-tailscale.pem` to `/etc/apk/keys/` on the router. In **System → Software**, update the package lists, upload the package, then sign in again. Open **Services → 精简版 Tailscale** to download the client, configure the node and view its logs. [Package build and installation instructions (Chinese)](README.md#在-luci-中安装和管理)

### Prerequisites

- OpenWRT system
- Network connectivity
- Basic shell environment

### Installation Steps

1. **Download and execute the installation script**

Run these commands on the router to fetch the installer from the project repository. To use a mirror, configure a service you trust under “GitHub download URL”.

```sh
download_base=${GITHUB_DOWNLOAD_BASE_URL:-https://github.com}
URL="${download_base%/}/xubiaolin/small-tailscale-client/raw/refs/heads/main/install.sh"
(curl -fL "$URL" -o /tmp/install.sh || wget -O /tmp/install.sh "$URL") && sh /tmp/install.sh
```

2. **Install Tailscale**

   Choose option `1` in the menu, select local or memory installation, and choose whether to enable auto-update. The installer then downloads the latest upstream release. To install a specific version, run `/etc/tailscale/setup.sh --version=TAG` with the desired release tag.

3. **Open the management menu**

```bash
tailscale-helper
```

For subnet routing, enter the LAN subnet in the LuCI plugin, save and start the node, then preview and apply the network configuration. Approve the subnet route in the Tailscale admin console. For manual setup, bind an unmanaged interface to `tailscale0`, leave the address, gateway and firewall zone empty, and add a forwarding rule restricted to incoming device `tailscale0` and the advertised destination subnet.

## 📦 Installation Modes

### Local Installation Mode

- **Characteristics**: Tailscale binary installed to `/usr/local/bin/`
- **Advantages**:
  - Persistent storage, retained after reboot
  - Optimal performance
  - Suitable for long-term operation
- **Disadvantages**:
  - Consumes system storage space
  - May conflict with system packages

**Use Case**: Devices with sufficient storage space

### Memory Installation Mode (Tmp)

- **Characteristics**: Tailscale binary stored in `/tmp/` memory
- **Advantages**:
  - No system storage consumption
  - Suitable for storage-limited devices
  - Easy cleanup
- **Disadvantages**:
  - Requires re-download after reboot
  - Higher memory usage

**Use Case**: Storage-limited devices

## 📚 Script Index

### Core Scripts

| Script Name                                | Function                                                                                                 | Invocation                    |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ----------------------------- |
| [`install.sh`](install.sh)                 | Main installation script, handles dependency checking, package download, verification and initialization | `sh install.sh`               |
| [`pretest_mirrors.sh`](pretest_mirrors.sh) | Run the installed download mirror test | Legacy installation entry point          |
| [`setup.sh`](scripts/setup.sh)             | Select the installation mode and update settings, then install Tailscale | `tailscale-helper` → Option 1 |
| [`helper.sh`](scripts/helper.sh)           | Main menu script providing 14 functional options in interactive interface                                | `tailscale-helper`            |

### Management Scripts

| Script Name                                            | Function                                                  | Invocation                          |
| ------------------------------------------------------ | --------------------------------------------------------- | ----------------------------------- |
| [`update_ctl.sh`](scripts/update_ctl.sh)               | Auto-update toggle control                                | `tailscale-helper` → Option 6       |
| [`autoupdate.sh`](scripts/autoupdate.sh)               | Auto-update execution logic, detects and updates versions | Scheduled task or manual invocation |
| [`github_direct_ctl.sh`](scripts/github_direct_ctl.sh) | Show the active GitHub download URL                | `tailscale-helper` → Option 8       |
| [`test_mirrors.sh`](scripts/test_mirrors.sh)           | Test the configured download mirror and verify the file                          | `tailscale-helper` → Option 12      |

### Service Scripts

| Script Name                                    | Function                                                        | Invocation                    |
| ---------------------------------------------- | --------------------------------------------------------------- | ----------------------------- |
| [`setup_service.sh`](scripts/setup_service.sh) | Generate and start Tailscale service                            | Called by setup.sh            |
| [`setup_cron.sh`](scripts/setup_cron.sh)       | Schedule automatic updates     | Called by setup.sh            |
| [`uninstall.sh`](scripts/uninstall.sh)         | Complete uninstallation of Tailscale and related configurations | `tailscale-helper` → Option 5 |

### Utility Scripts

| Script Name                                                      | Function                                                            | Invocation                     |
| ---------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------ |
| [`fetch_and_install.sh`](scripts/fetch_and_install.sh)           | Download and install Tailscale binary                               | Called by other scripts        |
| [`notify_ctl.sh`](scripts/notify_ctl.sh)                         | Notification system configuration management                        | `tailscale-helper` → Option 11 |
| [`tools.sh`](scripts/tools.sh)                                   | Common function library (logging, downloading, notifications, etc.) | Sourced by all scripts         |
| [`tailscale_up_generator.sh`](scripts/tailscale_up_generator.sh) | Generate Tailscale startup command                                  | `tailscale-helper` → Option 3  |

## 🎛️ Management Tools

### Main Menu (tailscale-helper)

The `tailscale-helper` menu opens offline. Choose option `10` to look up the latest upstream release.

```
1).  💾 Install / Reinstall Tailscale
2).  📥 Login to Tailscale
3).  📝 Generate Tailscale startup command
4).  📤 Logout from Tailscale
5).  ❌ Uninstall Tailscale
6).  🔄 Manage Tailscale auto-update
7).  🔄 Manually run update script
8).  🔄 Show GitHub download URL
9).  📦 View local Tailscale version
10). 📦 View remote Tailscale latest version
11). 🔔 Manage push notifications
12). 📊 Test configured download mirror
13). 🛠️ Update script package
14). 📜 Display Tailscale update log
0).  ⛔ Exit
```

### Auto-Update Management

Enable or disable auto-update:

```bash
# Via menu
tailscale-helper
# Select option 6 to manage Tailscale auto-update
```

Menu option 8 shows the active GitHub download URL. Option 12 tests the configured download mirror.

## ⚙️ Configuration Guide

### Configuration File Locations

All configuration files are stored in `/etc/tailscale/` directory:

```
/etc/tailscale/
├── install.conf          # Installation configuration (mode, version, architecture, etc.)
├── notify.conf           # Notification configuration (push service keys)
├── github-download.env   # Optional GitHub download URL for boot services and scheduled updates
├── current_version       # Current Tailscale version
└── scripts/              # All management scripts
```

### install.conf Configuration Items

```bash
# Installation mode: local or tmp
MODE=local

# Auto-update: true or false
AUTO_UPDATE=true

# Tailscale version: latest or specific version number
VERSION=latest

# System architecture: amd64, arm, arm64, mips, mipsle, etc.
ARCH=amd64

# Device hostname
HOST_NAME=OpenWrt

# Installation timestamp
TIMESTAMP=1234567890
```

### notify.conf Notification Configuration

```bash
# Notification switches
NOTIFY_UPDATE=1              # Update success notification
NOTIFY_MIRROR_FAIL=1         # Mirror failure notification
NOTIFY_EMERGENCY=1           # Emergency error notification

# Server Chan configuration
NOTIFY_SERVERCHAN=0
SERVERCHAN_KEY=""

# Bark configuration
NOTIFY_BARK=0
BARK_KEY=""

# NTFY configuration
NOTIFY_NTFY=0
NTFY_KEY=""

# PushPlus configuration
NOTIFY_PUSHPLUS=0
PUSHPLUS_TOKEN=""
```

## 🔄 Auto-Update

### How It Works

1. **Scheduled Detection**: Checks for new versions at random time between 4-6 AM daily
2. **Version Comparison**: Compares local version with remote latest version
3. **Automatic Update**: If new version available, automatically downloads and installs
4. **Service Restart**: Automatically restarts Tailscale service after update
5. **Push Notification**: Sends update success or failure notification based on configuration

### Scheduled Tasks

The installer schedules `/etc/tailscale/autoupdate.sh` to run daily. Use `crontab -l` to see the scheduled time.

## GitHub download URLs

The default download URL is `https://github.com`. Installation and automatic updates read `releases/latest/download/version.txt` from `CH3NGYZ/small-tailscale-openwrt`, then download the checksum and binary for that release.

To use a mirror for scripts and release files, export `GITHUB_DOWNLOAD_BASE_URL` before running the installation commands or `tailscale-helper`. A trailing slash is optional. For mirrors that expect a full GitHub URL in the path, append `/https://github.com` to the mirror URL.

```sh
export GITHUB_DOWNLOAD_BASE_URL='https://git.mirrors.imoyuapp.win/https://github.com'
```

This setting applies to the current shell and its child processes. For boot services and scheduled updates, put the same variable in `/etc/tailscale/github-download.env`. The file takes plain text assignments.

```text
GITHUB_DOWNLOAD_BASE_URL=https://git.mirrors.imoyuapp.win/https://github.com
```

The environment variable takes precedence over the file. An empty value selects the official URL for that process. For example, run `GITHUB_DOWNLOAD_BASE_URL= tailscale-helper` to use the official download URL for one session.

## ❓ FAQ

### Q1: Installation fails with missing dependency packages

**A**: The script automatically detects and installs required dependencies. If it still fails, manually install:

```bash
opkg update
opkg install libustream-openssl ca-bundle kmod-tun coreutils-timeout curl
```

### Q2: How to switch installation modes?

**A**: Re-run the installation script and select a different mode:

```bash
tailscale-helper
# Select option 1 to reinstall
```

### Q3: Auto-update is not working

**A**: Check the following:

1. Confirm auto-update is enabled: `tailscale-helper` → Option 6
2. Check scheduled tasks: `crontab -l`
3. View update log: `cat /var/log/tailscale_install.log`
4. Ensure network connectivity is normal

### Q4: How to manually update Tailscale?

**A**: Use menu option 7:

```bash
tailscale-helper
# Select option 7 to manually run update script
```

### Q5: How do I switch back to the official GitHub download URL?

Run `unset GITHUB_DOWNLOAD_BASE_URL` in your shell. If you set the variable in `/etc/tailscale/github-download.env`, remove its assignment there too. Then start `tailscale-helper` again.

### Q6: How to uninstall Tailscale?

**A**: Use menu option 5:

```bash
tailscale-helper
# Select option 5 to uninstall Tailscale
```

### Q7: How to check current version?

**A**: Use menu option 9:

```bash
tailscale-helper
# Select option 9 to view local version
```

Or check directly:

```bash
cat /etc/tailscale/current_version
```

### Q8: Which architectures are supported?

**A**: The following architectures are supported:

- x86: `386`, `amd64`
- ARM: `arm`, `arm64`
- MIPS: `mips`, `mipsle`, `mips64`, `mips64le`

The system automatically detects the architecture.

### Q9: How to configure push notifications?

**A**: Use menu option 11:

```bash
tailscale-helper
# Select option 11 to manage push notifications
```

### Q10: How to update the script package?

**A**: Use menu option 13:

```bash
tailscale-helper
# Select option 13 to update script package
```

## 📍 Log Locations

### System Logs

| Log File                         | Description           |
| -------------------------------- | --------------------- |
| `/var/log/tailscale_install.log` | Installation and update log |
| `logread -e tailscale` | Tailscale service messages in the system log |

### View Logs

```bash
# View installation log
tail -f /var/log/tailscale_install.log

# View service log
logread -f -e tailscale

# View update log
cat /var/log/tailscale_install.log

# View update log in menu
tailscale-helper
# Select option 14 to display Tailscale update log
```

## 🔔 Notification System

### Supported Notification Methods

#### 1. Server Chan (WeChat)

- **Get Key**: https://sct.ftqq.com/sendkey
- **Configuration**: Set SendKey in menu option 11

#### 2. Bark (iOS)

- **Get Key**: Install Bark app and get device code
- **Configuration**: Set device code in menu option 11
- **Format**: `https://api.day.app/KEYxxxxxxx` or self-hosted server address

#### 3. NTFY (Web/Mobile)

- **Get Key**: Visit https://ntfy.sh to create subscription
- **Configuration**: Set subscription code in menu option 11

#### 4. PushPlus (Web)

- **Get Key**: https://www.pushplus.plus
- **Configuration**: Set Token in menu option 11

### Notification Types

| Notification Type | Trigger Condition              | Configuration Item   |
| ----------------- | ------------------------------ | -------------------- |
| Update Success    | Tailscale successfully updated | `NOTIFY_UPDATE`      |
| Mirror Failure    | The configured download mirror failed its test       | `NOTIFY_MIRROR_FAIL` |
| Emergency Error   | Update or installation failed  | `NOTIFY_EMERGENCY`   |

### Configure Notifications

```bash
# Open menu
tailscale-helper

# Select option 11 to manage push notifications
# Follow prompts to configure each notification service

# Send test notification
# Select option 12 in menu
```

## 🤝 Contributing & License

### License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.

### Contributing

Issues and Pull Requests are welcome!

- [Report a bug or request a feature](https://github.com/xubiaolin/small-tailscale-client/issues)

### Acknowledgments

This project builds on CH3NGYZ’s OpenWrt installer and uses the binaries released by that project. [Upstream project](https://github.com/CH3NGYZ/small-tailscale-openwrt)

## 📞 Technical Support

- [GitHub Issues](https://github.com/xubiaolin/small-tailscale-client/issues)

---

**Version**: v1.1.0  
**Last Updated**: 2026-02-13  
**Upstream author**: CH3NGYZ
