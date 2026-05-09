class SimpleVm < Formula
  desc "Minimal macOS- and Linux-guest VM on Apple Silicon"
  homepage "https://github.com/chriswang06/simple-vm"
  version "0.1.0"
  url "https://github.com/chriswang06/simple-vm/releases/download/v#{version}/simple-vm-v#{version}-macos-arm64.tar.gz"
  sha256 "REPLACE_WITH_SHA256_AFTER_RELEASE"

  depends_on :macos => :sonoma
  depends_on arch: :arm64

  def install
    bin.install "simple-vm"
    pkgshare.install "SimpleVM.entitlements"

    # Strip quarantine (downloaded tarball) and re-sign so the virtualization
    # entitlement stays attached when brew copies the binary into Cellar.
    system "/usr/bin/xattr", "-d", "com.apple.quarantine", bin/"simple-vm" rescue nil
    system "/usr/bin/codesign",
           "--entitlements", pkgshare/"SimpleVM.entitlements",
           "--force", "--sign", "-",
           bin/"simple-vm"
  end

  def caveats
    <<~EOS
      simple-vm requires macOS 14+ on Apple Silicon.

      First run will prompt the system for virtualization permission.
      If a sandboxed launcher refuses, run from a Terminal.
    EOS
  end

  test do
    assert_match "SimpleVM", shell_output("#{bin}/simple-vm --help")
  end
end
