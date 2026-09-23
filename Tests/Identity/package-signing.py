import hashlib
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

package = Path(sys.argv[1])
with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert not any(name.endswith('.debug.dylib') for name in names)
    app = 'Payload/TrollRoute.app/'
    info = plistlib.loads(archive.read(app + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.dm2mymcszt.trollroute'
    assert tuple(map(int, info['MinimumOSVersion'].split('.'))) == (15, 0)
    print('App:', info['CFBundleDisplayName'], info['CFBundleShortVersionString'], 'minimum iOS', info['MinimumOSVersion'])

    def inspect_binary(path, expected_plist):
        record = archive.getinfo(path)
        assert (record.external_attr >> 16) & 0o111, path + ' is not executable'
        data = archive.read(path)
        # Select an arm64 slice when the app is a universal Mach-O.
        if data[:4] == bytes.fromhex('cafebabe'):
            count = struct.unpack_from('>I', data, 4)[0]
            slices = [struct.unpack_from('>IIIII', data, 8 + 20*i) for i in range(count)]
            cpu, subtype, offset, size, align = next(s for s in slices if s[0] == 0x100000c)
            data = data[offset:offset+size]
        assert struct.unpack_from('<I', data)[0] == 0xfeedfacf
        assert struct.unpack_from('<I', data, 4)[0] == 0x100000c
        commands = struct.unpack_from('<I', data, 16)[0]
        pos = 32
        entitlements = None
        dependencies = {}
        minimum = None
        for _ in range(commands):
            command, size = struct.unpack_from('<II', data, pos)
            if command in (0xc, 0x80000018):  # LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB
                name_offset = struct.unpack_from('<I', data, pos+8)[0]
                name = data[pos+name_offset:pos+size].split(b'\0', 1)[0].decode('utf-8')
                dependencies[name] = command
            if command == 0x32:  # LC_BUILD_VERSION
                platform, minimum, sdk = struct.unpack_from('<III', data, pos+8)
                assert platform == 2, path + ' is not an iOS device binary'
            elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS
                minimum = struct.unpack_from('<I', data, pos+8)[0]
            if command == 0x1d:  # LC_CODE_SIGNATURE
                offset, length = struct.unpack_from('<II', data, pos+8)
                signature = data[offset:offset+length]
                magic, total, count = struct.unpack_from('>III', signature)
                assert magic == 0xfade0cc0
                for i in range(count):
                    slot, blob_offset = struct.unpack_from('>II', signature, 12+8*i)
                    if slot == 5:  # XML entitlements
                        magic, blob_length = struct.unpack_from('>II', signature, blob_offset)
                        assert magic == 0xfade7171
                        entitlements = plistlib.loads(signature[blob_offset+8:blob_offset+blob_length])
            pos += size
        expected = plistlib.loads(Path(expected_plist).read_bytes(), fmt=plistlib.FMT_XML)
        assert entitlements == expected, path + ' entitlements mismatch'
        expected_minimum = (16 << 16 | 1 << 8) if 'TrollRouteActivity.appex' in path else 15 << 16
        assert minimum == expected_minimum, path + ' binary deployment target mismatch'
        if path == app+'TrollRoute':
            for framework in ('ActivityKit', 'AppIntents'):
                library = '/System/Library/Frameworks/' + framework + '.framework/' + framework
                assert dependencies.get(library) == 0x80000018, framework + ' must be weak-linked for iOS 15'
            print('App: ActivityKit/AppIntents weak-linked; binary minimum iOS 15 (launch test still separate)')
        print(path, ': arm64, executable, expected entitlements present')

    inspect_binary(app+'TrollRoute', 'entitlements.plist')
    inspect_binary(app+'PlugIns/TrollRouteShare.appex/TrollRouteShare', 'TrollRouteShare/entitlements.plist')
    inspect_binary(app+'PlugIns/TrollRouteActivity.appex/TrollRouteActivity', 'TrollRouteActivity/entitlements.plist')

print('SHA256:', hashlib.sha256(package.read_bytes()).hexdigest())
print('Package inspection passed:', package.resolve())
