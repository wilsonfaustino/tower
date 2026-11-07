#!/bin/zsh
# Convert the code coverage in an .xcresult bundle to SonarQube generic test coverage XML.
# Based on SonarSource's xccov-to-sonarqube-generic.sh example.
# File paths are made relative to the repo root, because SonarQube runs on another runner.
# Usage: scripts/xccov-to-sonarqube-generic.sh <path.xcresult> > coverage.xml
set -euo pipefail

xcresult_path="$1"
repo_root="${0:A:h:h}"

echo '<coverage version="1">'
xcrun xccov view --archive "$xcresult_path" | sed -n \
  -e "/:\$/s#^${repo_root}/##" \
  -e '/:$/s/&/\&amp;/g;s/^\(.*\):$/  <file path="\1">/p' \
  -e 's/^ *\([0-9][0-9]*\): 0.*$/    <lineToCover lineNumber="\1" covered="false"\/>/p' \
  -e 's/^ *\([0-9][0-9]*\): [1-9].*$/    <lineToCover lineNumber="\1" covered="true"\/>/p' \
  -e 's/^$/  <\/file>/p'
echo '</coverage>'
