cask "roomdeck-audio" do
  version "0.1.0-beta.2"
  sha256 "9c5f6d011800cbba8c872f93a21afb4238736d9e640ea905c414309f424af338"

  url "https://github.com/c-archer/homewave/releases/download/v#{version}/RoomDeck-Audio-#{version}-arm64.zip"
  name "RoomDeck Audio"
  desc "Native Apple Silicon controller for compatible Sonos systems"
  homepage "https://github.com/c-archer/homewave"

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
