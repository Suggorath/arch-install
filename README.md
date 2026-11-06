# arch-install

Arch Linux install script for SUGGORATH-PC (ASUS ROG STRIX X670E-F, Ryzen 7 7800X3D, RTX 4070 Ti SUPER).
It is written for this one PC: disk, user, host name and hardware are set in the CONFIG block of the script.

Run on the Arch Linux live ISO:

```bash
curl -LO https://raw.githubusercontent.com/Suggorath/arch-install/main/install.sh
bash install.sh
```

New install (`KEEP_HOME="no"`, default): put the firmware in Secure Boot Setup Mode first (clear the Secure
Boot keys in the BIOS). The script erases the target disk set in `TARGET_DISK`, creates its own Secure Boot keys
and enrolls them together with the Microsoft and firmware keys. Switch Secure Boot on after the install.

Reinstall (`KEEP_HOME="yes"`): switch Secure Boot off in the BIOS (keep the keys), set `KEEP_HOME="yes"` in the
script (`nano install.sh`) and run it. Only the ESP and root are formatted; `/home` and the Secure Boot keys
(backup in `/home/sbctl-keys-backup`) are kept. Switch Secure Boot on again afterwards.
