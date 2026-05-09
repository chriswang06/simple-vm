# SimpleVM

A minimal macOS- and Linux-guest VM for Apple Silicon, built on
`Virtualization.framework`. Single-binary CLI plus a SwiftUI window.

> Requires **macOS 14+ on Apple Silicon** (M1/M2/M3/M4). Intel Macs are
> not supported — `Virtualization.framework`'s macOS-guest path is
> Apple-Silicon-only.

## Install

### From source (recommended)

```sh
git clone https://github.com/chriswang06/simple-vm.git
cd simple-vm
make build
.build/debug/simple-vm --help
```

The Makefile codesigns with the virtualization entitlement automatically.
Needs Xcode Command Line Tools (`xcode-select --install`).

### From a release tarball

After a release is cut, fetch the prebuilt arm64 binary:

```sh
VERSION=v0.1.0
curl -L -o simple-vm.tar.gz \
  https://github.com/chriswang06/simple-vm/releases/download/$VERSION/simple-vm-$VERSION-macos-arm64.tar.gz
tar -xzf simple-vm.tar.gz
cd simple-vm-$VERSION-macos-arm64
xattr -d com.apple.quarantine simple-vm 2>/dev/null || true
codesign --entitlements SimpleVM.entitlements --force --sign - simple-vm
./simple-vm --help
```

The `xattr` removes Gatekeeper's download quarantine; the `codesign` step
re-attaches the virtualization entitlement.

### Homebrew

```sh
brew tap chriswang06/tap
brew install simple-vm
```

(Requires the tap repo to be set up — see `Formula/simple-vm.rb` in this
repository.)

## Build (development)

```sh
make build                  # debug + ad-hoc codesign with entitlement
make build CONFIG=release
```

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

The release workflow attaches `simple-vm-vX.Y.Z-macos-arm64.tar.gz` and a
SHA256 checksum to a GitHub release with install instructions in the notes.

### Updating the Homebrew tap (optional)

After cutting a release:

```sh
# Compute the SHA256 of the new tarball
shasum -a 256 simple-vm-vX.Y.Z-macos-arm64.tar.gz

# Update Formula/simple-vm.rb with the new version + sha
# Push that file to chriswang06/homebrew-tap (Formula/simple-vm.rb)
```

Users then `brew upgrade simple-vm`.
