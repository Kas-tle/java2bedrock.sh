import os
import json
import shutil
import glob
from jproperties import Properties

optifine = Properties()
i = 0
item_type = ["leather_helmet", "leather_chestplate", "leather_leggings", "leather_boots"]

def write_armor(file, gmdl, layer, i):
	if i == 0:
		type = "helmet"
	elif i == 1:
		type = "chestplate"
	elif i == 2:
		type = "leggings"
	elif i == 3:
		type = "boots"
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
	with open(file, "w") as f:
		f.write(json.dumps(ajson))

while i < 4:
	with open(f"pack/assets/minecraft/models/item/{item_type[i]}.json", "r") as f:
		data = json.load(f)
	for override in data["overrides"]:
		custom_model_data = override["predicate"]["custom_model_data"]
		model = override["model"]
		namespace = model.split(":")[0]
		item = model.split("/")[-1]
		if item in item_type:
			continue
		else:
			path = model.split(":")[1]
			optifine_file = f"{namespace}_{item}"
			with open(f"pack/assets/minecraft/optifine/cit/ia_generated_armors/{optifine_file}.properties", "rb") as f:
				optifine.load(f)
				if i == 2:
					layer = optifine.get("texture.leather_layer_2").data.split(".")[0]
				else:
					layer = optifine.get("texture.leather_layer_1").data.split(".")[0]
			if not os.path.exists("staging/target/rp/textures/armor_layer"):
				os.mkdir("staging/target/rp/textures/armor_layer")
			if not os.path.exists(f"staging/target/rp/textures/armor_layer/{layer}.png"):
				shutil.copy(f"pack/assets/minecraft/optifine/cit/ia_generated_armors/{layer}.png", "staging/target/rp/textures/armor_layer")
			with open(f"pack/assets/{namespace}/models/{path}.json", "r") as f :
				texture = json.load(f)["textures"]["layer1"]
				tpath = texture.split(":")[1]
				shutil.copy(f"pack/assets/{namespace}/textures/{tpath}.png", f"staging/target/rp/textures/{namespace}/{path}.png")
			afile = glob.glob(f"staging/target/rp/attachables/{namespace}/{path}*.json")
			with open(afile[0], "r") as f:
				da = json.load(f)["minecraft:attachable"]
				gmdl = da["description"]["identifier"].split(":")[1]
			pfile = afile[0].replace(".json", ".player.json")
			write_armor(pfile, gmdl, layer, i)
	i += 1
