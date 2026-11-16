#!/usr/bin/env bash
# wine_iphlpapi.sh -- lets real apps boot under Wine 9: gives the Wine prefix an
# iphlpapi.dll that has GetAnycastIpAddressTable.
#
# The JDK's NetworkInterface delay-loads that function, Wine 9's iphlpapi does
# not export it, and the delay-load failure (0xc06d007f) ends the JVM: any app
# that asks ConnectivityManager for the network, which is nearly every app from
# a store, died there. This builds a wrapper that forwards every export of
# Wine's own DLL (copied beside it as wineiphlp.dll) and adds the one missing
# function, answering an empty table. Then run with
#
#   WINEDLLOVERRIDES="iphlpapi=n,b"
#
# as run_app_wine.sh and the sweep under --launcher wine do. For the test
# environment only; nothing of it is part of a build. Newer Wine has the
# function, and the script then does nothing.
#
# Needs: mingw-w64 gcc (x86_64-w64-mingw32-gcc), wine.
set -euo pipefail
WINE="${WINE:-$(command -v wine64 || command -v wine)}"
SYS32="$(WINEDEBUG=-all "$WINE" winepath -u 'C:\windows\system32' 2>/dev/null)"
BUILTIN="$(find /usr/lib /usr/lib64 /opt -path '*x86_64-windows/iphlpapi.dll' 2>/dev/null | head -1)"
[[ -f "$BUILTIN" ]] || { echo "[wine_iphlpapi] Wine's iphlpapi.dll not found" >&2; exit 1; }
exports() { x86_64-w64-mingw32-objdump -p "$1" | awk '/\[Ordinal\/Name Pointer\] Table/{f=1;next} f&&NF>=2{print $NF}' |
    grep -E '^[A-Za-z_][A-Za-z0-9_@]*$' | sort -u; }
if exports "$BUILTIN" | grep -qx GetAnycastIpAddressTable; then
    echo "[wine_iphlpapi] this Wine has GetAnycastIpAddressTable: nothing to do"
    exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
{
    echo "LIBRARY iphlpapi.dll"
    echo "EXPORTS"
    exports "$BUILTIN" | sed 's/.*/  & = wineiphlp.&/'
    echo "  GetAnycastIpAddressTable"
} > "$WORK/iph.def"
cat > "$WORK/iph.c" <<'C'
#include <windows.h>
/* An empty MIB_ANYCASTIPADDRESS_TABLE, freed by FreeMibTable (the process heap). */
__declspec(dllexport) DWORD WINAPI GetAnycastIpAddressTable(USHORT family, void** table) {
    (void)family;
    *table = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, 256);
    return *table ? 0 : 8;
}
BOOL WINAPI DllMainCRTStartup(HINSTANCE inst, DWORD reason, void* reserved) {
    (void)inst; (void)reason; (void)reserved;
    return TRUE;
}
C
x86_64-w64-mingw32-gcc -shared -nostdlib -o "$WORK/iphlpapi.dll" "$WORK/iph.c" "$WORK/iph.def" -lkernel32
cp -f "$BUILTIN" "$SYS32/wineiphlp.dll"
cp -f "$WORK/iphlpapi.dll" "$SYS32/iphlpapi.dll"
echo "[wine_iphlpapi] installed in $SYS32; run with WINEDLLOVERRIDES=iphlpapi=n,b"
