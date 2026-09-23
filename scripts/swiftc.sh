#!/bin/zsh
# Keep compiler caches and any CLT compatibility workaround inside this project.
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/clean-module-cache .build/toolchain
flags=(-swift-version 5 -target "$(uname -m)-apple-macosx13.0" -module-cache-path .build/clean-module-cache)
compiler_path=$(xcrun --find swiftc)
header_root="${compiler_path:h:h}/include/swift"
if [[ -f "$header_root/module.modulemap" && -f "$header_root/bridging.modulemap" ]] &&
   grep -q 'module SwiftBridging' "$header_root/module.modulemap" &&
   grep -q 'module SwiftBridging' "$header_root/bridging.modulemap"; then
  # Some upgraded CLT installations retain an obsolete identical module map.
  # A VFS overlay hides it only from this compilation, without changing the SDK.
  python3 - "$header_root/module.modulemap" "$PWD/.build/toolchain" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[2])
empty = root / 'empty.modulemap'
empty.write_text('// Obsolete duplicate SwiftBridging declaration hidden for this build.\n')
(root / 'overlay.json').write_text(json.dumps({'version': 0, 'roots': [
    {'type': 'file', 'name': sys.argv[1], 'external-contents': str(empty)}
]}))
PY
  flags+=(-vfsoverlay .build/toolchain/overlay.json -Xcc -ivfsoverlay -Xcc .build/toolchain/overlay.json)
fi
exec xcrun swiftc "${flags[@]}" "$@"
