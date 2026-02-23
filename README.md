# dietpi-zero2-bootstrap

A single-script bootstrap for a headless Raspberry Pi Zero 2W running DietPi, Pi-hole, Unbound, and NUT client. Run it on your host machine after flashing, answer a few prompts, insert the card, and walk away.

---

## Background

The individual pieces of this setup — Pi-hole, Unbound, NUT client, VLAN interfaces, static networking — were all figured out organically through real-world use. What this script does is tie all of that accumulated knowledge into a reproducible, automated rebuild process, so that replacing a worn-out SD card doesn't mean starting from scratch.

The script itself was developed through a conversation with [Claude](https://claude.ai) (Anthropic), which helped formalize the approach, structure the automation, and think through edge cases like NUT's tmpfiles symlink quirk and the ordering of first-boot operations.

---

## What This Does

After flashing a fresh DietPi image, `prepare_sd.sh` runs on your host machine and:

- Configures `dietpi.txt` for fully automated, headless first boot (static IP, timezone, locale, hostname, no WiFi, no Bluetooth, no serial console)
- Queues Pi-hole and Unbound for automatic installation via DietPi's software installer
- Writes `Automation_Custom_Script.sh` to the boot partition, which runs on first boot to:
  - Write `/etc/network/interfaces` and VLAN interface config
  - Purge WiFi and Bluetooth packages
  - Disable the serial console
  - Install and configure NUT client (including the tmpfiles symlink fix)
  - Flip DNS to `127.0.0.1` once Unbound is installed
  - Restore your Pi-hole configuration from a Teleporter backup
  - Set `HISTCONTROL=ignoreboth:erasedups` in `.bashrc`
  - Pre-populate `.bash_history` with useful commands
- Copies your Pi-hole Teleporter zip to the boot partition for the first-boot restore

All sensitive and environment-specific values (IPs, passwords, UPS details) are prompted at runtime — nothing is hardcoded, making the script safe to store publicly.

---

## Prerequisites

- A Raspberry Pi Zero 2W
- A freshly flashed DietPi SD card (recommended: Sandisk Max Endurance 32GB or equivalent endurance-rated card)
- [Balena Etcher](https://etcher.balena.io) or similar to flash the image
- A host machine running Linux or macOS to run the script (Windows users: WSL works)
- A Pi-hole Teleporter backup `.zip` exported from your previous Pi-hole instance
- An existing NUT server on your network

---

## Usage

**1. Flash DietPi to your SD card** using Balena Etcher or your preferred tool.

**2. Mount the boot partition** on your host machine. On Linux it typically auto-mounts; on macOS it will appear in Finder.

**3. Run the script:**

```bash
sudo bash prepare_sd.sh <path_to_boot_partition> <path_to_teleporter_zip>
```

For example:
```bash
sudo bash prepare_sd.sh /media/youruser/bootfs ~/pihole-teleporter.zip
```

**4. Answer the prompts.** Defaults are shown in brackets — press Enter to accept or type to override. You'll be asked for:

- Hostname, timezone, locale, DietPi password
- Static IP, netmask, gateway
- VLAN IPs as a comma-separated list (mapped to `eth0.2`, `eth0.3`, etc. in order)
- NUT UPS name, server IP, port, username, and password

**5. Eject the SD card safely** and insert it into the Pi. First boot will take several minutes as DietPi installs software and runs the automation script.

**6. Verify** by SSHing in once the Pi is online and checking `/var/log/dietpi-automation-custom.log` to confirm all steps completed successfully.

---

## Contributing

This repo reflects a specific personal setup — Pi-hole + Unbound + NUT client on a Pi Zero 2W under DietPi. Pull requests that improve robustness, portability, or documentation are welcome. Forks that adapt it to different stacks or hardware are equally encouraged.

---

## License

MIT — do whatever you like with it.
