#!/bin/bash

# No-Nonsense setup script for Fedora 44
# Based on ArchTitus

# Redirect stdout and stderr to setuplog.txt and still output to console
exec > >(tee -i setuplog.txt)
exec 2>&1

echo -ne "
-------------------------------------------------------------------------
                    Automated Fedora Linux Installer
-------------------------------------------------------------------------

"

if [ ! -f /usr/bin/dnf ]; then
    echo "This script must be run from an Fedora Linux ISO environment."
    exit 1
fi

root_check() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -ne "ERROR! This script must be run under the 'root' user!\n"
        exit 1
    fi
}

docker_check() {
    if awk -F/ '$2 == "docker"' /proc/self/cgroup | read -r; then
        echo -ne "ERROR! Docker container is not supported (at the moment)\n"
        exit 0
    elif [[ -f /.dockerenv ]]; then
        echo -ne "ERROR! Docker container is not supported (at the moment)\n"
        exit 1
    fi
}

fedora_check() {
    if [[ ! -e /etc/fedora-release ]]; then
        echo -ne "ERROR! This script must be run in Fedora Linux!\n"
        exit 1
    fi
}

dnf_check() {
    if [[ -f /run/dnf/rpmtransaction.lock ]]; then
        echo "ERROR! DNF is blocked."
        echo -ne "If not running remove /run/dnf/rpmtransaction.lock.\n"
        exit 1
    fi
}

background_checks() {
    root_check
    fedora_check
    dnf_check
    docker_check
}

select_option() {
    local options=("$@")
    local num_options=${#options[@]}
    local selected=0
    local last_selected=-1

    while true; do
        # Move cursor up to the start of the menu
        if [ $last_selected -ne -1 ]; then
            echo -ne "\033[${num_options}A"
        fi

        if [ $last_selected -eq -1 ]; then
            echo "Please select an option using the arrow keys and Enter:"
        fi
        for i in "${!options[@]}"; do
            if [ "$i" -eq $selected ]; then
                echo "> ${options[$i]}"
            else
                echo "  ${options[$i]}"
            fi
        done

        last_selected=$selected

        # Read user input
        read -rsn1 key
        case $key in
            $'\x1b') # ESC sequence
                read -rsn2 -t 0.1 key
                case $key in
                    '[A') # Up arrow
                        ((selected--))
                        if [ $selected -lt 0 ]; then
                            selected=$((num_options - 1))
                        fi
                        ;;
                    '[B') # Down arrow
                        ((selected++))
                        if [ "$selected" -ge "$num_options" ]; then
                            selected=0
                        fi
                        ;;
                esac
                ;;
            '') # Enter key
                break
                ;;
        esac
    done

    return $selected
}

# @description Displays logo
# @noargs
logo () {
# This will be shown on every set as user is progressing
echo -ne "
------------------------------------------------------------------------
            Please select presetup settings for your system
------------------------------------------------------------------------
"
}

# @description This function will handle file systems. At this movement we are handling only
# btrfs and ext4. Others will be added in future.
filesystem () {
    echo -ne "
    Please Select your file system for root partition.
    "
    options=("btrfs" "ext4" "luks+btrfs" "exit")
    select_option "${options[@]}"

    case $? in
    0) export FS=btrfs;;
    1) export FS=ext4;;
    2) export FS=luks;;
    3) exit ;;
    *) echo "Wrong option please select again"; filesystem;;
    esac
}

# @description Detects and sets timezone.
timezone () {
    echo -ne "\n"
    time_zone="$(curl -sfm 5 https://ipapi.co/timezone)"
    while true; do
        read -r -p "Detected timezone: '$time_zone'. Press Enter to accept or type a new one: " input
        TIMEZONE="${input:-$time_zone}"
        if [[ -f "/usr/share/zoneinfo/${TIMEZONE}" ]]; then
            break
        else
            echo "ERROR! Timezone '${TIMEZONE}' not found. Please enter a valid timezone (e.g. Europe/Kyiv)."
        fi
    done
    export TIMEZONE
}

# @description Set user's keyboard mapping.
keymap () {
    echo -e "\nAvailable keyboard layouts:\n"

    # Compact table
    local layouts=(
        us uk de fr es it pt nl be se no dk fi pl cz sk hu ro bg
        hr rs si ba mk gr tr ru ua by lt lv ee il ir in jp kr cn
    )

    local cols=4
    local i=0

    for layout in "${layouts[@]}"; do
        printf "%-8s" "$layout"
        ((i++))

        if (( i % cols == 0 )); then
            echo
        fi
    done

    echo -e "\n"

    while true; do
        read -r -p "Enter keyboard layout [us]: " keymap

        # default
        keymap=${keymap:-us}

        # lowercase normalize
        keymap=${keymap,,}

        # validate against actual system keymaps
        if localectl list-keymaps 2>/dev/null | grep -qx "$keymap"; then
            break
        fi

        echo "ERROR: Invalid keyboard layout '$keymap'"
    done

    echo -e "\nSelected keyboard layout: $keymap\n"

    export KEYMAP="$keymap"
}

# @description Derives a default locale from the selected keymap and lets the user confirm or override.
set_locale () {
    declare -A keymap_locale_map=(
        [us]="en_US.UTF-8"  [uk]="en_GB.UTF-8"  [ca]="en_CA.UTF-8"
        [cf]="fr_CA.UTF-8"  [by]="be_BY.UTF-8"  [cz]="cs_CZ.UTF-8"
        [de]="de_DE.UTF-8"  [dk]="da_DK.UTF-8"  [es]="es_ES.UTF-8"
        [et]="et_EE.UTF-8"  [fa]="fa_IR.UTF-8"  [fi]="fi_FI.UTF-8"
        [fr]="fr_FR.UTF-8"  [gr]="el_GR.UTF-8"  [hu]="hu_HU.UTF-8"
        [il]="he_IL.UTF-8"  [it]="it_IT.UTF-8"  [lt]="lt_LT.UTF-8"
        [lv]="lv_LV.UTF-8"  [mk]="mk_MK.UTF-8"  [nl]="nl_NL.UTF-8"
        [no]="nb_NO.UTF-8"  [pl]="pl_PL.UTF-8"  [ro]="ro_RO.UTF-8"
        [ru]="ru_RU.UTF-8"  [se]="sv_SE.UTF-8"  [sg]="de_CH.UTF-8"
        [si]="sl_SI.UTF-8"  [tr]="tr_TR.UTF-8"  [ua]="uk_UA.UTF-8"
    )
    local suggested_locale="${keymap_locale_map[${KEYMAP}]:-en_US.UTF-8}"
    while true; do
        read -r -p "Detected locale: '$suggested_locale'. Press Enter to accept or type a new one (e.g. de_DE.UTF-8): " input
        LOCALE="${input:-$suggested_locale}"
        # Basic sanity check: must look like xx_XX.UTF-8 or similar
        if [[ "${LOCALE}" =~ ^[a-z]{2,3}_[A-Z]{2,3}\. ]]; then
            break
        else
            echo "ERROR! Locale '${LOCALE}' does not look valid. Please enter a locale like en_US.UTF-8."
        fi
    done
    export LOCALE
}

# @description Auto-detects drive type (SSD, MMC, or HDD) and sets mount options accordingly.
drivessd () {
    local disk_name
    disk_name=$(basename "${DISK}")

    # eMMC / SD storage
    if [[ "${disk_name}" =~ ^mmcblk ]]; then
        export MOUNT_OPTIONS="noatime,compress=zstd:5,ssd,commit=120"
        echo "Detected MMC/eMMC drive (${disk_name}): using MMC mount options"

    # VirtIO disks (QEMU/KVM)
    elif [[ "${disk_name}" =~ ^vd[a-z] ]]; then
        export MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"
        echo "Detected VirtIO disk (${disk_name}): using SSD mount options"

    # Standard block devices with rotational flag
    elif [[ -f "/sys/block/${disk_name}/queue/rotational" ]]; then
        local rotational
        rotational=$(cat "/sys/block/${disk_name}/queue/rotational")

        if [[ "${rotational}" == "0" ]]; then
            export MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"
            echo "Detected SSD/NVMe drive (${disk_name}): using SSD mount options"
        else
            export MOUNT_OPTIONS="noatime,compress=zstd,commit=120"
            echo "Detected HDD (${disk_name}): using HDD mount options"
        fi

    # Fallback
    else
        export MOUNT_OPTIONS="noatime,compress=zstd,ssd,commit=120"
        echo "Could not detect drive type for ${disk_name}, defaulting to SSD mount options"
    fi
}

# @description Disk selection for drive to be used with installation.
diskpart () {
echo -ne "
------------------------------------------------------------------------
    THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK
    Make sure you know what you are doing because
    after formatting your disk there is no way to get data back
    *****BACKUP YOUR DATA BEFORE CONTINUING*****
    ***I AM NOT RESPONSIBLE FOR ANY DATA LOSS***
    ***PRESS CTRL-C TO STOP AND EXIT THE SCRIPT IF IN DOUBT***
------------------------------------------------------------------------

"

    #Loop through selection if non-viable device (mmcblkXbootY, mmcblkXrpbm, etc) is selected
    while true
    do
        PS3=$'\nSelect the disk to install on: '

        mapfile -t options < <(
            lsblk -n --output TYPE,KNAME,SIZE |
            awk '
                $1=="disk" &&
                $2 !~ /^loop/ &&
                $2 !~ /^zram/ &&
                $2 !~ /^sr/ {
                    print "/dev/" $2 "|" $3
                }
            '
        )

        select_option "${options[@]}"

        disk=${options[$?]%|*}

        if [[ ! "$disk" =~ ^/dev/mmcblk[0-9]+boot[0-9]+$ ]]
        then
            break
        fi

        echo -e "\n$disk is not a viable install drive\n"
    done

    echo -e "\n$disk selected\n"

    export DISK="$disk"

    drivessd
}

# @description Gather username and password to be used for installation.
userinfo () {
    # root password
    while true
    do
        read -rs -p "Please enter ROOT password: " PASSWORD1
        echo -ne "\n"
        read -rs -p "Please re-enter ROOT password: " PASSWORD2
        echo -ne "\n"
        if [[ "$PASSWORD1" == "$PASSWORD2" ]]; then
            break
        else
            echo -ne "ERROR! Passwords do not match. \n"
        fi
    done
    export ROOT_PASSWORD=$PASSWORD1

    # Loop through user input until the user gives a valid username
    echo -ne "\n"
    while true
    do
            read -r -p "Please enter username: " username
            if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]
            then
                    break
            fi
            echo "Incorrect username."
    done
    export USERNAME=$username

    while true
    do
        read -rs -p "Please enter password: " PASSWORD1
        echo -ne "\n"
        read -rs -p "Please re-enter password: " PASSWORD2
        echo -ne "\n"
        if [[ "$PASSWORD1" == "$PASSWORD2" ]]; then
            break
        else
            echo -ne "ERROR! Passwords do not match. \n"
        fi
    done
    export PASSWORD=$PASSWORD1

    # Loop through user input until the user gives a valid hostname, but allow the user to force save
    echo -ne "\n"
    while true
    do
            read -r -p "Please name your machine: " name_of_machine
            # hostname regex (!!couldn't find spec for computer name!!)
            if [[ "${name_of_machine,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]
            then
                    break
            fi
            # if validation fails allow the user to force saving of the hostname
            read -r -p "Hostname doesn't seem correct. Do you still want to save it? (y/n)" force
            if [[ "${force,,}" = "y" ]]
            then
                    break
            fi
    done
    export NAME_OF_MACHINE=$name_of_machine
}

configure_dnf() {
    local CONF="/etc/dnf/dnf.conf"

    # Ensure file exists
    [ -f "$CONF" ] || touch "$CONF"

    # Ensure [main] section exists
    if ! grep -q "^\[main\]" "$CONF"; then
        echo "[main]" >> "$CONF"
    fi

    add_or_update() {
        local key="$1"
        local value="$2"

        if grep -qE "^[#]*\s*${key}=" "$CONF"; then
            # Replace existing (commented or uncommented)
            sed -i -E "s|^[#]*\s*${key}=.*|${key}=${value}|" "$CONF"
        else
            # Add under [main]
            sed -i "/^\[main\]/a ${key}=${value}" "$CONF"
        fi
    }

    # Desired settings
    add_or_update "max_parallel_downloads" "10"
    add_or_update "fastestmirror" "True"
    add_or_update "defaultyes" "True"
    add_or_update "keepcache" "True"

    echo "DNF configuration updated."
    #grep -E "^(max_parallel_downloads|fastestmirror|defaultyes|keepcache)=" "$CONF" || true
}

rpm_fusion() {
    # Ask user whether RPM Fusion should be enabled
    echo -ne "\n"
    RPMFUSION_ENABLED=0
    read -rp "Install RPM Fusion repositories and multimedia codecs? [y/N]: " INSTALL_RPMFUSION
    case "${INSTALL_RPMFUSION,,}" in
        y|yes)
            RPMFUSION_ENABLED=1;;
        *)
            RPMFUSION_ENABLED=0;;
    esac
}


# Starting functions
background_checks
#clear
#logo
userinfo
#clear
#logo
diskpart
#clear
#logo
filesystem
#clear
#logo
timezone
#clear
#logo
keymap
#clear
#logo
set_locale
configure_dnf
rpm_fusion

echo -ne "
-------------------------------------------------------------------------
                    Installing Prerequisites
-------------------------------------------------------------------------
"
dnf -y install gdisk

echo -ne "
-------------------------------------------------------------------------
                    Formatting Disk
-------------------------------------------------------------------------
"
umount -A --recursive /mnt # make sure everything is unmounted before we start
# disk prep
sgdisk -Z "${DISK}" # zap all on disk
sgdisk -a 2048 -o "${DISK}" # new gpt disk 2048 alignment

# create partitions
#sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' "${DISK}" # partition 1 (BIOS Boot Partition)
#sgdisk -n 2::+1GiB --typecode=2:ef00 --change-name=2:'EFIBOOT' "${DISK}" # partition 2 (UEFI Boot Partition)
#sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' "${DISK}" # partition 3 (Root), default start, remaining

# 1. BIOS boot (only used by legacy BIOS GRUB)
sgdisk -n 1::+1M \
       --typecode=1:ef02 \
       --change-name=1:'BIOSBOOT' "${DISK}"

# 2. EFI System Partition (UEFI only)
sgdisk -n 2::+512M \
       --typecode=2:ef00 \
       --change-name=2:'EFI' "${DISK}"

# 3. /boot
sgdisk -n 3::+2G \
       --typecode=3:8300 \
       --change-name=3:'BOOT' "${DISK}"

# 4. ROOT
sgdisk -n 4::-0 \
       --typecode=4:8300 \
       --change-name=4:'ROOT' "${DISK}"

if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
    sgdisk -A 1:set:2 "${DISK}"
fi
partprobe "${DISK}" # reread partition table to ensure it is correct

# make filesystems
echo -ne "
-------------------------------------------------------------------------
                    Creating Filesystems
-------------------------------------------------------------------------
"
# @description Creates the btrfs subvolumes.
createsubvolumes () {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    # Set @ as the default subvolume so genfstab records subvolid=256 (not 5)
    # Path form requires btrfs-progs >= 5.6 (standard on Arch rolling)
    btrfs subvolume set-default /mnt/@
}

# @description Mount all btrfs subvolumes after root has been mounted.
mountallsubvol () {
    mount -o "${MOUNT_OPTIONS}",subvol=@home "${BTRFS_DEVICE}" /mnt/home
}

# @description BTRFS subvolulme creation and mounting.
subvolumesetup () {
# create nonroot subvolumes
    createsubvolumes
# unmount root to remount with subvolume
    umount /mnt
# mount @ subvolume
    mount -o "${MOUNT_OPTIONS}",subvol=@ "${BTRFS_DEVICE}" /mnt
# make directories for subvolumes
    mkdir -p /mnt/home
# mount subvolumes
    mountallsubvol
}

prompt_luks_password() {
    local pass1 pass2

    while true; do
        read -rsp "Enter LUKS password: " pass1; echo
        read -rsp "Confirm LUKS password: " pass2; echo

        if [[ -z "$pass1" ]]; then
            echo "Password cannot be empty"
            continue
        fi

        if [[ "$pass1" != "$pass2" ]]; then
            echo "Passwords do not match"
            continue
        fi

        LUKS_PASSWORD="$pass1"
        break
    done
}

if [[ "${DISK}" =~ "nvme"|"mmcblk" ]]; then
    partition2=${DISK}p2
    partition3=${DISK}p3
    partition4=${DISK}p4
else
    partition2=${DISK}2
    partition3=${DISK}3
    partition4=${DISK}4
fi



# Format EFI partition as FAT
mkfs.fat -F32 -n "EFI" "${partition2}"

# Format BOOT partition as EXT4
mkfs.ext4 -F "${partition3}"

# Format ROOT
if [[ "${FS}" == "btrfs" ]]; then
    mkfs.btrfs -f "${partition4}"
    mount -t btrfs "${partition4}" /mnt
    BTRFS_DEVICE="${partition4}"
    subvolumesetup
elif [[ "${FS}" == "ext4" ]]; then
    mkfs.ext4 -F "${partition4}"
    mount -t ext4 "${partition4}" /mnt
elif [[ "${FS}" == "luks" ]]; then
    # enter luks password to cryptsetup and format root partition
    prompt_luks_password
    printf "%s" "$LUKS_PASSWORD" | cryptsetup -v luksFormat "${partition4}" -
    # open luks container and ROOT will be place holder
    printf "%s" "$LUKS_PASSWORD" | cryptsetup open "${partition4}" ROOT -

    # now format that container
    mkfs.btrfs /dev/mapper/ROOT
    # create subvolumes for btrfs
    mount -t btrfs /dev/mapper/ROOT /mnt
    BTRFS_DEVICE=/dev/mapper/ROOT
    subvolumesetup
    ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value "${partition4}")
fi

sync

if ! mountpoint -q /mnt; then
    echo "ERROR! Failed to mount ${partition4} to /mnt after multiple attempts."
    exit 1
fi

BOOT_UUID=$(blkid -s UUID -o value "${partition3}")
mkdir -p /mnt/boot
mount -U "${BOOT_UUID}" /mnt/boot/

EFI_UUID=$(blkid -s UUID -o value "${partition2}")
mkdir -p /mnt/boot/efi
mount -U "${EFI_UUID}" /mnt/boot/efi

if ! grep -qs '/mnt' /proc/mounts; then
    echo "Drive is not mounted can not continue, please reboot."
    exit 1
fi

echo -ne "
-------------------------------------------------------------------------
                    Fedora Install on Main Drive
-------------------------------------------------------------------------
"

# ===== Generate fstab =====

ROOT_UUID=$(blkid -s UUID -o value "${partition4}")
EFI_UUID=$(blkid -s UUID -o value "${partition2}")

mkdir -p /mnt/etc

# Start fresh (avoid appending garbage on reruns)
: > /mnt/etc/fstab

# --- EFI ---
cat <<EOF >> /mnt/etc/fstab
UUID=${EFI_UUID} /boot/efi vfat umask=0077,shortname=winnt 0 2
EOF

# --- BOOT ---
cat <<EOF >> /mnt/etc/fstab
UUID=${BOOT_UUID} /boot ext4 defaults,noatime 0 2
EOF

# --- ROOT ---
if [[ "${FS}" == "btrfs" ]]; then
    cat <<EOF >> /mnt/etc/fstab
UUID=${ROOT_UUID} / btrfs subvol=@,${MOUNT_OPTIONS} 0 0
UUID=${ROOT_UUID} /home btrfs subvol=@home,${MOUNT_OPTIONS} 0 0
EOF

elif [[ "${FS}" == "ext4" ]]; then
    cat <<EOF >> /mnt/etc/fstab
UUID=${ROOT_UUID} / ext4 defaults,noatime 0 1
EOF

elif [[ "${FS}" == "luks" ]]; then
    # crypttab first (required for initramfs)
    cat <<EOF >> /mnt/etc/crypttab
ROOT UUID=${ENCRYPTED_PARTITION_UUID} none luks
EOF

    # fstab uses mapped device
    cat <<EOF >> /mnt/etc/fstab
/dev/mapper/ROOT / btrfs subvol=@,${MOUNT_OPTIONS} 0 0
/dev/mapper/ROOT /home btrfs subvol=@home,${MOUNT_OPTIONS} 0 0
EOF
fi

echo "
  Generated /etc/fstab:
"
cat /mnt/etc/fstab

# Core pseudo-filesystems
mkdir -p /mnt/{dev,proc,sys,run}
mount --bind /dev  /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys  /mnt/sys
mount --bind /run  /mnt/run

# Ensure efivars visible inside chroot (UEFI case)
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars
    UEFI=1
    echo "[*] UEFI detected"
else
    UEFI=0
    echo "[*] BIOS detected"
fi

echo -ne "
  Installing packages:
"
# Core OS and kernel
dnf -y --releasever=44 --installroot=/mnt --use-host-config install @core NetworkManager-tui NetworkManager-wifi wpa_supplicant htop fastfetch pciutils usbutils
dnf -y --releasever=44 --installroot=/mnt --use-host-config install grub2-efi-x64 grub2-efi-x64-modules shim-x64 grub2-tools grub2-pc efibootmgr
dnf -y --releasever=44 --installroot=/mnt --use-host-config install kernel iwlwifi\*
# Language packs
LANGPACKS="glibc-langpack-en"
LANG_PREFIX="${LOCALE%%_*}"
if [[ "$LANG_PREFIX" != "en" ]]; then
    LANGPACKS+=" glibc-langpack-${LANG_PREFIX}"
fi
dnf -y --releasever=44 --installroot=/mnt --use-host-config install $LANGPACKS

# Detect virtualization platform and install VM agents
VIRT_TYPE="$(systemd-detect-virt 2>/dev/null || true)"
if [[ "$VIRT_TYPE" == "qemu" || "$VIRT_TYPE" == "kvm" ]]; then
    dnf -y --releasever=44 --installroot=/mnt --use-host-config install -y qemu-guest-agent spice-vdagent
fi

# RPM Fusion
if [[ "$RPMFUSION_ENABLED" -eq 1 ]]; then
    dnf -y --releasever=44 --installroot=/mnt --use-host-config install @multimedia ffmpeg-free
    dnf -y --releasever=44 --installroot=/mnt --use-host-config install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    dnf -y --releasever=44 --installroot=/mnt --use-host-config update @core
    dnf -y --releasever=44 --installroot=/mnt --use-host-config update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    dnf -y --releasever=44 --installroot=/mnt --use-host-config swap ffmpeg-free ffmpeg --allowerasing
fi

setenforce 0

cp /etc/dnf/dnf.conf /mnt/etc/dnf/dnf.conf

cp /etc/default/grub /mnt/etc/default/grub
sed -i \
  -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' \
  /mnt/etc/default/grub

echo "[*] Applying system settings..."
chroot /mnt /bin/bash <<EOF
fixfiles -F onboot

echo "[chroot] Setting hostname..."
echo "$NAME_OF_MACHINE" > /etc/hostname

# --- Timezone ---
echo "[chroot] Setting timezone: $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime

# --- Locale ---
echo "[chroot] Setting locale: $LOCALE"
cat > /etc/locale.conf <<EOFCH
LANG=$LOCALE
LC_COLLATE=C
EOFCH

# --- Keymap ---
echo "[chroot] Setting keymap: $KEYMAP"
cat > /etc/vconsole.conf <<EOFCH
KEYMAP=$KEYMAP
FONT=latarcyrheb-sun16
EOFCH

echo "[chroot] Installing BIOS GRUB..."
grub2-install "$DISK"

echo "[chroot] Generating GRUB config..."
grub2-mkconfig -o /boot/grub2/grub.cfg

echo "[chroot] Creating users..."

# Root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Regular user
id -u "$USERNAME" >/dev/null 2>&1
if [ \$? -ne 0 ]; then
    useradd -m -G wheel -s /bin/bash "$USERNAME"
fi
echo "$USERNAME:$PASSWORD" | chpasswd

EOF
echo "[*] System configuration complete."
