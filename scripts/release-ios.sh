#!/bin/sh
# Archives the iOS app (with its widgets and the watch app) and uploads it to App Store Connect,
# signed automatically with the team's distribution certificate through the Apple ID signed in
# to Xcode. The version is MARKETING_VERSION in App/project.yml; the build number is the commit
# count on main, so every upload can be traced to a commit. The upload then shows in TestFlight
# and can be picked for an App Store submission.
# Usage: scripts/release-ios.sh
#   MOONRISE_PUBLISH  0 archives and exports the .ipa to .build/ios-release without uploading
set -eu

cd "$(dirname "$0")/.."
publish="${MOONRISE_PUBLISH:-1}"
team=ZCNAX3VL9D

if [ "$publish" != 0 ]; then
    [ -z "$(git status --porcelain)" ] || { echo "The working tree has changes." >&2; exit 1; }
    [ "$(git branch --show-current)" = main ] || { echo "Release from main." >&2; exit 1; }
fi

version="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' App/project.yml | sort -u)"
[ "$(printf '%s\n' "$version" | wc -l | tr -d ' ')" = 1 ] || { echo "The targets' MARKETING_VERSION differ: $version" >&2; exit 1; }
build="$(git rev-list --count HEAD)"

command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen" >&2; exit 1; }
(cd App && xcodegen generate --quiet)

out=.build/ios-release
rm -rf "${out:?}"
mkdir -p "$out"
archive="$out/moonrise.xcarchive"
xcodebuild archive -project App/Moonrise.xcodeproj -scheme Moonrise -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates -quiet \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build"

if [ "$publish" = 0 ]; then destination=export; else destination=upload; fi
cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>$destination</string>
    <key>teamID</key>
    <string>$team</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$out/ExportOptions.plist" \
    -exportPath "$out/export" -allowProvisioningUpdates -quiet

if [ "$publish" = 0 ]; then
    echo "Exported $(ls "$out"/export/*.ipa): $version ($build), not uploaded"
else
    echo "Uploaded Moonrise $version ($build) to App Store Connect; it shows in TestFlight once processed"
fi
