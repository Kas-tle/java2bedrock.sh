#!/usr/bin/env bash
: ${1?'Please specify an input resource pack in the same directory as the script (e.g. ./converter.sh MyResourcePack.zip)'}

# define color placeholders
C_RED='\e[31m'
C_GREEN='\e[32m'
C_YELLOW='\e[33m'
C_BLUE='\e[36m'
C_GRAY='\e[37m'
C_CLOSE='\e[m'

# status message function
status_message () {
  case $1 in
    "completion")
      printf "${C_GREEN}[+] ${C_GRAY}${2}${C_CLOSE}\n"
      ;;
    "process")
      printf "${C_YELLOW}[•] ${C_GRAY}${2}${C_CLOSE}\n"
      ;;
    "critical")
      printf "${C_RED}[X] ${C_GRAY}${2}${C_CLOSE}\n"
      ;;
    "error")
      printf "${C_RED}[ERROR] ${C_GRAY}${2}${C_CLOSE}\n"
      ;;
    "info")
      printf "${C_BLUE}${2}${C_CLOSE}\n"
      ;;
    "plain")
      printf "${C_GRAY}${2}${C_CLOSE}\n"
      ;;
  esac
}

dependency_check () {
  if command ${3} 2>/dev/null | grep -q "${4}"; then
      status_message completion "Dependency ${1} satisfied"
  else
      status_message error "Dependency ${1} must be installed to proceed\nSee ${2}\nExiting script..."
      exit 1
  fi
}

user_input () {
  status_message plain "${2} ${C_YELLOW}[${3}]\n"
  read -p "${4}: " ${1}
  echo
}

# ensure input pack exists
if ! test -f "${1}"; then
   status_message error "Input resource pack ${1} is not in this directory"
   exit 1
else
  status_message process "Input file ${1} detected"
fi

printf '\e[1;31m%-6s\e[m\n' "
███████████████████████████████████████████████████████████████████████████████
████████████████████████ # <!> # W A R N I N G # <!> # ████████████████████████
███████████████████████████████████████████████████████████████████████████████
███ This script has been provided as is. If your resource pack does not     ███
███ entirely conform the vanilla resource specification, including but not  ███
███ limited to, missing textures, improper parenting, improperly defined    ███
███ predicates, and malformed JSON files, among other problems, there is a  ███
███ strong possibility this script will fail. Please remedy any potential   ███
███ resource pack formatting errors before attempting to make use of this   ███
███ converter. You have been warned.                                        ███
███████████████████████████████████████████████████████████████████████████████
███████████████████████████████████████████████████████████████████████████████
███████████████████████████████████████████████████████████████████████████████
"

read -p $'\e[37mTo acknowledge and continue, press enter. To exit, press Ctrl+C.:\e[0m

'

# ensure we have all the required dependencies
dependency_check "jq-1.6" "https://stedolan.github.io/jq/download/" "jq --version" "1.6"
dependency_check "sponge" "https://joeyh.name/code/moreutils/" "-v sponge" ""
dependency_check "imagemagick-7" "https://imagemagick.org/script/download.php" "magick --version" "ImageMagick 7."
dependency_check "spritesheet-js" "https://www.npmjs.com/package/spritesheet-js" "-v spritesheet-js" ""
status_message completion "All dependencies have been satisfied\n"

# initial configuration
if [[ ${2} != default ]]
then
  status_message info "This script will now ask some configuration questions. Default values are yellow. Simply press enter to use the defaults.\n"
  user_input merge_input "Is there an existing bedrock pack in this directory with which you would like the output merged? (e.g. input.mcpack)" "null" "Input pack to merge"
  user_input attachable_material "What material should we use for the attachables?" "entity_alphatest" "Attachable material"
  user_input block_material "What material should we use for the blocks?" "alpha_test" "Block material"
  user_input fallback_pack "From what URL should we download the fallback resource pack? (must be a direct link)\n Use 'none' if default resources are not needed." "null" "Fallback pack URL"
fi

status_message plain "
Generating Bedrock 3D resource pack with settings:
${C_GRAY}Input pack to merge: ${C_BLUE}${merge_input:=null}
${C_GRAY}Attachable material: ${C_BLUE}${attachable_material:=entity_alphatest}
${C_GRAY}Block material: ${C_BLUE}${block_material:=alpha_test}
${C_GRAY}Fallback pack URL: ${C_BLUE}${fallback_pack:=null}
"

# decompress our input pack
status_message process "Decompressing input pack"
unzip -q ${1}
status_message completion "Input pack decompressed"

# get the current default textures and merge them with our rp
if [[ ${fallback_pack} != none ]]
then
   status_message process "Now downloading the fallback resource pack:"
fi

if [[ ${fallback_pack} = null ]]
then
  printf "\e[3m\e[37m"
  wget -nv --show-progress -O default_assets.zip https://github.com/InventivetalentDev/minecraft-assets/zipball/refs/tags/1.18.2
  printf "${C_CLOSE}"
  status_message completion "Fallback resources downloaded"
  root_folder=($(unzip -Z -1 default_assets.zip | head -1))
fi

if [[ ${fallback_pack} != null &&  ${fallback_pack} != none ]]
then
  printf "\e[3m\e[37m"
  wget -nv --show-progress -O default_assets.zip "${fallback_pack}"
  status_message completion "Fallback resources downloaded"
  root_folder=""
fi

if [[ ${fallback_pack} != none ]]
then
  mkdir ./defaultassetholding
  unzip -q -d ./defaultassetholding default_assets.zip "${root_folder}assets/minecraft/textures/**/*"
  status_message completion "Fallback resources decompressed"
  cp -n -r "./defaultassetholding/${root_folder}assets/minecraft/textures"/* './assets/minecraft/textures/'
  status_message completion "Fallback resources merged with target pack"
  rm -rf defaultassetholding
  rm -f default_assets.zip
  status_message critical "Extraneous fallback resources deleted\n"
fi

# generate a fallback texture
convert -size 16x16 xc:\#FFFFFF ./assets/minecraft/textures/0.png

# setup our initial config
status_message process "Iterating through all vanilla associated model JSONs to generate initial predicate config\nOn a large pack, this may take some time...\n"

if test -d "./assets/minecraft/models/item"; then confarg1="./assets/minecraft/models/item/*.json"; fi
if test -d "./assets/minecraft/models/block"; then confarg2="./assets/minecraft/models/block/*.json"; fi


jq -n '[inputs | {(input_filename | sub("(.+)/(?<itemname>.*?).json"; .itemname)): .overrides?[]?}] |

def maxdur($input):
({
  "carrot_on_a_stick": 25,
  "golden_axe": 32,
  "golden_hoe": 32,
  "golden_pickaxe": 32,
  "golden_shovel": 32,
  "golden_sword": 32,
  "wooden_axe": 59,
  "wooden_hoe": 59,
  "wooden_pickaxe":59,
  "wooden_shovel":59,
  "wooden_sword": 59,
  "fishing_rod": 64,
  "flint_and_steel": 64,
  "warped_fungus_on_a_stick": 100,
  "sparkler": 100,
  "glow_stick": 100,
  "stone_axe": 131,
  "stone_hoe": 131,
  "stone_pickaxe":131,
  "stone_shovel":131,
  "stone_sword": 131,
  "shears": 238,
  "iron_axe": 250,
  "iron_hoe": 250,
  "iron_pickaxe": 250,
  "iron_shovel": 250,
  "iron_sword": 250,
  "trident": 250,
  "crossbow": 326,
  "shield": 336,
  "bow": 384,
  "elytra": 432,
  "diamond_axe": 1561,
  "diamond_hoe": 1561,
  "diamond_pickaxe": 1561,
  "diamond_shovel": 1561,
  "diamond_sword": 1561,
  "netherite_axe": 2031,
  "netherite_hoe": 2031,
  "netherite_pickaxe": 2031,
  "netherite_shovel": 2031,
  "netherite_sword": 2031
} | .[$input] // 1)
;

def namespace:
if contains(":") then sub("\\:(.+)"; "") else "minecraft" end
;

[.[] | to_entries | map( select((.value.predicate.damage != null) or (.value.predicate.damaged != null)  or (.value.predicate.custom_model_data != null)) |
      (if .value.predicate.damage then (.value.predicate.damage * maxdur(.key) | round) else null end) as $damage
    | (if .value.predicate.damaged == 0 then 1 else null end) as $unbreakable
    | (if .value.predicate.custom_model_data then .value.predicate.custom_model_data else null end) as $custom_model_data |
  {
    "item": .key,
      "nbt": ({
        "Damage": $damage,
        "Unbreakable": $unbreakable,
        "CustomModelData": $custom_model_data
      }),
    "path": ("./assets/" + (.value.model | namespace) + "/models/" + (.value.model | sub("(.*?)\\:"; "")) + ".json")

}) | .[]]
| walk(if type == "object" then with_entries(select(.value != null)) else . end)
| to_entries | map( ((.value.geyserID = "gmdl_\(1+.key)" | .value.geometry = ("geometry.geysercmd." + "gmdl_\(1+.key)")) | .value))
| INDEX(.geyserID)

' ${confarg1} ${confarg2} | sponge config.json
status_message completion "Initial predicate config generated"

# get a bash array of all model json files in our resource pack
status_message process "Generating an array of all model JSON files to crosscheck with our predicate config"
json_dir=($(find ./assets/**/models -type f -name '*.json'))

# ensure all our reference files in config.json exist, and delete the entry if they do not
status_message critical "Removing config entries that do not have an associated JSON file in the pack"
jq '

def real_file($input):
($ARGS.positional | index($input) // null);

map_values(if real_file(.path) != null then . else empty end)

' config.json --args ${json_dir[@]} | sponge config.json

# get a bash array of all our input models
status_message process "Creating a bash array for remaing models in our predicate config"
model_array=($(jq -r '.[].path' config.json))

# find initial parental information
status_message process "Doing an initial sweep for level 1 parentals"
jq -n '

[def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end;

inputs | {
  "path": (input_filename),
  "parent": ("./assets/" + (.parent | namespace) + "/models/" + ((.parent? // empty) | sub("(.*?)\\:"; "")) + ".json")
  }
]

' ${model_array[@]} | sponge parents.json

# add initial parental information to config.json
status_message critical "Removing config entries with non-supported parentals\n"
jq -s '

. as $global |

def intest($input_i): ($global | .[0] | map({(.path): .parent}) | add | .[$input_i]? // null);

def gtest($input_g):
["./assets/minecraft/models/block/block.json", "./assets/minecraft/models/block/cube.json", "./assets/minecraft/models/block/cube_column.json", "./assets/minecraft/models/block/cube_directional.json", "./assets/minecraft/models/block/cube_mirrored.json", "./assets/minecraft/models/block/observer.json", "./assets/minecraft/models/block/orientable_with_bottom.json", "./assets/minecraft/models/block/piston_extended.json", "./assets/minecraft/models/block/redstone_dust_side.json", "./assets/minecraft/models/block/redstone_dust_side_alt.json", "./assets/minecraft/models/block/template_single_face.json", "./assets/minecraft/models/block/thin_block.json", "./assets/minecraft/models/builtin/entity.json", "./assets/minecraft/models/builtin/generated.json", "./assets/minecraft/models/item/bow.json", "./assets/minecraft/models/item/chest.json", "./assets/minecraft/models/item/crossbow.json", "./assets/minecraft/models/item/fishing_rod.json", "./assets/minecraft/models/item/generated.json", "./assets/minecraft/models/item/handheld.json", "./assets/minecraft/models/item/handheld_rod.json", "./assets/minecraft/models/item/template_skull.json"]
| index($input_g) // null;

.[1] | map_values(. + ({"parent": (intest(.path) // null)} | if gtest(.parent) == null then . else empty end))
| walk(if type == "object" then with_entries(select(.value != null)) else . end)

' parents.json config.json | sponge config.json


# create our initial directories for bp & rp
status_message process "Generating initial directory strucutre for our bedrock packs"
mkdir -p ./target/rp/models/blocks/geysercmd && mkdir -p ./target/rp/textures/blocks/geysercmd && mkdir -p ./target/rp/attachables/geysercmd && mkdir -p ./target/rp/animations/geysercmd && mkdir -p ./target/bp/blocks/geysercmd

# copy over our pack.png if we have one
if test -f "./pack.png"; then
    cp ./pack.png ./target/rp/pack_icon.png && cp ./pack.png ./target/bp/pack_icon.png
fi

# generate uuids for our manifests
uuid1=($(uuidgen))
uuid2=($(uuidgen))
uuid3=($(uuidgen))
uuid4=($(uuidgen))

# get pack description if we have one
pack_desc=($(jq -r '(.pack.description // "Geyser 3D Items Resource Pack")' ./pack.mcmeta))

# generate rp manifest.json
status_message process "Generating resource pack manifest"
jq -c --arg pack_desc "${pack_desc}" --arg uuid1 "${uuid1}" --arg uuid2 "${uuid2}" -n '
{
    "format_version": 2,
    "header": {
        "description": "Adds 3D items for use with a Geyser proxy",
        "name": $pack_desc,
        "uuid": ($uuid1 | ascii_downcase),
        "version": [1, 0, 0],
        "min_engine_version": [1, 16, 100]
    },
    "modules": [
        {
            "description": "Adds 3D items for use with a Geyser proxy",
            "type": "resources",
            "uuid": ($uuid2 | ascii_downcase),
            "version": [1, 0, 0]
        }
    ]
}
' | sponge ./target/rp/manifest.json

# generate bp manifest.json
status_message process "Generating behavior pack manifest"
jq -c --arg pack_desc "${pack_desc}" --arg uuid1 "${uuid1}" --arg uuid3 "${uuid3}" --arg uuid4 "${uuid4}" -n '
{
    "format_version": 2,
    "header": {
        "description": "Adds 3D items for use with a Geyser proxy",
        "name": $pack_desc,
        "uuid": ($uuid3 | ascii_downcase),
        "version": [1, 0, 0],
        "min_engine_version": [ 1, 16, 100]
    },
    "modules": [
        {
            "description": "Adds 3D items for use with a Geyser proxy",
            "type": "data",
            "uuid": ($uuid4 | ascii_downcase),
            "version": [1, 0, 0]
        }
    ],
    "dependencies": [
        {
            "uuid": ($uuid1 | ascii_downcase),
            "version": [1, 0, 0]
        }
    ]
}
' | sponge ./target/bp/manifest.json

# generate rp terrain_texture.json
status_message process "Generating resource pack terrain texture definition"
jq -nc '
{
  "resource_pack_name": "vanilla",
  "texture_name": "atlas.terrain",
  "padding": 8,
  "num_mip_levels": 4,
  "texture_data": {
    "gmdl_atlas": {
      "textures": "textures/blocks/geysercmd/gmdl_atlas"
      }
  }
}
' | sponge ./target/rp/textures/terrain_texture.json

status_message process "Generating resource pack disabling animation"
# generate our disabling animation
jq -nc '
{
  "format_version": "1.8.0",
  "animations": {
    "animation.geysercmd.disable": {
      "loop": true,
      "override_previous_animation": true,
      "bones": {
        "geysercmd": {
          "scale": 0
        }
      }
    }
  }
}
' | sponge ./target/rp/animations/geysercmd/animation.geysercmd.disable.json
status_message completion "Initial pack setup complete\n"

jq -r '.[] | select(.parent != null) | [.path, .geyserID, .parent] | @tsv | gsub("\\t";",")' config.json | sponge pa.csv

_start=1
_end="$(jq -r '(. | length) + ([.[] | select(.parent != null)] | length)' config.json)"
cur_pos=0

function ProgressBar {
    let _progress=(${1}*100/${2}*100)/100
    let _done=(${_progress}*6)/10
    let _left=60-$_done
    _fill=$(printf "%${_done}s")
    _empty=$(printf "%${_left}s")
printf "\r\e[37m█\e[m \e[37m${_fill// /█}\e[m\e[37m${_empty// /•}\e[m \e[37m█\e[m \e[33m${_progress}％\e[m\n"
}

# first, deal with parented models
while IFS=, read -r file gid parental
do
  cur_pos=$((cur_pos+1))
  elements="$(jq -rc '.elements' ${file} | tee elements.temp)"
  element_parent=${file}
  textures="$(jq -rc '.textures' ${file} | tee textures.temp)"
  display="$(jq -rc '.display' ${file} | tee display.temp)"
  status_message process "Locating parental info for child model with GeyserID ${gid}"

  # itterate through parented models until they all have geometry, display, and textures
  until [[ ${elements} != null && ${textures} != null && ${display} != null ]] || [[ ${parental} = null ]]
  do
    if [[ ${elements} = null ]]
    then
      elements="$(jq -rc '.elements' ${parental} 2> /dev/null | tee elements.temp || echo && echo null)"
      element_parent=${parental}
    fi
    if [[ ${textures} = null ]]
    then
      textures="$(jq -rc '.textures' ${parental} 2> /dev/null | tee textures.temp || echo && echo null)"
    fi
    if [[ ${display} = null ]]
    then
      display="$(jq -rc '.display' ${parental} 2> /dev/null | tee display.temp || echo && echo null)"
    fi
    parental="$(jq -rc 'def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end; ("./assets/" + (.parent | namespace) + "/models/" + ((.parent? // empty) | sub("(.*?)\\:"; "")) + ".json") // "null"' ${parental} 2> /dev/null || echo && echo null)"
  done

  # if we can, generate a model now
  if [[ ${elements} != null && ${textures} != null ]]
  then
    jq -n --slurpfile jelements elements.temp --slurpfile jtextures textures.temp --slurpfile jdisplay display.temp '
    {
      "textures": ($jtextures[]),
      "elements": ($jelements[])
    } + (if $jdisplay then ({"display": ($jdisplay[])}) else {} end)
    ' | sponge ${file}
    status_message completion "Located all parental info for Child ${gid}"
    ProgressBar ${cur_pos} ${_end}
    echo
  # otherwise, remove it from our config
  else
    status_message plain "Suitable parent information was not availbile for ${gid}..."
    status_message critical "Deleting ${gid} from config"
    ProgressBar ${cur_pos} ${_end}
    echo
    jq --arg gid "${gid}" 'del(.[$gid])' config.json | sponge config.json
  fi

done < pa.csv

# make sure we crop all mcmeta associated png files
status_message process "Cropping animated textures"
for i in $(find ./assets/**/textures -type f -name "*.mcmeta" | sed 's/\.mcmeta//'); do magick ${i} -background none -gravity North -extent "%[fx:h<w?h:w]x%[fx:h<w?h:w]" ${i}; done

status_message process "Compiling final model list"
# get our final model list from the config
model_list=( $(jq -r '.[].path' config.json) )

# get our final texture list
# get a bash array of all texture files in our resource pack
status_message process "Generating an array of all model PNG files to crosscheck with our atlas"
jq -n '$ARGS.positional' --args $(find ./assets/**/textures -type f -name '*.png') | sponge textures1.temp
status_message process "Generating an array for the master texture atlas"
jq -s 'def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end; [.[].textures[]] | unique | map("./assets/" + (. | namespace) + "/textures/" + (. | sub("(.*?)\\:"; "")) + ".png")' ${model_list[@]} | sponge textures2.temp
texture_list=( $(jq -s -r '((.[1] - (.[1] - .[0])) + ["./assets/minecraft/textures/0.png"]) | .[]' textures1.temp textures2.temp) )

# generate our atlas from the final texture list
status_message process "Generating sprite sheet"
spritesheet-js -f json --fullpath  ${texture_list[@]} > /dev/null 2>&1
status_message completion "Sprite sheet successfully generated"
mv spritesheet.png ./target/rp/textures/blocks/geysercmd/gmdl_atlas.png

# begin conversion
jq -r '.[] | [.path, .geyserID] | @tsv | gsub("\\t";",")' config.json | sponge all.csv

while IFS=, read -r file gid
do
   convert_model () {
    local file=${1}
    local gid=${2}

    status_message process "Starting conversion of model with GeyserID ${gid}"

    jq --slurpfile atlas spritesheet.json --arg binding "c.item_slot == 'head' ? 'head' : q.item_slot_to_bone_name(c.item_slot)" --arg model_name "${gid}" -c '
    .textures as $texture_list |

    def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end;

    def totexture($input): ($texture_list[($input[1:])]? // ([$texture_list[]][0]));

    def topath($input): ("./assets/" + ($input | namespace) + "/textures/" + ($input | sub("(.*?)\\:"; "")) + ".png");

    def texturedata($input): $atlas[] | .frames | (.[topath(totexture($input))] // ."./assets/minecraft/textures/0.png");

    def roundit: (.*10000 | round) / 10000;

    def element_array:
        .elements | map({
        "origin": [((-.to[0] + 8) | roundit), ((.from[1]) | roundit), ((.from[2] - 8) | roundit)],
        "size": [((.to[0] - .from[0]) | roundit), ((.to[1] - .from[1]) | roundit), ((.to[2] - .from[2]) | roundit)],
        "rotation": (if (.rotation.axis) == "x" then [(.rotation.angle | tonumber * -1), 0, 0] elif (.rotation.axis) == "y" then [0, (.rotation.angle | tonumber * -1), 0] elif (.rotation.axis) == "z" then [0, 0, (.rotation.angle | tonumber)] else null end),
        "pivot": (if .rotation.origin then [((- .rotation.origin[0] + 8) | roundit), (.rotation.origin[1] | roundit), ((.rotation.origin[2] - 8) | roundit)] else null end),
        "uv": (
          def uv_calc($input):
            (if (.faces | .[$input]) then
            (.faces | .[$input].texture) as $input_n
            | ( (((((.faces | .[$input].uv[0]) * (texturedata($input_n) | .frame.w) * 0.0625) + (texturedata($input_n) | .frame.x)) * (16 / ($atlas[] | .meta.size.w))) ) ) as $fn0
            | ( (((((.faces | .[$input].uv[1]) * (texturedata($input_n) | .frame.h) * 0.0625) + (texturedata($input_n) | .frame.y)) * (16 / ($atlas[] | .meta.size.h))) ) ) as $fn1
            | ( (((((.faces | .[$input].uv[2]) * (texturedata($input_n) | .frame.w) * 0.0625) + (texturedata($input_n) | .frame.x)) * (16 / ($atlas[] | .meta.size.w))) ) ) as $fn2
            | ( (((((.faces | .[$input].uv[3]) * (texturedata($input_n) | .frame.h) * 0.0625) + (texturedata($input_n) | .frame.y)) * (16 / ($atlas[] | .meta.size.h))) ) ) as $fn3 
            | (($fn2 - $fn0) as $num | [([-1, $num] | max), 1] | min) as $x_sign
            | (($fn3 - $fn1) as $num | [([-1, $num] | max), 1] | min) as $y_sign |
            {
              "uv": [(($fn0 + (0.016 * $x_sign)) | roundit), (($fn1 + (0.016 * $y_sign)) | roundit)],
              "uv_size": [((($fn2 - $fn0) - (0.016 * $x_sign)) | roundit), ((($fn3 - $fn1) - (0.016 * $y_sign)) | roundit)]
            } else null end);
          {
          "north": uv_calc("north"),
          "south": uv_calc("south"),
          "east": uv_calc("east"),
          "west": uv_calc("west"),
          "up": uv_calc("up"),
          "down": uv_calc("down")
          })
      }) | walk( if type == "object" then with_entries(select(.value != null)) else . end)
      ;

      def pivot_groups:
      (element_array) as $element_array |
      [[.elements[].rotation] | unique | .[] | select (.!=null)]
      | map((
      [((- .origin[0] + 8) | roundit), (.origin[1] | roundit), ((.origin[2] - 8) | roundit)] as $i_piv |
      (if (.axis) == "x" then [(.angle | tonumber * -1), 0, 0] elif (.axis) == "y" then [0, (.angle | tonumber * -1), 0] else [0, 0, (.angle | tonumber)] end) as $i_rot |
      {
        "parent": "geysercmd_z",
        "pivot": ($i_piv),
        "rotation": ($i_rot),
        "mirror": true,
        "cubes": [($element_array | .[] | select(.rotation == $i_rot and .pivot == $i_piv))]
      }))
      ;

      {
        "format_version": "1.16.0",
        "minecraft:geometry": [{
          "description": {
            "identifier": ("geometry.geysercmd." + ($model_name)),
            "texture_width": 16,
            "texture_height": 16,
            "visible_bounds_width": 4,
            "visible_bounds_height": 4.5,
            "visible_bounds_offset": [0, 0.75, 0]
          },
          "bones": ([{
            "name": "geysercmd",
            "binding": $binding,
            "pivot": [0, 8, 0]
          }, {
            "name": "geysercmd_x",
            "parent": "geysercmd",
            "pivot": [0, 8, 0]
          }, {
            "name": "geysercmd_y",
            "parent": "geysercmd_x",
            "pivot": [0, 8, 0]
          }, {
            "name": "geysercmd_z",
            "parent": "geysercmd_y",
            "pivot": [0, 8, 0],
            "cubes": [(element_array | .[] | select(.rotation == null))]
          }] + (pivot_groups | map(del(.cubes[].rotation)) | to_entries | map( (.value.name = "rot_\(1+.key)" ) | .value)))
        }]
      }

      ' ${file} | sponge ./target/rp/models/blocks/geysercmd/${gid}.json

      # generate our rp animations via display settings
      jq -c --arg model_name "${gid}" '

      {
        "format_version": "1.8.0",
        "animations": {
          ("animation.geysercmd." + ($model_name) + ".thirdperson_main_hand"): {
            "loop": true,
            "bones": {
              "geysercmd_x": (if .display.thirdperson_righthand then {
                "rotation": (if .display.thirdperson_righthand.rotation then [(- .display.thirdperson_righthand.rotation[0]), 0, 0] else null end),
                "position": (if .display.thirdperson_righthand.translation then [(- .display.thirdperson_righthand.translation[0]), (.display.thirdperson_righthand.translation[1]), (.display.thirdperson_righthand.translation[2])] else null end),
                "scale": (if .display.thirdperson_righthand.scale then [(.display.thirdperson_righthand.scale[0]), (.display.thirdperson_righthand.scale[1]), (.display.thirdperson_righthand.scale[2])] else null end)
              } else null end),
              "geysercmd_y": (if .display.thirdperson_righthand.rotation then {
                "rotation": (if .display.thirdperson_righthand.rotation then [0, (- .display.thirdperson_righthand.rotation[1]), 0] else null end)
              } else null end),
              "geysercmd_z": (if .display.thirdperson_righthand.rotation then {
                "rotation": [0, 0, (.display.thirdperson_righthand.rotation[2])]
              } else null end),
              "geysercmd": {
                "rotation": [90, 0, 0],
                "position": [0, 13, -3]
              }
            }
          },
          ("animation.geysercmd." + ($model_name) + ".thirdperson_off_hand"): {
            "loop": true,
            "bones": {
              "geysercmd_x": (if .display.thirdperson_lefthand then {
                "rotation": (if .display.thirdperson_lefthand.rotation then [(- .display.thirdperson_lefthand.rotation[0]), 0, 0] else null end),
                "position": (if .display.thirdperson_lefthand.translation then [(- .display.thirdperson_lefthand.translation[0]), (.display.thirdperson_lefthand.translation[1]), (.display.thirdperson_lefthand.translation[2])] else null end),
                "scale": (if .display.thirdperson_lefthand.scale then [(.display.thirdperson_lefthand.scale[0]), (.display.thirdperson_lefthand.scale[1]), (.display.thirdperson_lefthand.scale[2])] else null end)
              } else null end),
              "geysercmd_y": (if .display.thirdperson_lefthand.rotation then {
                "rotation": (if .display.thirdperson_lefthand.rotation then [0, (- .display.thirdperson_lefthand.rotation[1]), 0] else null end)
              } else null end),
              "geysercmd_z": (if .display.thirdperson_lefthand.rotation then {
                "rotation": [0, 0, (.display.thirdperson_lefthand.rotation[2])]
              } else null end),
              "geysercmd": {
                "rotation": [90, 0, 0],
                "position": [0, 13, -3]
              }
            }
          },
          ("animation.geysercmd." + ($model_name) + ".head"): {
            "loop": true,
            "bones": {
              "geysercmd_x": {
                "rotation": (if .display.head.rotation then [(- .display.head.rotation[0]), 0, 0] else null end),
                "position": (if .display.head.translation then [(- .display.head.translation[0] * 0.625), (.display.head.translation[1] * 0.625), (.display.head.translation[2] * 0.625)] else null end),
                "scale": (if .display.head.scale then (.display.head.scale | map(. * 0.625)) else 0.625 end)
              },
              "geysercmd_y": (if .display.head.rotation then {
                "rotation": [0, (- .display.head.rotation[1]), 0]
              } else null end),
              "geysercmd_z": (if .display.head.rotation then {
                "rotation": [0, 0, (.display.head.rotation[2])]
              } else null end),
              "geysercmd": {
                "position": [0, 19.5, 0]
              }
            }
          },
          ("animation.geysercmd." + ($model_name) + ".firstperson_main_hand"): {
            "loop": true,
            "bones": {
              "geysercmd": {
                "rotation": [90, 60, -40],
                "position": [4, 10, 4],
                "scale": 1.5
              },
              "geysercmd_x": {
                "position": (if .display.firstperson_righthand.translation then [(- .display.firstperson_righthand.translation[0]), (.display.firstperson_righthand.translation[1]), (- .display.firstperson_righthand.translation[2])] else null end),
                "rotation": (if .display.firstperson_righthand.rotation then [(- .display.firstperson_righthand.rotation[0]), 0, 0] else [0.1, 0.1, 0.1] end),
                "scale": (if .display.firstperson_righthand.scale then (.display.firstperson_righthand.scale) else null end)
              },
              "geysercmd_y": (if .display.firstperson_righthand.rotation then {
                "rotation": [0, (- .display.firstperson_righthand.rotation[1]), 0]
              } else null end),
              "geysercmd_z": (if .display.firstperson_righthand.rotation then {
                "rotation": [0, 0, (.display.firstperson_righthand.rotation[2])]
              } else null end)
            }
          },
          ("animation.geysercmd." + ($model_name) + ".firstperson_off_hand"): {
            "loop": true,
            "bones": {
              "geysercmd": {
                "rotation": [90, 60, -40],
                "position": [4, 10, 4],
                "scale": 1.5
              },
              "geysercmd_x": {
                "position": (if .display.firstperson_lefthand.translation then [(.display.firstperson_lefthand.translation[0]), (.display.firstperson_lefthand.translation[1]), (- .display.firstperson_lefthand.translation[2])] else null end),
                "rotation": (if .display.firstperson_lefthand.rotation then [(- .display.firstperson_lefthand.rotation[0]), 0, 0] else [0.1, 0.1, 0.1] end),
                "scale": (if .display.firstperson_lefthand.scale then (.display.firstperson_lefthand.scale) else null end)
              },
              "geysercmd_y": (if .display.firstperson_lefthand.rotation then {
                "rotation": [0, (- .display.firstperson_lefthand.rotation[1]), 0]
              } else null end),
              "geysercmd_z": (if .display.firstperson_lefthand.rotation then {
                "rotation": [0, 0, (.display.firstperson_lefthand.rotation[2])]
              } else null end)
            }
          }
        }
      } | walk( if type == "object" then with_entries(select(.value != null)) else . end)

      ' ${file} | sponge ./target/rp/animations/geysercmd/animation.${gid}.json

      # generate our rp attachable definition
      jq -c -n --arg attachable_material "${attachable_material}" --arg v_main "v.main_hand = c.item_slot == 'main_hand';" --arg v_off "v.off_hand = c.item_slot == 'off_hand';" --arg v_head "v.head = c.item_slot == 'head';" --arg model_name "${gid}" --arg texture_name "${texture_id}" '

      {
        "format_version": "1.10.0",
        "minecraft:attachable": {
          "description": {
            "identifier": ("geysercmd:" + $model_name),
            "materials": {
              "default": $attachable_material,
              "enchanted": $attachable_material
            },
            "textures": {
              "default": "textures/blocks/geysercmd/gmdl_atlas",
              "enchanted": "textures/misc/enchanted_item_glint"
            },
            "geometry": {
              "default": ("geometry.geysercmd." + $model_name)
            },
            "scripts": {
              "pre_animation": [$v_main, $v_off, $v_head],
              "animate": [
                {"thirdperson_main_hand": "v.main_hand && !c.is_first_person"},
                {"thirdperson_off_hand": "v.off_hand && !c.is_first_person"},
                {"thirdperson_head": "v.head && !c.is_first_person"},
                {"firstperson_main_hand": "v.main_hand && c.is_first_person"},
                {"firstperson_off_hand": "v.off_hand && c.is_first_person"},
                {"firstperson_head": "c.is_first_person && v.head"}
              ]
            },
            "animations": {
              "thirdperson_main_hand": ("animation.geysercmd." + $model_name + ".thirdperson_main_hand"),
              "thirdperson_off_hand": ("animation.geysercmd." + $model_name + ".thirdperson_off_hand"),
              "thirdperson_head": ("animation.geysercmd." + $model_name + ".head"),
              "firstperson_main_hand": ("animation.geysercmd." + $model_name + ".firstperson_main_hand"),
              "firstperson_off_hand": ("animation.geysercmd." + $model_name + ".firstperson_off_hand"),
              "firstperson_head": "animation.geysercmd.disable"
            },
            "render_controllers": [ "controller.render.item_default" ]
          }
        }
      }

      ' | sponge ./target/rp/attachables/geysercmd/${gid}.attachable.json

      # generate our bp block definition
      jq -c -n --arg block_material "${block_material}" --arg geyser_id "${gid}" '

      {
          "format_version": "1.16.200",
          "minecraft:block": {
              "description": {
                  "identifier": ("geysercmd:" + $geyser_id)
              },
              "components": {
                  "minecraft:material_instances": {
                      "*": {
                          "texture": "gmdl_atlas",
                          "render_method": $block_material,
                          "face_dimming": false,
                          "ambient_occlusion": false
                      }
                  },
                  "tag:geysercmd:example_block": {},
                  "minecraft:geometry": ("geometry.geysercmd." + $geyser_id),
                  "minecraft:placement_filter": {
                    "conditions": [
                        {
                            "allowed_faces": [
                            ],
                            "block_filter": [
                            ]
                        }
                    ]
                  }
              }
          }
      }

      ' | sponge ./target/bp/blocks/geysercmd/${gid}.json
      local tot_pos=$((cur_pos + $(ls ./target/bp/blocks/geysercmd/*.json | wc -l)))
      status_message completion "${gid} converted\n$(ProgressBar ${tot_pos} ${_end})"
      echo
   }
   convert_model ${file} ${gid} &

done < all.csv
wait # wait for all the jobs to finish

# write lang file US
status_message process "Writing en_US and en_GB lang files"
mkdir ./target/rp/texts
jq -r '

def format: (.[0:1] | ascii_upcase ) + (.[1:] | gsub( "_(?<a>[a-z])"; (" " + .a) | ascii_upcase));
to_entries[]|"\("tile.geysercmd:" + .key + ".name")=\(.value.item | format)"

' config.json | sponge ./target/rp/texts/en_US.lang

# copy US lang to GB
cp ./target/rp/texts/en_US.lang ./target/rp/texts/en_GB.lang

# write supported languages file
jq -n '["en_US","en_GB"]' | sponge ./target/rp/texts/languages.json
status_message completion "en_US and en_GB lang files written\n"

# apply image compression if we can
#if command -v pngquant >/dev/null 2>&1 ; then
#    status_message completion "Optional dependency pngquant detected"
#    status_message process "Attempting image compression"
#    pngquant -f --skip-if-larger --ext .png --strip ./target/rp/textures/blocks/geysercmd/*.png
#    status_message completion "Image compression complete"
#    echo
#fi

# attempt to merge with existing pack if input was provided
if test -f ${merge_input}; then
  mkdir inputbedrockpack
  status_message process "Decompressing input bedrock pack"
  unzip -q ${merge_input} -d ./inputbedrockpack
  status_message process "Merging input bedrock pack with generated bedrock assets"
  cp -n -r "./inputbedrockpack"/* './target/rp/'
  if test -f ./inputbedrockpack/textures/terrain_texture.json; then
    status_message process "Merging terrain texture files"
    jq -s '
    {"resource_pack_name": "vanilla",
    "texture_name": "atlas.terrain",
    "padding": 8, "num_mip_levels": 4,
    "texture_data": (.[1].texture_data + .[0].texture_data)}
    ' ./target/rp/textures/terrain_texture.json ./inputbedrockpack/textures/terrain_texture.json | sponge ./target/rp/textures/terrain_texture.json
  fi
  if test -f ./inputbedrockpack/texts/languages.json; then
    status_message process "Merging languages file"
    jq -s '.[0] + .[1] | unique' | sponge ./target/rp/texts/languages.json
  fi
  if test -f ./inputbedrockpack/texts/en_US.lang; then
    status_message process "Merging en_US lang file"
    cat ./inputbedrockpack/texts/en_US.lang >> ./target/rp/texts/en_US.lang
  fi
  if test -f ./inputbedrockpack/texts/en_GB.lang; then
    status_message process "Merging en_GB lang file"
    cat ./inputbedrockpack/texts/en_GB.lang >> ./target/rp/texts/en_GB.lang
  fi
  status_message critical "Deleting input bedrock pack scratch direcotry"
  rm -rf inputbedrockpack
  status_message completion "Input bedrock pack merged with generated assets\n"
fi

# cleanup
status_message critical "Deleting scratch files"
rm -rf assets && rm -f pack.mcmeta && rm -f pack.png && rm -f parents.json && rm -f all.csv && rm -f pa.csv && rm -f README.md && rm -f README.txt && rm -f *.temp && rm -f spritesheet.json

status_message critical "Deleting unused entries from config"
jq 'map_values(del(.path, .element_parent, .parent, .geyserID))' config.json | sponge config.json
status_message process "Moving config to target directory"
mv config.json ./target/config.json
echo

status_message process "Compressing output packs"
mkdir ./target/packaged
cd ./target/rp > /dev/null && zip -rq8 geyser_rp.mcpack . -x "*/.*" && cd - > /dev/null && mv ./target/rp/geyser_rp.mcpack ./target/packaged/geyser_rp.mcpack
cd ./target/bp > /dev/null && zip -rq8 geyser_bp.mcpack . -x "*/.*" && cd - > /dev/null && mv ./target/bp/geyser_bp.mcpack ./target/packaged/geyser_bp.mcpack
cd ./target/packaged > /dev/null && zip -rq8 geyser.mcaddon . -i "*.mcpack" && cd - > /dev/null
mkdir ./target/unpackaged
mv ./target/rp ./target/unpackaged/rp && mv ./target/bp ./target/unpackaged/bp

echo
printf "\e[32m[+]\e[m \e[1m\e[37mConversion Process Complete\e[m\n\n\e[37mExiting...\e[m\n\n"
