# Homebrew formula for denryoku.
#
# This builds the CLI from source with SwiftPM. The Command Line Tools (or
# Xcode) provide the `swift` compiler — no extra toolchain needed.
#
# Tap + install (once published to GitHub):
#   brew tap ZachLiu519/tap https://github.com/ZachLiu519/denryoku
#   brew install ZachLiu519/tap/denryoku
#
# Or install the latest commit directly:
#   brew install --HEAD ZachLiu519/tap/denryoku
#
# Before the first tagged release, fill in `url` + `sha256` (get the sha with:
#   curl -sL <tarball-url> | shasum -a 256
# ).
class Denryoku < Formula
  desc "Granular CPU power tiers for Apple Silicon Macs via AppleCLPC"
  homepage "https://github.com/ZachLiu519/denryoku"
  url "https://github.com/ZachLiu519/denryoku/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "CHANGE_ME_RELEASE_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/ZachLiu519/denryoku.git", branch: "main"

  depends_on arch: :arm64
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/denryoku"
  end

  test do
    assert_match "denryoku", shell_output("#{bin}/denryoku --help")
    # Read-only; should run on any Apple Silicon Mac without root.
    system bin/"denryoku", "tiers"
  end
end
