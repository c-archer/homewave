cask "roomdeck-audio" do
  version "0.1.0-beta.4"
  sha256 "bd80cbe155f913c8b088c36e749030a9c97f240e98d4c9de610dcf94cc15894e"

  url "https://github.com/c-archer/roomdeck/releases/download/v#{version}/RoomDeck-Audio-#{version}-arm64.zip"
  name "RoomDeck Audio"
  desc "Native Apple Silicon controller for compatible Sonos systems"
  homepage "https://github.com/c-archer/roomdeck"

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
