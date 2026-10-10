"""Rebuild bundled SC font subsets from an installed, OFL-licensed Noto CJK source."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools import subset
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--source-dir', type=Path, default=Path('/usr/share/fonts/opentype/noto'))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
chars = ''.join(
    p.read_text(encoding='utf-8')
    for folder, pattern in [('scripts', '*.gd'), ('scenes', '*.tscn')]
    for p in (root / folder).rglob(pattern)
)
chars += ''.join(chr(i) for i in range(32, 127))
for kind in ['Sans', 'Serif']:
    font = TTFont(args.source_dir / f'Noto{kind}CJK-Regular.ttc', fontNumber=2)
    subsetter = subset.Subsetter()
    subsetter.populate(text=chars)
    subsetter.subset(font)
    font.save(root / 'assets' / 'fonts' / f'Source{kind}SC.otf')
