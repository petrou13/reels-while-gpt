A free source-available GitHub publication can precede paid Apple distribution. Author: petrou13. License: PolyForm Noncommercial 1.0.0. See GITHUB.ru.md for the free ad-hoc prerelease workflow.

# Distribution preparation

The 1.16 local app uses ad-hoc signing and Hardened Runtime. It is not Developer ID signed or notarized. See PUBLISH.ru.md for the detailed workflow and SECURITY-AUDIT.ru.md for review scope and limitations.

Recommended first channel: direct download. Enroll in Apple's Developer Program, choose a permanent bundle identifier under your own namespace, create a Developer ID Application certificate in local Keychain, and configure a notarytool Keychain profile. Never commit or send passwords/private keys in chat.

Set CODE_SIGN_IDENTITY and RELEASE_BUNDLE_ID, then run `Release/distribute.sh prepare` to build and sign locally. After authorizing submission of the binary to Apple, set NOTARY_PROFILE to the existing Keychain profile name and run `Release/distribute.sh notarize`. The script requires Accepted status, staples and validates the app, assesses Gatekeeper and recreates the ZIP with a SHA-256 checksum. It never publishes to a website. Configure Xcode and accept its license on the signing machine first.

Before publishing, test the downloaded, quarantined Developer ID artifact on a clean Mac, including AX/Automation, the isolated WebKit scripts, saved sign-in after relaunch and data removal. Verify publisher identity, working support contact, hosted privacy policy, the included PolyForm Noncommercial license, accurate system requirements and screenshots without personal data. A new bundle ID uses separate settings, TCC consent and website storage; it requires a new sign-in rather than copying session tokens.

The current architecture is not App Sandbox enabled and is not ready for Mac App Store submission. Store release requires sandbox/automation/AX redesign and validation, App Store Connect setup, accurate privacy declarations for integrated Instagram web content, third-party service/brand review and Apple's approval. The native privacy manifest does not certify Instagram's privacy or tracking behavior.

Primary Apple references:
- https://developer.apple.com/macos/distribution/
- https://developer.apple.com/developer-id/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/help/account/membership/program-enrollment/
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
