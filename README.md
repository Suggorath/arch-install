# arch-install

Arch Linux install script for SUGGORATH-PC (ASUS ROG STRIX X670E-F, Ryzen 7 7800X3D, RTX 4070 Ti SUPER).
It is written for this one PC: disk, user, host name and hardware are set in the CONFIG block of the script.

Run on the Arch Linux live ISO:

```bash
curl -LO https://raw.githubusercontent.com/Suggorath/arch-install/main/install.sh
bash install.sh
```

Before starting: put the firmware in Secure Boot Setup Mode (clear the Secure Boot keys in the BIOS).
The script erases the target disk set in `TARGET_DISK`.
