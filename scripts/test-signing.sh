#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
signing_test_dir=$(mktemp -d "$PWD/.build/signing-test.XXXXXX")
trap 'rm -rf "$signing_test_dir"' EXIT
ditto build/MacBar.app "$signing_test_dir/first.app"
ditto build/MacBar.app "$signing_test_dir/second.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 9999' "$signing_test_dir/second.app/Contents/Info.plist"
./scripts/sign.sh "$signing_test_dir/second.app"
first_requirement=$(codesign -d -r- "$signing_test_dir/first.app" 2>&1 | sed -n 's/^designated => //p')
second_requirement=$(codesign -d -r- "$signing_test_dir/second.app" 2>&1 | sed -n 's/^designated => //p')
[[ -n "$first_requirement" && "$first_requirement" == "$second_requirement" && "$first_requirement" != *cdhash* ]]
first_hash=$(codesign -dv --verbose=4 "$signing_test_dir/first.app" 2>&1 | sed -n 's/^CDHash=//p')
second_hash=$(codesign -dv --verbose=4 "$signing_test_dir/second.app" 2>&1 | sed -n 's/^CDHash=//p')
[[ -n "$first_hash" && "$first_hash" != "$second_hash" ]]
codesign --verify --strict --test-requirement "=$first_requirement" "$signing_test_dir/second.app"
codesign --verify --strict --test-requirement "=$second_requirement" "$signing_test_dir/first.app"
print 'PASS: two versions with different contents retain the same identity and satisfy each other’s signing requirements.'
