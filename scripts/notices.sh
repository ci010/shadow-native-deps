#!/usr/bin/env bash
set -euo pipefail
output=bundle/THIRD-PARTY-NOTICES.txt
printf 'Native dependency license notices. aria2 COPYING and LICENSE.OpenSSL are separate.\n' > "$output"
case "$(uname -s)" in
 MINGW*|MSYS*)
   # Include the installed toolchain's complete notice tree, a superset of the
   # statically linked OpenSSL/zlib/GCC runtime materials. No DLLs are bundled.
   test -d /mingw64/share/licenses/openssl
   find /mingw64/share/licenses -type f -print0 | sort -z | while IFS= read -r -d '' file; do
     printf '\n===== %s =====\n' "$file" >> "$output"
     cat "$file" >> "$output"
   done
   ;;
 Linux)
   for file in /usr/share/doc/libssl3/copyright /usr/share/doc/zlib1g/copyright /usr/share/doc/libstdc++6/copyright; do
     printf '\n===== %s =====\n' "$file" >> "$output"
     cat "$file" >> "$output"
   done
   ;;
 Darwin)
   printf 'Uses macOS system libraries/frameworks (see CI otool output). No third-party library binaries are bundled.\n' >> "$output"
   ;;
 *) exit 1 ;;
esac
