"""Reject pictographs in shipped source/string catalogs, including escaped text.

Text copyright/trademark signs and ordinary punctuation are allowed. App icons
must use image assets or SF Symbols rather than Unicode pictographs. Scan all
source text (also comments) so unused strings cannot retain the old artwork.
"""
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PICTOGRAPHS = re.compile(
    '[\U0001F000-\U0001FAFF\u2600-\u27BF\u2300-\u23FF'
    '\u2B50\u2B55\u3030\u303D\u3297\u3299\uFE0F\u20E3]'
)


def decode_source(text):
    # Swift scalar escapes; do not decode backslash-n or non-ASCII prose.
    text = re.sub(r'\\u\{([0-9a-fA-F]{1,8})\}',
                  lambda m: chr(int(m[1], 16)), text)
    # Legacy .strings UTF-16 escapes, including surrogate pairs.
    text = re.sub(r'\\[uU]([0-9a-fA-F]{4})',
                  lambda m: chr(int(m[1], 16)), text)
    return text.encode('utf-16', 'surrogatepass').decode('utf-16', 'surrogatepass')


def check():
    failures = []
    count = 0
    for directory in ('TrollRoute', 'TrollRouteShare', 'TrollRouteActivity'):
        for path in (ROOT / directory).rglob('*'):
            if path.suffix not in ('.swift', '.strings', '.xcstrings', '.plist'):
                continue
            count += 1
            if path.suffix == '.plist':
                text = str(plistlib.loads(path.read_bytes()))
            else:
                text = path.read_text(encoding='utf-8')
                if path.suffix == '.xcstrings':
                    text = json.dumps(json.loads(text), ensure_ascii=False)
                else:
                    text = decode_source(text)
            found = sorted({f'U+{ord(c):04X}' for c in PICTOGRAPHS.findall(text)})
            if found:
                failures.append(f'{path.relative_to(ROOT)}: {", ".join(found)}')
    assert not failures, 'Emoji/pictographs in shipped text:\n' + '\n'.join(failures)
    print(f'PASS: no emoji in {count} app source, string and property-list files')


if __name__ == '__main__':
    assert PICTOGRAPHS.search(decode_source(r'\u{1F4CD}'))
    assert PICTOGRAPHS.search(decode_source(r'\UD83D\UDCCD'))
    assert not PICTOGRAPHS.search('figure.walk; mappin.circle.fill; Caf\u00e9; \u00a9 OpenStreetMap')
    check()
