param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '../assets/stickers/weapon-sheet.png'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../assets/stickers')
)

# Reproducible cutouts of the supplied 3387 x 1780 sheet. The paths trace the
# visible weapon silhouettes; RGB samples are copied, never redrawn/generated.
# Pink/blue rectangular smear artifacts are excluded by their blade contours.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') {
    # System.Drawing on Windows uses the built-in .NET Framework assembly.
    & "$env:WINDIR/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -SourcePath $SourcePath -OutputDirectory $OutputDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Weapon extraction failed.' }
    return
}
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
public static class WeaponCutouts {
    public static void Extract(string source, string output, int x, int y, int w, int h, string outline, bool clearBlack) {
        using (var sheet = new Bitmap(source))
        using (var crop = sheet.Clone(new Rectangle(x,y,w,h), PixelFormat.Format32bppArgb))
        using (var mask = new Bitmap(w,h,PixelFormat.Format32bppArgb)) {
            var points = new List<PointF>();
            foreach (var token in outline.Split(new[]{' '},StringSplitOptions.RemoveEmptyEntries)) {
                var xy = token.Split(','); points.Add(new PointF(float.Parse(xy[0]),float.Parse(xy[1])));
            }
            using (var g = Graphics.FromImage(mask)) {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.FillPolygon(Brushes.White,points.ToArray());
            }
            var xmin=w; var ymin=h; var xmax=0; var ymax=0;
            for (var j=0;j<h;j++) for(var i=0;i<w;i++) {
                var c=crop.GetPixel(i,j); var a=mask.GetPixel(i,j).A;
                if(clearBlack && c.R<=12 && c.G<=12 && c.B<=12) a=0;
                crop.SetPixel(i,j,a==0 ? Color.FromArgb(0,0,0,0) : Color.FromArgb(a,c.R,c.G,c.B));
                if(a>0) { xmin=Math.Min(xmin,i); ymin=Math.Min(ymin,j); xmax=Math.Max(xmax,i); ymax=Math.Max(ymax,j); }
            }
            const int padding=6;
            using(var trimmed=new Bitmap(xmax-xmin+1+padding*2,ymax-ymin+1+padding*2,PixelFormat.Format32bppArgb)) {
                // Copy pixel-for-pixel; Graphics.DrawImage can apply source DPI.
                for(var j=ymin;j<=ymax;j++) for(var i=xmin;i<=xmax;i++)
                    trimmed.SetPixel(i-xmin+padding,j-ymin+padding,crop.GetPixel(i,j));
                trimmed.Save(output,ImageFormat.Png);
            }
        }
    }
}
'@

$source = [System.IO.Path]::GetFullPath($SourcePath)
$destination = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($destination) | Out-Null
$sheet = [System.Drawing.Bitmap]::new($source)
if ($sheet.Width -ne 3387 -or $sheet.Height -ne 1780) {
    $sheet.Dispose()
    throw 'Contours are authored for the original 3387 x 1780 source sheet.'
}
$sheet.Dispose()
$factor = 3387 / 2048.0
$items = @(
    @{
        Name='weapon-dusword'; Region=@(292,310,132,525); ClearBlack=$false
        Outline='106,15 113,17 126,36 134,52 135,66 130,75 125,79 122,100 120,126 119,154 120,176 125,189 123,199 122,207 129,218 132,241 138,251 150,255 166,253 179,241 187,227 203,225 201,301 193,391 185,461 179,517 169,522 162,529 159,540 163,553 180,565 180,645 180,706 183,757 187,790 197,817 179,826 156,836 133,843 109,847 87,846 63,840 40,831 20,820 26,785 30,744 32,696 34,646 35,566 48,558 53,549 53,537 48,527 34,521 12,225 25,227 29,235 35,243 48,252 63,257 77,252 85,245 86,235 92,228 97,220 93,215 92,204 97,194 99,183 98,151 97,112 95,92 91,80 86,70 84,60 87,47 91,34 95,24'
    },
    @{
        Name='weapon-pink-blade'; Region=@(610,448,294,270); ClearBlack=$false
        Outline='96,171 113,163 150,143 164,145 162,132 179,124 204,105 230,82 258,58 280,42 303,31 305,27 325,19 350,17 366,20 377,28 382,38 384,45 378,54 376,72 353,87 346,99 363,96 367,98 366,106 388,107 393,113 405,114 411,109 420,96 428,87 437,75 440,65 447,64 445,59 455,47 459,39 459,34 464,33 470,61 471,73 467,80 470,88 466,106 457,129 444,152 421,177 395,195 395,184 30,430 14,431 276,234 350,180 391,153 391,139 376,144 354,151 321,154 287,151 273,146 259,154 224,164 181,178 146,188 126,195 114,192 107,183 98,179'
    },
    @{
        Name='weapon-silver-sword'; Region=@(1076,269,86,580); ClearBlack=$false
        Outline='79,28 85,28 90,36 96,43 99,58 103,69 107,73 108,82 102,94 99,104 94,117 86,125 78,132 78,154 77,184 80,213 90,238 94,244 96,254 103,261 115,271 124,259 128,257 131,269 130,283 126,291 129,298 130,316 124,326 121,333 109,341 102,346 103,857 97,881 86,908 80,920 73,911 65,888 59,856 58,399 54,391 62,379 66,373 58,372 53,375 51,370 57,361 66,349 78,341 84,334 90,320 89,307 82,297 71,295 65,301 62,311 60,320 54,332 48,339 48,352 37,359 41,344 39,325 31,313 13,300 11,293 26,282 30,270 33,259 42,262 54,262 64,259 67,251 67,242 64,233 65,219 68,196 69,166 67,141 64,125 62,120 61,114 68,103 61,102 56,96 56,90 62,83 62,74 65,62 70,54 77,50 77,43 74,35'
    },
    @{
        Name='weapon-blue-sword'; Region=@(1300,370,318,395); ClearBlack=$false
        Outline='491,15 505,14 504,22 498,23 490,32 482,44 474,57 464,69 454,81 445,94 435,106 426,118 416,132 412,145 405,151 403,162 394,174 384,183 380,196 371,199 370,211 362,218 363,226 355,239 344,257 335,278 323,296 309,315 297,333 284,352 268,370 21,630 34,614 74,566 111,521 151,474 187,427 219,384 254,340 264,326 275,313 283,298 292,286 300,272 311,258 320,244 328,230 337,216 345,200 351,189 357,178 363,167 372,157 382,154 386,144 395,138 398,122 408,114 414,101 422,94 431,82 442,70 451,60 461,49 470,39 480,27'
    },
    @{
        Name='weapon-violet-greatsword'; Region=@(1744,114,179,773); ClearBlack=$true
        Outline='231,20 225,56 225,88 218,104 209,111 202,153 199,192 197,232 198,277 192,301 184,320 197,328 201,343 215,350 215,365 228,377 254,382 274,385 274,398 258,400 253,449 243,453 217,449 210,451 208,461 217,467 217,483 225,498 219,538 218,601 217,697 212,708 201,708 187,702 181,682 178,663 170,656 163,659 162,673 166,682 160,693 160,708 153,713 152,728 159,731 160,747 153,751 154,765 161,772 161,794 153,796 154,808 163,815 172,1050 175,1116 183,1135 192,1147 198,1141 197,1126 197,1110 211,1110 213,1172 215,1250 207,1255 193,1254 172,1250 150,1242 118,1238 102,1237 83,1234 71,1230 27,464 40,472 54,485 76,499 97,502 101,499 100,482 89,470 77,454 75,445 78,424 91,422 93,411 93,389 92,374 115,371 123,359 132,357 131,343 149,345 163,341 169,331 170,318 174,310 172,299 174,281 178,253 181,224 184,195 185,173 186,146 187,128 188,109 188,85 193,62 205,45 218,35'
    }
)
foreach ($item in $items) {
    $r=$item.Region
    [WeaponCutouts]::Extract($source, (Join-Path $destination ($item.Name+'.png')),
        [int]($r[0]*$factor), [int]($r[1]*$factor), [int]($r[2]*$factor), [int]($r[3]*$factor),
        $item.Outline, $item.ClearBlack)
    Write-Output ($item.Name+'.png')
}
