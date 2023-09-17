import os
import json
import shutil
import glob
from jproperties import Properties

# Khởi tạo đối tượng Properties từ thư viện jproperties
optifine = Properties()

# Biến đếm
i = 0

# Loại của các món đồ (hình ảnh đầu trang)
item_type = ["leather_helmet", "leather_chestplate", "leather_leggings", "leather_boots"]

# Hàm để tạo tệp JSON cho vật phẩm áo giáp
def write_armor(file, gmdl, layer, i):
    if i == 0:
        type = "helmet"
    elif i == 1:
        type = "chestplate"
    elif i == 2:
        type = "leggings"
    elif i == 3:
        type = "boots"
    
    # Dữ liệu JSON cho vật phẩm áo giáp
    ajson = {
        "format_version": "1.10.0",
        "minecraft:attachable": {
            "description": {
                "identifier": f"geyser_custom:{gmdl}.player",
                "item": { f"geyser_custom:{gmdl}": "query.owner_identifier == 'minecraft:player'" },
                "materials": {
                    "default": "armor_leather",
                    "enchanted": "armor_leather_enchanted"
                },
                "textures": {
                    "default": f"textures/armor_layer/{layer}",
                    "enchanted": "textures/misc/enchanted_item_glint"
                },
                "geometry": {
                    "default": f"geometry.player.armor.{type}"
                },
                "scripts": {
                    "parent_setup": "variable.helmet_layer_visible = 0.0;"
                },
                "render_controllers": ["controller.render.armor"]
            }
        }
    }
    
    # Ghi dữ liệu JSON vào tệp
    with open(file, "w") as f:
        f.write(json.dumps(ajson))

# Lặp qua các loại áo giáp
while i < 4:
    # Đọc tệp JSON cho loại áo giáp hiện tại
    with open(f"pack/assets/minecraft/models/item/{item_type[i]}.json", "r") as f:
        data = json.load(f)
    
    # Lặp qua các lựa chọn cho áo giáp
    for override in data["overrides"]:
        custom_model_data = override["predicate"]["custom_model_data"]
        model = override["model"]
        namespace = model.split(":")[0]
        item = model.split("/")[-1]
        
        # Kiểm tra nếu vật phẩm này là một loại áo giáp thì bỏ qua
        if item in item_type:
            continue
        else:
            path = model.split(":")[1]
            optifine_file = f"{namespace}_{item}"
            
            # Đọc tệp thuộc tính OptiFine
            with open(f"pack/assets/minecraft/optifine/cit/ia_generated_armors/{optifine_file}.properties", "rb") as f:
                optifine.load(f)
                
                # Xác định lớp áo giáp (layer)
                if i == 2:
                    layer = optifine.get("texture.leather_layer_2").data.split(".")[0]
                else:
                    layer = optifine.get("texture.leather_layer_1").data.split(".")[0]
            
            # Tạo thư mục nếu chưa tồn tại để lưu hình ảnh áo giáp
            if not os.path.exists("staging/target/rp/textures/armor_layer"):
                os.mkdir("staging/target/rp/textures/armor_layer")
            
            # Sao chép hình ảnh layer vào thư mục tương ứng
            if not os.path.exists(f"staging/target/rp/textures/armor_layer/{layer}.png"):
                shutil.copy(f"pack/assets/minecraft/optifine/cit/ia_generated_armors/{layer}.png", "staging/target/rp/textures/armor_layer")
            
            # Đọc tệp JSON của mô hình vật phẩm
            with open(f"pack/assets/{namespace}/models/{path}.json", "r") as f:
                texture = json.load(f)["textures"]["layer1"]
                tpath = texture.split(":")[1]
                
                # Sao chép hình ảnh texture của vật phẩm vào thư mục tương ứng
                shutil.copy(f"pack/assets/{namespace}/textures/{tpath}.png", f"staging/target/rp/textures/{namespace}/{path}.png")
            
            # Tìm tệp mô hình attachable
            afile = glob.glob(f"staging/target/rp/attachables/{namespace}/{path}*.json")
            
            # Đọc tệp mô hình attachable
            with open(afile[0], "r") as f:
                da = json.load(f)["minecraft:attachable"]
                gmdl = da["description"]["identifier"].split(":")[1]
            
            # Tạo tệp JSON cho áo giáp
            pfile = afile[0].replace(".json", ".player.json")
            write_armor(pfile, gmdl, layer, i)
    
    # Tăng biến đếm
    i += 1
