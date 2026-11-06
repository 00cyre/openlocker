#!/bin/bash
# The public certificate pins the project's persistent signing identity. Its
# private key is kept outside the repository and in encrypted release secrets.
openlocker_release_fingerprint() {
  openssl x509 -inform DER -in "$OPENLOCKER_ROOT/signing/release.cer" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':'
}
openlocker_check_release_config() {
  if [[ "${OPENLOCKER_RELEASE:-0}" == 1 ]]; then
    if [[ -z "${OPENLOCKER_SIGNING_IDENTITY:-}" || "$OPENLOCKER_SIGNING_IDENTITY" == - ]]; then
      echo 'Release builds require the persistent OPENLOCKER_SIGNING_IDENTITY. Ad-hoc releases are refused.' >&2
      return 1
    fi
  fi
}
openlocker_sign() {
  local openlocker_target="$1" openlocker_identifier="$2"
  local openlocker_keychain_args=()
  if [[ -n "${OPENLOCKER_SIGNING_KEYCHAIN:-}" ]]; then
    openlocker_keychain_args=(--keychain "$OPENLOCKER_SIGNING_KEYCHAIN")
  fi
  if [[ -n "${OPENLOCKER_SIGNING_IDENTITY:-}" && "$OPENLOCKER_SIGNING_IDENTITY" != - ]]; then
    codesign --force --options runtime --timestamp=none --sign "$OPENLOCKER_SIGNING_IDENTITY" "${openlocker_keychain_args[@]}" --identifier "$openlocker_identifier" "$openlocker_target"
  else
    codesign --force --sign - --identifier "$openlocker_identifier" "$openlocker_target"
  fi
  codesign --verify --strict "$openlocker_target"
  if [[ "${OPENLOCKER_RELEASE:-0}" == 1 ]]; then
    local openlocker_fingerprint
    openlocker_fingerprint="$(openlocker_release_fingerprint)"
    codesign --verify --strict -R "=certificate root = H\"$openlocker_fingerprint\" and identifier \"$openlocker_identifier\"" "$openlocker_target"
  fi
}
