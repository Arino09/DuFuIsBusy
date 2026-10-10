"""Extract the complete OFL-licensed SC face for user-entered Chinese text."""
from pathlib import Path
from fontTools.ttLib import TTFont
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
font = TTFont(args.source, fontNumber=2)
font.save(root / 'assets' / 'fonts' / 'CreativeSansSC.otf')
