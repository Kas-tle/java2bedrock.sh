def sprite(glyph):
    from PIL import Image
    import os, math, time
    max_frames_row = 16.0
    frames = []
    tile_width = 256
    tile_height = 256

    spritesheet_width = 4096
    spritesheet_height = 4096
    
    files = []
    
    files = os.listdir(f"export/{glyph}")
    files.sort()
    print(files)
    
    for current_file in files:
        try:
            with Image.open(f"export/{glyph}/{current_file}") as im:
                frames.append(im.getdata())
                print(im.getdata)
        except:
            print(current_file + " is not a valid image")
    tile_width = frames[0].size[0]
    tile_height = frames[0].size[1]

    if len(frames) > max_frames_row :
        spritesheet_width = tile_width * max_frames_row
        required_rows = math.ceil(len(frames)/max_frames_row)
        spritesheet_height = tile_height * required_rows
    else:
        spritesheet_width = tile_width*len(frames)
        spritesheet_height = tile_height
    
    print(spritesheet_height)
    print(spritesheet_width)

    spritesheet = Image.new("RGBA",(int(spritesheet_width), int(spritesheet_height)))

    for current_frame in frames :
        top = tile_height * math.floor((frames.index(current_frame))/max_frames_row)
        left = tile_width * (frames.index(current_frame) % max_frames_row)
        bottom = top + tile_height
        right = left + tile_width
    
        box = (left,top,right,bottom)
        box = [int(i) for i in box]
        cut_frame = current_frame.crop((0,0,tile_width,tile_height))
    
        spritesheet.paste(cut_frame, box)
    try:
        os.makedirs("staging/targrt/rp/font", exist_ok = True)
    except OSError as error:
        print("Have Path")
    spritesheet.save(f"staging/target/rp/font/glyph_{glyph}.png", "PNG")
