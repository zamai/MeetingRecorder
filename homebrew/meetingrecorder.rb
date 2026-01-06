cask "meetingrecorder" do
  version "0.1"
  sha256 "7b32ed2530cfeebbdd3fa37debe663b2aa8614f37b112e7e5638668588b63bc7"

  url "https://github.com/zamai/MeetingRecorder/releases/download/v#{version}/MeetingRecorder-#{version}.zip"
  name "MeetingRecorder"
  desc "Record system audio and microphone simultaneously on macOS"
  homepage "https://github.com/zamai/MeetingRecorder"

  depends_on macos: ">= :sonoma"

  app "MeetingRecorder.app"

  # Remove quarantine attribute for unsigned app
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/MeetingRecorder.app"],
                   sudo: false
  end

  uninstall quit: "com.zamai.MeetingRecorder"

  zap trash: [
    "~/Library/Application Support/MeetingRecorder",
    "~/Library/Preferences/com.zamai.MeetingRecorder.plist",
  ]
end
