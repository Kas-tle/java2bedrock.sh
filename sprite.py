def sprite(glyph, spritesheet=None, tile=None):
    # Nhập các thư viện cần thiết
    from PIL import Image
    import os
    import math
    
    # Số tối đa các frame trên một dòng của spritesheet
    max_frames_row = 16.0
    
    # Danh sách các frame
    frames = []
    
    # Khởi tạo kích thước mặc định cho tile và spritesheet
    tile_width = None
    tile_height = None
    spritesheet_width = None
    spritesheet_height = None
    
    # Nếu tile hoặc spritesheet không được cung cấp, sử dụng kích thước mặc định
    if tile_width or tile_height or spritesheet_width or spritesheet_height is None:
        tile_width = 256
        tile_height = 256
        spritesheet_width = 4096
        spritesheet_height = 4096
    else:
        tile_width = tile
        tile_height = tile
        spritesheet_width = spritesheet
        spritesheet_height = spritesheet
    
    # Danh sách các file hình ảnh trong thư mục export/glyph
    files = os.listdir(f"export/{glyph}")
    files.sort()
    print(files)
    
    # Đọc và thêm hình ảnh vào danh sách frames
    for current_file in files:
        try:
            with Image.open(f"export/{glyph}/{current_file}") as im:
                frames.append(im.getdata())
        except:
            print(current_file + " is not a valid image")
    
    # Xác định kích thước tile từ frame đầu tiên
    tile_width = frames[0].size[0]
    tile_height = frames[0].size[1]

    # Tính toán kích thước của spritesheet
    if len(frames) > max_frames_row:
        spritesheet_width = tile_width * max_frames_row
        required_rows = math.ceil(len(frames) / max_frames_row)
        spritesheet_height = tile_height * required_rows
    else:
        spritesheet_width = tile_width * len(frames)
        spritesheet_height = tile_height
    
    print(spritesheet_height)
    print(spritesheet_width)

    # Tạo một hình ảnh mới cho spritesheet
    spritesheet = Image.new("RGBA", (int(spritesheet_width), int(spritesheet_height)))

    # Duyệt qua từng frame và đặt chúng lên spritesheet
    for current_frame in frames:
        top = tile_height * math.floor((frames.index(current_frame)) / max_frames_row)
        left = tile_width * (frames.index(current_frame) % max_frames_row)
        bottom = top + tile_height
        right = left + tile_width
    
        box = (left, top, right, bottom)
        box = [int(i) for i in box]
        cut_frame = current_frame.crop((0, 0, tile_width, tile_height))
    
        spritesheet.paste(cut_frame, box)
    
    # Tạo thư mục nếu chưa tồn tại
    os.makedirs("staging/target/rp/font", exist_ok=True)
    
    # Lưu spritesheet với tên dựa trên glyph
    spritesheet.save(f"staging/target/rp/font/glyph_{glyph}.png", "PNG")
