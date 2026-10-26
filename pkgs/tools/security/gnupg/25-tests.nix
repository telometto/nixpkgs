{
  runCommand,
  gnupg,
}:

runCommand "gnupg-output-permissions"
  {
    nativeBuildInputs = [ gnupg ];
  }
  ''
    export GNUPGHOME="$TMPDIR/gnupg"
    mkdir -m 700 "$GNUPGHOME"
    trap 'gpgconf --kill all' EXIT
    umask 022

    head -c 4096 /dev/zero > plaintext
    gpg --batch --yes --pinentry-mode loopback --passphrase test-only \
      --s2k-count 65536 --compress-algo none --output encrypted.gpg \
      --symmetric plaintext

    for mode in 600 640 700; do
      printf 'previous output' > output
      chmod "$mode" output
      gpg --batch --yes --pinentry-mode loopback --passphrase test-only \
        --output output --decrypt encrypted.gpg
      actual=$(stat -c %a output)
      if [[ "$actual" != "$mode" ]]; then
        echo "Decryption changed output permissions: $mode -> $actual" >&2
        exit 1
      fi
      cmp plaintext output
      test ! -e output.part
    done

    gpg --batch --yes --pinentry-mode loopback --passphrase test-only \
      --output new-output --decrypt encrypted.gpg
    test "$(stat -c %a new-output)" = 644
    cmp plaintext new-output

    # Failed authentication must preserve the previous output and remove the
    # partial plaintext, including when the destination does not yet exist.
    cp encrypted.gpg truncated.gpg
    truncate -s -1 truncated.gpg
    printf 'previous output' > expected
    cp expected failed-output
    chmod 600 failed-output
    if gpg --batch --yes --pinentry-mode loopback --passphrase test-only \
      --output failed-output --decrypt truncated.gpg; then
      echo "Decryption unexpectedly accepted truncated ciphertext" >&2
      exit 1
    fi
    cmp expected failed-output
    test "$(stat -c %a failed-output)" = 600
    test ! -e failed-output.part
    if gpg --batch --yes --pinentry-mode loopback --passphrase test-only \
      --output failed-new-output --decrypt truncated.gpg; then
      echo "Decryption unexpectedly accepted truncated ciphertext" >&2
      exit 1
    fi
    test ! -e failed-new-output
    test ! -e failed-new-output.part

    touch "$out"
  ''
