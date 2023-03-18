from PIL import Image
from sprite import sprite
import dload
import glob, os, math, time, shutil, json, re, itertools, time

blankimg = 'blank256.png'
lines = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, "a", "b", "c", "d", "e", "f"]

download_url = os.environ.get("PACK_URL")
dload.save_unzip(download_url, "pack/")

def create_empty(glyph):
    if not os.path.exists(f"images/{glyph}"):
        os.makedirs(f"images/{glyph}")
    for line in lines:
        for linee in lines:
            if linee != lines:
                name = f"{line}{linee}"
                imagesus = Image.open(blankimg)
                image = imagesus.copy()
                image.save(f"images/{glyph}/0x{glyph}{name}.png", "PNG")
    for line in lines:
        name = f"{line}{line}"
        imagesus = Image.open(blankimg)
        image = imagesus.copy()
        image.save(f"images/{glyph}/0x{glyph}{name}.png", "PNG")

def imagetoexport(glyph):
    filelist = [file for file in os.listdir(f'images/{glyph}') if file.endswith('.png')]
    if not os.path.exists(f"export/{glyph}"):
        os.makedirs(f"export/{glyph}")
    for img in filelist:
        image = Image.open(blankimg)
        logo = Image.open(f'images/{glyph}/{img}')
        image_copy = image.copy()
        position = (0, 0)
        image_copy.paste(logo, position)
        image_copy.save(f"export/{glyph}/{img}")
        
with open("pack/assets/minecraft/font/default.json", "r") as f:
    data = json.load(f)
    symbols = [d['chars'] for d in data['providers']]
    paths = [d['file'] for d in data['providers']]
    
glyphs = []
for i in symbols:
    if i not in glyphs:
        symbolbe = ''.join(i)
        sbh = (hex(ord(symbolbe)))
        a = sbh[2:]
        ab = a[:2]
        glyphs.append(ab.upper())
glyphs = list(dict.fromkeys(glyphs))
print(glyphs)

def converterpack(glyph):
    if len(symbols) == len(paths):
        create_empty(glyph) 
        for symboll, path in zip(symbols, paths):
            symbolbe = ''.join(symboll)
            symbolbehex = (hex(ord(symbolbe)))
            symbol = symbolbehex[4:]
            symbolac = symbolbehex[2:]
            symbolcheck = symbolac[:2]
            if (symbolcheck.upper()) == (glyph.upper()):
                if ":" in path:
                    namespace = path.split(":")[0]
                    pathnew = path.split(":")[1]
                    imagefont = Image.open(f"pack/assets/{namespace}/textures/{pathnew}")
                    image = imagefont.copy()
                    os.remove(f"images/{glyph}/0x{glyph}{symbol}.png")
                    image.save(f"images/{glyph}/0x{glyph}{symbol}.png", "PNG")
                else:
                    imagefont = Image.open(f"pack/assets/minecraft/textures/{path}")
                    image = imagefont.copy()
                    os.remove(f"images/{glyph}/0x{glyph}{symbol}.png")
                    image.save(f"images/{glyph}/0x{glyph}{symbol}.png", "PNG")
            else:
                continue
        else:
            imagetoexport(glyph)
            sprite(glyph)
            
for glyph in glyphs:
    converterpack(glyph)
