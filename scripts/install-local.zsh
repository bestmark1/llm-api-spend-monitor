#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
derived_data_path="${DERIVED_DATA_PATH:-${repo_root}/.build/DerivedData-Release}"
destination="${INSTALL_DESTINATION:-/Applications/LLMSpendMonitor.app}"
launch_after_install="${LAUNCH_AFTER_INSTALL:-1}"
source_app="${derived_data_path}/Build/Products/Release/LLMSpendMonitor.app"
staging_app="${destination}.installing.$$"

if [[ "${destination:t}" != "LLMSpendMonitor.app" ]]; then
    print -u2 "Refusing to replace an unexpected app path: ${destination}"
    exit 1
fi

cleanup() {
    /bin/rm -rf "${staging_app}"
}
trap cleanup EXIT

print "Building the signed Release app…"
/usr/bin/xcodebuild \
    -project "${repo_root}/LLMSpendMonitor.xcodeproj" \
    -scheme LLMSpendMonitor \
    -configuration Release \
    -derivedDataPath "${derived_data_path}" \
    -destination "platform=macOS" \
    -allowProvisioningUpdates \
    build

if [[ ! -d "${source_app}" ]]; then
    print -u2 "Release app was not produced at ${source_app}"
    exit 1
fi

print "Installing ${destination}…"
/usr/bin/pkill -x LLMSpendMonitor 2>/dev/null || true
/bin/mkdir -p "${destination:h}"
/bin/rm -rf "${staging_app}"
/usr/bin/ditto "${source_app}" "${staging_app}"
/usr/bin/codesign --verify --deep --strict "${staging_app}"
/bin/rm -rf "${destination}"
/bin/mv "${staging_app}" "${destination}"

if [[ "${launch_after_install}" == "1" ]]; then
    /usr/bin/open -n "${destination}"
fi

print "Installed successfully: ${destination}"
print "Enable Options → Settings → Launch at Login once to keep it in the menu bar after sign-in."
