#!/usr/bin/env bash

# shellcheck disable=SC2317,SC2129,SC1091,SC2120,SC2035,SC2016,SC2310,SC2155,SC2154,SC2034,2250,2249,2312,2292,2207

# Helper script to set up code signing environment for iOS/macOS publishing
# This guides users through the process of configuring signing identities and notarization credentials

set -e

echo "========================================"
echo "FFmpegKit Code Signing Setup"
echo "========================================"
echo ""
echo "This script will help you set up code signing for iOS/macOS XCFramework distribution."
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: Code signing must be performed on macOS"
  exit 1
fi

# Function to display menu
show_menu() {
  echo ""
  echo "What would you like to set up?"
  echo "1) Import code signing certificate"
  echo "2) List available signing identities"
  echo "3) Set up notarization credentials"
  echo "4) Test signing environment"
  echo "5) Sign and notarize XCFrameworks"
  echo "6) Exit"
  echo ""
}

# Import certificate
import_certificate() {
  echo ""
  echo "========================================"
  echo "Import Code Signing Certificate"
  echo "========================================"
  echo ""
  echo "To import your Developer ID Application certificate:"
  echo ""
  echo "1. Export your certificate from Keychain Access as .p12"
  echo "2. Run the following command:"
  echo ""
  echo "   security import YourCertificate.p12 \\"
  echo "     -k ~/Library/Keychains/login.keychain-db \\"
  echo "     -P <certificate-password>"
  echo ""
  echo "3. Make sure the certificate is trusted"
  echo ""
  
  read -p "Would you like to import a certificate now? (y/N): " import_now
  
  if [[ "${import_now,,}" == "y" ]]; then
    read -p "Path to .p12 file: " cert_path
    read -p "Certificate password: " -s cert_password
    echo ""
    
    if [[ -f "${cert_path}" ]]; then
      security import "${cert_path}" \
        -k ~/Library/Keychains/login.keychain-db \
        -P "${cert_password}"
      
      echo ""
      echo "✓ Certificate imported successfully"
    else
      echo "ERROR: Certificate file not found: ${cert_path}"
    fi
  fi
}

# List signing identities
list_identities() {
  echo ""
  echo "========================================"
  echo "Available Signing Identities"
  echo "========================================"
  echo ""
  
  local identities
  identities=$(security find-identity -v -p codesigning)
  
  if echo "${identities}" | grep -q "0 valid identities"; then
    echo "No valid signing identities found."
    echo ""
    echo "To get a signing identity:"
    echo "1. Enroll in Apple Developer Program: https://developer.apple.com/programs/"
    echo "2. Create a Developer ID Application certificate in Apple Developer Portal"
    echo "3. Download and install the certificate"
  else
    echo "${identities}"
    echo ""
    echo "Copy the identity name (between quotes) to use with --signing-identity"
    echo "Example: 'Developer ID Application: Your Company (TEAM123)'"
  fi
}

# Set up notarization
setup_notarization() {
  echo ""
  echo "========================================"
  echo "Notarization Setup"
  echo "========================================"
  echo ""
  echo "To notarize your binaries, you need:"
  echo ""
  echo "1. Apple ID enrolled in Apple Developer Program"
  echo "2. App-Specific Password"
  echo ""
  echo "To generate an App-Specific Password:"
  echo "1. Go to: https://appleid.apple.com/account/manage"
  echo "2. Sign in with your Apple ID"
  echo "3. Under 'Sign-In and Security', click 'App-Specific Passwords'"
  echo "4. Click 'Generate Password' and follow the prompts"
  echo "5. Copy the generated password (format: xxxx-xxxx-xxxx-xxxx)"
  echo ""
  echo "You'll also need your Team ID, found at:"
  echo "https://developer.apple.com/account/#/membership"
  echo ""
  
  read -p "Would you like to test your notarization credentials? (y/N): " test_notarization
  
  if [[ "${test_notarization,,}" == "y" ]]; then
    read -p "Apple ID: " apple_id
    read -p "App-Specific Password: " -s app_password
    echo ""
    read -p "Team ID: " team_id
    
    echo ""
    echo "Testing notarization credentials..."
    
    # Store password temporarily
    security add-generic-password \
      -a "${apple_id}" \
      -w "${app_password}" \
      -s "AC_PASSWORD" \
      -U 2>/dev/null || true
    
    # Test with altool
    if xcrun altool --list-providers \
      -u "${apple_id}" \
      -p "@keychain:AC_PASSWORD" 2>&1 | grep -q "${team_id}"; then
      echo "✓ Notarization credentials are valid"
      echo ""
      echo "Save these values for later:"
      echo "  --apple-id=${apple_id}"
      echo "  --team-id=${team_id}"
      echo "  --app-specific-password=<your-password>"
    else
      echo "✗ Failed to validate notarization credentials"
      echo "Check your Apple ID, password, and team ID"
    fi
  fi
}

# Test signing environment
test_environment() {
  echo ""
  echo "========================================"
  echo "Testing Signing Environment"
  echo "========================================"
  echo ""
  
  local issues=0
  
  # Check for codesign
  if command -v codesign &> /dev/null; then
    echo "✓ codesign tool available"
  else
    echo "✗ codesign tool not found"
    ((issues++))
  fi
  
  # Check for xcrun
  if command -v xcrun &> /dev/null; then
    echo "✓ xcrun tool available"
  else
    echo "✗ xcrun tool not found"
    ((issues++))
  fi
  
  # Check for altool
  if command -v altool &> /dev/null || xcrun altool --version &> /dev/null 2>&1; then
    echo "✓ altool available for notarization"
  else
    echo "⚠ altool not found (notarization will not work)"
  fi
  
  # Check signing identities
  local identity_count
  identity_count=$(security find-identity -v -p codesigning | grep -c "valid identity" || echo "0")
  
  if [[ ${identity_count} -gt 0 ]]; then
    echo "✓ Found ${identity_count} signing identity(ies)"
  else
    echo "✗ No signing identities found"
    ((issues++))
  fi
  
  # Check for XCFrameworks
  local xcframework_count
  xcframework_count=$(find prebuilt/apple/xcframeworks -name "*.xcframework" -type d 2>/dev/null | wc -l | tr -d ' ')
  
  if [[ ${xcframework_count} -gt 0 ]]; then
    echo "✓ Found ${xcframework_count} XCFramework(s) to sign"
  else
    echo "⚠ No XCFrameworks found in prebuilt/apple/xcframeworks/"
    echo "  Build XCFrameworks first using: scripts/apple/build_xcframework.sh"
  fi
  
  echo ""
  if [[ ${issues} -eq 0 ]]; then
    echo "✓ Environment is ready for code signing"
  else
    echo "✗ Found ${issues} issue(s). Please resolve them before signing."
  fi
}

# Sign and notarize
sign_and_notarize() {
  echo ""
  echo "========================================"
  echo "Sign and Notarize XCFrameworks"
  echo "========================================"
  echo ""
  
  # Check if XCFrameworks exist
  if [[ ! -d "prebuilt/apple/xcframeworks" ]]; then
    echo "ERROR: No XCFrameworks found. Build them first."
    return
  fi
  
  echo "Available bundles:"
  ls -1 prebuilt/apple/xcframeworks/ | grep "\.xcframework$" | gsed 's/\.xcframework$//' | gsed 's/^ffmpegkit-//' | sort -u
  
  echo ""
  read -p "Bundles to sign (comma-separated, or 'all'): " bundle_input
  
  if [[ "${bundle_input}" == "all" || -z "${bundle_input}" ]]; then
    bundles="base,audio,video,video_hw,full"
  else
    bundles="${bundle_input}"
  fi
  
  read -p "Signing identity: " signing_identity
  read -p "Team ID: " team_id
  read -p "Apple ID (for notarization): " apple_id
  read -p "App-Specific Password: " -s app_password
  echo ""
  
  read -p "Skip notarization? (sign only) (y/N): " skip_notarization
  
  # Build command
  cmd="sudo ./scripts/apple/code_sign.sh --bundles=${bundles} --signing-identity='${signing_identity}' --team-id=${team_id}"
  
  if [[ -n "${apple_id}" ]]; then
    cmd="${cmd} --apple-id=${apple_id}"
  fi
  
  if [[ -n "${app_password}" ]]; then
    cmd="${cmd} --app-specific-password=${app_password}"
  fi
  
  if [[ "${skip_notarization,,}" == "y" ]]; then
    cmd="${cmd} --skip-notarization"
  fi
  
  echo ""
  echo "Running:"
  echo "${cmd}"
  echo ""
  
  eval "${cmd}"
}

# Main loop
while true; do
  show_menu
  read -p "Select option (1-6): " option
  
  case ${option} in
    1) import_certificate ;;
    2) list_identities ;;
    3) setup_notarization ;;
    4) test_environment ;;
    5) sign_and_notarize ;;
    6)
      echo "Goodbye!"
      exit 0
      ;;
    *)
      echo "Invalid option. Please select 1-6."
      ;;
  esac
done
