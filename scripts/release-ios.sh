#!/bin/sh
# Archives the iOS app (with its widgets and the watch app) and uploads it to App Store Connect.
# The version is MARKETING_VERSION in App/project.yml; the build number is the commit count on
# main, so every upload can be traced to a commit. The work is done by appstore-kit, checked out
# beside this repository or at $APPSTORE_KIT.
# Usage: scripts/release-ios.sh
#   MOONRISE_PUBLISH  0 archives and exports the .ipa to .build/ios-release without uploading
PUBLISH="${MOONRISE_PUBLISH:-1}"
name=Moonrise
project=App/Moonrise.xcodeproj
scheme=Moonrise
spec=App/project.yml
. "${APPSTORE_KIT:-$(dirname "$0")/../../appstore-kit}/release-ios.sh"
