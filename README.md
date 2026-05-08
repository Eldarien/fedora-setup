# Fedora 44 Automated Setup Script

This repository contains an automated installation and configuration script for **Fedora 44**. It is designed to perform a full system setup from a live environment, arch-style.
Network connectivity is required during installation for package retrieval (Net-Install). UEFI and BIOS systems supported.

## Important Requirements

- Must be run as `root`
- Must be executed from a Fedora 44 Live ISO environment
- Recommended live environment: XFCE Spin (lighter, more stable for installation tasks)
- Do **not** run this script on an already installed system unless you fully understand its actions

---

## Getting the Script (from Live ISO)

Boot into a Fedora 44 Live environment, then open a terminal.

### 1. Become root
```bash
sudo -i
```

### 2. Install required tools
```bash
dnf install -y git
```

### 3. Clone the repository
```bash
git clone https://github.com/eldarien/fedora-setup
cd fedora-setup
```

### 4. Make the script executable
```bash
chmod +x setup.sh
```

### 5. Run the setup script
```bash
./setup.sh
```

---

## After Completion

Once the script finishes:

- Ensure all operations completed successfully
- If needed, you can chroot installed system and install additional packages or make changes:
```bash
chroot /mnt /bin/bash
```
- Reboot the system:

```bash
reboot
```

Remove the live media when prompted or after shutdown.
