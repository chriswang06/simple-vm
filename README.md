# SimpleVM

A minimal macOS- and Linux-guest VM for Apple Silicon, built on
`Virtualization.framework`. Single-binary CLI plus a SwiftUI window.

## Build

```sh
make build                  # debug + ad-hoc codesign with entitlement
make build CONFIG=release
```

Codesigning is required — without `com.apple.security.virtualization`,
`VZVirtualMachineConfiguration.validate()` fails.

## Sanity check

```sh
.build/debug/simple-vm --validate
```

## macOS guest

Restore from Apple's universal IPSW (~14 GB download, ~20 minutes):

```sh
.build/debug/simple-vm --install --guest mac --download
.build/debug/simple-vm   # boot
```

Or use a local IPSW:

```sh
.build/debug/simple-vm --install --guest mac --ipsw /path/to/UniversalMac.ipsw
```

## Linux guest

Create a bundle, then boot with an arm64 distro ISO to run the installer:

```sh
.build/debug/simple-vm --install --guest linux --bundle ~/VMs/Ubuntu --disk-gb 32

# First boot — attach the ISO; the distro's installer runs in the window:
.build/debug/simple-vm --bundle ~/VMs/Ubuntu --iso ~/Downloads/ubuntu-arm64.iso

# After install completes and you shut down the guest, boot from disk:
.build/debug/simple-vm --bundle ~/VMs/Ubuntu
```

### Rosetta-for-Linux (run x86_64 Linux binaries inside arm64 Linux)

```sh
.build/debug/simple-vm --install --guest linux --bundle ~/VMs/Ubuntu --rosetta
```

This installs Apple's Rosetta translator into the host (one-time, may prompt)
and exposes it to the guest as a virtio-fs share with the tag `rosetta`.
Inside the guest, mount it and register with `binfmt_misc`:

```sh
sudo mkdir /media/rosetta
sudo mount -t virtiofs rosetta /media/rosetta
# add binfmt_misc registration per Apple's docs
```

After that, x86_64 Linux binaries run transparently on the arm64 guest.

## Bundle layout

```
~/VMs/SimpleVM/
├── disk.img              # virtual disk (sparse)
├── settings.json         # cpu / memory / display / guest type
│
│  macOS guest only:
├── aux.bin               # firmware / NVRAM
├── identifier.bin        # VZMacMachineIdentifier
├── hardware-model.bin    # VZMacHardwareModel
│
│  Linux guest only:
├── efi-vars.bin          # VZEFIVariableStore
└── generic-id.bin        # VZGenericMachineIdentifier
```

`settings.json` carries `guestType: "mac" | "linux"`; `simple-vm` auto-detects
on boot.

## Notes

- macOS 14+ host, Apple Silicon only.
- macOS guests can't sign in to iCloud / App Store / Messages (Apple block).
- Networking is NAT — guest gets internet, not LAN-reachable.
- GPU/CPU partitioning is not exposed by Apple Silicon. `cpuCount` in
  `settings.json` is the only knob.
- Windows guests are not supported by this project — Apple's framework
  presents virtio devices that stock Windows ARM ISOs don't accept without
  driver injection. Use UTM or Parallels for Windows.

## Releases

GitHub Actions builds and ad-hoc-signs an arm64 release tarball on tag push:

```sh
git tag v0.1.0
git push --tags
```
