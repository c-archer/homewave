cask "roomdeck-audio" do
  version "0.1.0-beta.3"
  sha256 "6b3a733b5d63fd78ec3e1d861c122119213374e61eebd4c3f2130e4ffbbd3373"

  url "https://github.com/c-archer/homewave/releases/download/v#{version}/RoomDeck-Audio-#{version}-arm64.zip"
  name "RoomDeck Audio"
  desc "Native Apple Silicon controller for compatible Sonos systems"
  homepage "https://github.com/c-archer/homewave"

  livecheck do
    skip "Only prerelease builds are currently published"
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "RoomDeck Audio.app"

  uninstall quit: "uk.co.roomdeck.audio"

  zap trash: "~/Library/Preferences/uk.co.roomdeck.audio.plist"

  caveats <<~EOS
    This community beta is ad-hoc signed and is not Apple-notarized.
    Review the source and release checksum before installing it.
  EOS
end
