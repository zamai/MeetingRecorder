cask "meetingrecorder" do
  version "0.2"
  sha256 "abc35408d95a9a83a65ca8258d6f04c92b19cd5412459c8e399dd2bff7613ece"

  url "https://github.com/zamai/MeetingRecorder/releases/download/v#{version}/MeetingRecorder.zip"
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
