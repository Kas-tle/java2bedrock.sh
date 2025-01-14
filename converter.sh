#!/usr/bin/env bash
: ${1?'Please specify an input resource pack in the same directory as the script (e.g. ./converter.sh MyResourcePack.zip)'}

# define color placeholders
C_RED='\e[31m'
C_GREEN='\e[32m'
C_YELLOW='\e[33m'
C_BLUE='\e[36m'
C_GRAY='\e[37m'
C_CLOSE='\e[m'

# status message function depending on message type
# usage: status <completion|process|critical|error|info|plain> <message>
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

# dependency check function ensures important required programs are installed
# usage: dependency_check <program_name> <program_site> <test_command> <grep_expression>
dependency_check () {
  if command ${3} 2>/dev/null | grep -q "${4}"; then
      status_message completion "Dependency ${1} satisfied"
  else
      status_message error "Dependency ${1} must be installed to proceed\nSee ${2}\nExiting script..."
      exit 1
  fi
}

# user input function to prompt user for info when needed
# usage: user_input <prompt_message> <default_value> <value_description>
user_input () {
  if [[ -z "${!1}" ]]; then
    status_message plain "${2} ${C_YELLOW}[${3}]\n"
    read -p "${4}: " ${1}
    echo
  fi
}

# wait for jobs function prevents the next job from starting until there is a free CPU thread
wait_for_jobs () {
  while test $(jobs -p | wc -w) -ge "$((2*$(nproc)))"; do wait -n; done
}

# ensure input pack exists
if ! test -f "${1}"; then
   status_message error "Input resource pack ${1} is not in this directory"
   exit 1
else
  status_message process "Input file ${1} detected"
fi

# get user defined start flags
while getopts w:m:a:b:f:v:r:s:u: flag "${@:2}"
do
    case "${flag}" in
        w) warn=${OPTARG};;
        m) merge_input=${OPTARG};;
        a) attachable_material=${OPTARG};;
        b) block_material=${OPTARG};;
        f) fallback_pack=${OPTARG};;
        v) default_asset_version=${OPTARG};;
	r) rename_model_files=${OPTARG};;
        s) save_scratch=${OPTARG};;
        u) disable_ulimit=${OPTARG};;
    esac
done

if [[ ${disable_ulimit} == "true" ]]
then
  getconf ARG_MAX
  ulimit -s unlimited
  status_message info "Changed ulimit settings for script:"
  ulimit -a
  echo | xargs --show-limits
  getconf ARG_MAX

fi

# warn user about limitations of the script
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

if [[ ${warn} != "false" ]]; then
read -p $'\e[37mTo acknowledge and continue, press enter. To exit, press Ctrl+C.:\e[0m

'
fi

# ensure we have all the required dependencies
dependency_check "jq" "https://stedolan.github.io/jq/download/" "jq --version" "1.6\|1.7"
dependency_check "sponge" "https://joeyh.name/code/moreutils/" "-v sponge" ""
# dependency_check "imagemagick" "https://imagemagick.org/script/download.php" "convert --version" ""
dependency_check "spritesheet-js" "https://www.npmjs.com/package/spritesheet-js" "-v spritesheet-js" ""
status_message completion "All dependencies have been satisfied\n"

# prompt user for initial configuration
status_message info "This script will now ask some configuration questions. Default values are yellow. Simply press enter to use the defaults.\n"
user_input merge_input "Is there an existing bedrock pack in this directory with which you would like the output merged? (e.g. input.mcpack)" "null" "Input pack to merge"
user_input attachable_material "What material should we use for the attachables?" "entity_alphatest_one_sided" "Attachable material"
user_input block_material "What material should we use for the blocks?" "alpha_test" "Block material"
user_input fallback_pack "From what URL should we download the fallback resource pack? (must be a direct link)\n Use 'none' if default resources are not needed." "null" "Fallback pack URL"

# print initial configuration for user and set default values if none were specified
status_message plain "
Generating Bedrock 3D resource pack with settings:
${C_GRAY}Input pack to merge: ${C_BLUE}${merge_input:=null}
${C_GRAY}Attachable material: ${C_BLUE}${attachable_material:=entity_alphatest_one_sided}
${C_GRAY}Block material: ${C_BLUE}${block_material:=alpha_test}
${C_GRAY}Fallback pack URL: ${C_BLUE}${fallback_pack:=null}
"

# decompress our input pack
status_message process "Decompressing input pack"
unzip -n -q "${1}"
status_message completion "Input pack decompressed"

# exit the script if no input pack exists by checking for a pack.mcmeta file
if [ ! -f pack.mcmeta ]
then
	status_message error "Invalid resource pack! The pack.mcmeta file does not exist. Is the resource pack improperly compressed in an enclosing folder?"
  exit 1
fi

# ensure the directory that would contain predicate definitions exists
if test -d "./assets/minecraft/models/item"
then 
  status_message completion "Minecraft namespace item folder found."
else
  status_message error "Invalid resource pack! No item or block folders exist. No predicate definitions be found."
  exit 1
fi

# Download geyser mappings
status_message process "Downloading the latest geyser item mappings"
mkdir -p ./scratch_files
printf "\e[3m\e[37m"
echo
COLUMNS=$COLUMNS-1 curl --no-styled-output -#L -o scratch_files/item_mappings.json https://raw.githubusercontent.com/GeyserMC/mappings/master/items.json
echo
COLUMNS=$COLUMNS-1 curl --no-styled-output -#L -o scratch_files/item_texture.json https://raw.githubusercontent.com/Kas-tle/java2bedrockMappings/main/item_texture.json
echo
printf "${C_CLOSE}"

# setup our initial config by iterating over all json files in the block and item folders
# technically we only need to iterate over actual item models that contain overrides, but the constraints of bash would likely make such an approach less efficent 
status_message process "Iterating through all vanilla associated model JSONs to generate initial predicate config\nOn a large pack, this may take some time...\n"

jq --slurpfile item_texture scratch_files/item_texture.json --slurpfile item_mappings scratch_files/item_mappings.json -n '
[inputs | {(input_filename | sub("(.+)/(?<itemname>.*?).json"; .itemname)): .overrides?[]?}] |

def maxdur($input):
($item_mappings[] |
[to_entries | map(.key as $key | .value | .java_identifer = $key) | .[] | select(.max_damage)] 
| map({(.java_identifer | split(":") | .[1]): (.max_damage)}) 
| add
| .[$input] // 1)
;

def bedrocktexture($input):
($item_texture[] | .[$input] // {"icon": "camera", "frame": 0})
;

def namespace:
if contains(":") then sub("\\:(.+)"; "") else "minecraft" end
;

[.[] | to_entries | map( select((.value.predicate.damage != null) or (.value.predicate.damaged != null)  or (.value.predicate.custom_model_data != null)) |
      (if .value.predicate.damage then (.value.predicate.damage * maxdur(.key) | ceil) else null end) as $damage
    | (if .value.predicate.damaged == 0 then true else null end) as $unbreakable
    | (if .value.predicate.custom_model_data then .value.predicate.custom_model_data else null end) as $custom_model_data |
  {
    "item": .key,
    "bedrock_icon": bedrocktexture(.key),
    "nbt": ({
      "Damage": $damage,
      "Unbreakable": $unbreakable,
      "CustomModelData": $custom_model_data
    }),
    "path": ("./assets/" + (.value.model | namespace) + "/models/" + (.value.model | sub("(.*?)\\:"; "")) + ".json"),
    "namespace": (.value.model | namespace),
    "model_path": ((.value.model | sub("(.*?)\\:"; "")) | split("/")[:-1] | map(. + "/") | add[:-1] // ""),
    "model_name": ((.value.model | sub("(.*?)\\:"; "")) | split("/")[-1]),
    "generated": false

}) | .[]]
| walk(if type == "object" then with_entries(select(.value != null)) else . end)
| to_entries | map( ((.value.geyserID = "gmdl_\(1+.key)") | .value))
| INDEX(.geyserID)

' ./assets/minecraft/models/item/*.json > config.json || { status_message error "Invalid JSON exists in block or item folder! See above log."; exit 1; }
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
model_array=($(jq -r '[.[].path] | unique | .[]' config.json))

# find initial parental information
status_message process "Doing an initial sweep for level 1 parentals"
jq -n '

[def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end;

inputs | {
  "path": (input_filename),
  "parent": ("./assets/" + (.parent | namespace) + "/models/" + ((.parent? // empty) | sub("(.*?)\\:"; "")) + ".json")
  }
]

' ${model_array[@]} | sponge scratch_files/parents.json

# add initial parental information to config.json
status_message critical "Removing config entries with non-supported parentals\n"
jq -s '

. as $global |

def intest($input_i): ($global | .[0] | map({(.path): .parent}) | add | .[$input_i]? // null);

def gtest($input_g):
[ 
  "./assets/minecraft/models/block/block.json", 
  "./assets/minecraft/models/block/cube.json", 
  "./assets/minecraft/models/block/cube_column.json", 
  "./assets/minecraft/models/block/cube_directional.json", 
  "./assets/minecraft/models/block/cube_mirrored.json", 
  "./assets/minecraft/models/block/observer.json", 
  "./assets/minecraft/models/block/orientable_with_bottom.json", 
  "./assets/minecraft/models/block/piston_extended.json", 
  "./assets/minecraft/models/block/redstone_dust_side.json", 
  "./assets/minecraft/models/block/redstone_dust_side_alt.json", 
  "./assets/minecraft/models/block/template_single_face.json", 
  "./assets/minecraft/models/block/thin_block.json", 
  "./assets/minecraft/models/builtin/entity.json"
]
| index($input_g) // null;

.[1] | map_values(. + ({"parent": (intest(.path) // null)} | if gtest(.parent) == null then . else empty end))
| walk(if type == "object" then with_entries(select(.value != null)) else . end)

' scratch_files/parents.json config.json | sponge config.json

# obtain hashes of all model predicate info to ensure consistent model naming
jq -r '.[] | [.geyserID, (.item + "_c" + (.nbt.CustomModelData | tostring) + "_d" + (.nbt.Damage | tostring) + "_u" + (.nbt.Unbreakable | tostring)), .path] | @tsv | gsub("\\t";",")' config.json > scratch_files/paths.csv

function write_hash () { 
    local entry_hash=$(echo -n "${1}" | md5sum | head -c 7)
    local path_hash=$(echo -n "${2}" | md5sum | head -c 7)
    echo "${3},${entry_hash},${path_hash}" >> "${4}"
}

while IFS=, read -r gid predicate path
    do write_hash "${predicate}" "${path}" "${gid}" "scratch_files/hashes.csv"
done < scratch_files/paths.csv > /dev/null

jq -cR 'split(",")' scratch_files/hashes.csv | jq -s 'map({(.[0]): [.[1], .[2]]}) | add' > scratch_files/hashmap.json

jq --slurpfile hashmap scratch_files/hashmap.json '
    map_values(
        .geyserID as $gid 
        | . += {
          "path_hash": ("gmdl_" + ($hashmap[] | .[($gid)] | .[0])),
          "geometry": ("geo_" + ($hashmap[] | .[($gid)] | .[1]))
          }
    )
' config.json | sponge config.json

# create our initial directories for bp & rp
status_message process "Generating initial directory strucutre for our bedrock packs"
mkdir -p ./target/rp/models/blocks && mkdir -p ./target/rp/textures && mkdir -p ./target/rp/attachables && mkdir -p ./target/rp/animations && mkdir -p ./target/bp/blocks && mkdir -p ./target/bp/items

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
pack_desc="$(jq -r '(.pack.description // "Geyser 3D Items Resource Pack")' ./pack.mcmeta)"

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
        "min_engine_version": [1, 18, 3]
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
        "min_engine_version": [ 1, 18, 3]
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
  "resource_pack_name": "geyser_custom",
  "texture_name": "atlas.terrain",
  "texture_data": {
  }
}
' | sponge ./target/rp/textures/terrain_texture.json

# generate rp item_texture.json
status_message process "Generating resource pack item texture definition"
jq -nc '
{
  "resource_pack_name": "geyser_custom",
  "texture_name": "atlas.items",
  "texture_data": {}
}
' | sponge ./target/rp/textures/item_texture.json

status_message process "Generating resource pack disabling animation"
# generate our disabling animation
jq -nc '
{
  "format_version": "1.8.0",
  "animations": {
    "animation.geyser_custom.disable": {
      "loop": true,
      "override_previous_animation": true,
      "bones": {
        "geyser_custom": {
          "scale": 0
        }
      }
    }
  }
}
' | sponge ./target/rp/animations/animation.geyser_custom.disable.json

# DO DEFAULT ASSETS HERE!!
# get the current default textures and merge them with our rp
if [[ ${fallback_pack} != none ]] && [[ ! -f default_assets.zip ]]
then
  status_message process "Now downloading the fallback resource pack:"
  printf "\e[3m\e[37m"
  echo
  COLUMNS=$COLUMNS-1 curl --no-styled-output -#L -o default_assets.zip https://github.com/InventivetalentDev/minecraft-assets/zipball/refs/tags/${default_asset_version:=1.19.2}
  echo
  printf "${C_CLOSE}"
  status_message completion "Fallback resources downloaded"
fi

if [[ ${fallback_pack} != null &&  ${fallback_pack} != none ]]
then
  printf "\e[3m\e[37m"
  echo
  COLUMNS=$COLUMNS-1 curl --no-styled-output -#L -o provided_assets.zip "${fallback_pack}"
  echo
  printf "${C_CLOSE}"
  status_message completion "Provided resources downloaded"
  mkdir ./providedassetholding
  unzip -n -q -d ./providedassetholding provided_assets.zip "assets/**"
  status_message completion "Provided resources decompressed"
  cp -n -r "./providedassetholding/assets"/** './assets/'
  status_message completion "Provided resources merged with target pack"
fi

if [[ ${fallback_pack} != none ]]
then
  root_folder=($(unzip -Z -1 default_assets.zip | head -1))
  mkdir ./defaultassetholding
  unzip -n -q -d ./defaultassetholding default_assets.zip "${root_folder}assets/minecraft/textures/**/*"
  unzip -n -q -d ./defaultassetholding default_assets.zip "${root_folder}assets/minecraft/models/**/*"
  status_message completion "Fallback resources decompressed"
  mkdir -p './assets/minecraft/textures/'
  cp -n -r "./defaultassetholding/${root_folder}assets/minecraft/textures"/* './assets/minecraft/textures/'
  cp -n -r "./defaultassetholding/${root_folder}assets/minecraft/models"/* './assets/minecraft/models/'
  status_message completion "Fallback resources merged with target pack"
  rm -rf defaultassetholding
  #rm -f default_assets.zip
  status_message critical "Extraneous fallback resources deleted\n"
fi

# generate a fallback texture
convert -size 16x16 xc:\#FFFFFF ./assets/minecraft/textures/0.png

# make sure we crop all mcmeta associated png files
status_message process "Cropping animated textures"
for i in $(find ./assets/**/textures -type f -name "*.mcmeta" | sed 's/\.mcmeta//'); do 
convert ${i} -set option:distort:viewport "%[fx:min(w,h)]x%[fx:min(w,h)]" -distort affine "0,0 0,0" -define png:format=png8 -clamp ${i} 2> /dev/null
done

status_message completion "Initial pack setup complete\n"

jq -r '.[] | select(.parent != null) | [.path, .geyserID, .parent, .namespace, .model_path, .model_name, .path_hash] | @tsv | gsub("\\t";",")' config.json | sponge scratch_files/pa.csv

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
while IFS=, read -r file gid parental namespace model_path model_name path_hash
do
  resolve_parental () {
    local file=${1}
    local gid=${2}
    local parental=${3}
    local namespace=${4}
    local model_path=${5}
    local model_name=${6}
    local path_hash=${7}

    local elements="$(jq -rc '.elements' ${file} | tee scratch_files/${gid}.elements.temp)"
    local element_parent=${file}
    local textures="$(jq -rc '.textures' ${file} | tee scratch_files/${gid}.textures.temp)"
    local display="$(jq -rc '.display' ${file} | tee scratch_files/${gid}.display.temp)"
    status_message process "Locating parental info for child model with GeyserID ${gid}"

    # itterate through parented models until they all have geometry, display, and textures
    until [[ ${elements} != null && ${textures} != null && ${display} != null ]] || [[ ${parental} = "./assets/minecraft/models/builtin/generated.json" ]] || [[ ${parental} = null ]]
    do
      if [[ ${elements} = null ]]
      then
        local elements="$(jq -rc '.elements' ${parental} 2> /dev/null | tee scratch_files/${gid}.elements.temp || (echo && echo null))"
        local element_parent=${parental}
      fi
      if [[ ${textures} = null ]]
      then
        local textures="$(jq -rc '.textures' ${parental} 2> /dev/null | tee scratch_files/${gid}.textures.temp || (echo && echo null))"
      fi
      if [[ ${display} = null ]]
      then
        local display="$(jq -rc '.display' ${parental} 2> /dev/null | tee scratch_files/${gid}.display.temp || (echo && echo null))"
      fi
      local parental="$(jq -rc 'def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end; ("./assets/" + (.parent? | namespace) + "/models/" + ((.parent? // empty) | sub("(.*?)\\:"; "")) + ".json") // "null"' ${parental} 2> /dev/null || (echo && echo null))"
      local texture_0="$(jq -rc 'def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end; ("./assets/" + ([.[]][0]? | namespace) + "/textures/" + (([.[]][0]? // empty) | sub("(.*?)\\:"; "")) + ".png") // "null"' scratch_files/${gid}.textures.temp)"
    done

    # if we can, generate a model now
    if [[ ${elements} != null && ${textures} != null ]]
    then
      jq -n --slurpfile jelements scratch_files/${gid}.elements.temp --slurpfile jtextures scratch_files/${gid}.textures.temp --slurpfile jdisplay scratch_files/${gid}.display.temp '
      {
        "textures": ($jtextures[]),
        "elements": ($jelements[])
      } + (if $jdisplay then ({"display": ($jdisplay[])}) else {} end)
      ' | sponge ${file}
      echo >> scratch_files/count.csv
      local tot_pos=$(wc -l < scratch_files/count.csv)
      status_message completion "Located all parental info for Child ${gid}\n$(ProgressBar ${tot_pos} ${_end})"
      echo
    # check if this is a 2d item dervived from ./assets/minecraft/models/builtin/generated
    elif [[ ${textures} != null && ${parental} = "./assets/minecraft/models/builtin/generated.json" && -f "${texture_0}" ]]
    then
      jq -n --slurpfile jelements scratch_files/${gid}.elements.temp --slurpfile jtextures scratch_files/${gid}.textures.temp --slurpfile jdisplay scratch_files/${gid}.display.temp '
      {
        "textures": ([$jtextures[]][0])
      } + (if $jdisplay then ({"display": ($jdisplay[])}) else {} end)
      ' | sponge ${file}
      # copy texture directly to the rp
      mkdir -p "./target/rp/textures/${namespace}/${model_path}"
      cp "${texture_0}" "./target/rp/textures/${namespace}/${model_path}/${model_name}.png"
      # add texture to item atlas
      echo "${path_hash},textures/${namespace}/${model_path}/${model_name}" >> scratch_files/icons.csv
      echo "${gid}" >> scratch_files/generated.csv
      echo >> scratch_files/count.csv
      local tot_pos=$(wc -l < scratch_files/count.csv)
      status_message completion "Located all parental info for 2D Child ${gid}\n$(ProgressBar ${tot_pos} ${_end})"
      echo
    # otherwise, remove it from our config
    else
      echo "${gid}" >> scratch_files/deleted.csv
      echo >> scratch_files/count.csv
      local tot_pos=$(wc -l < scratch_files/count.csv)
      status_message critical "Deleting ${gid} from config as no suitable parent information was found\n$(ProgressBar ${tot_pos} ${_end})"
      echo
    fi
    rm -f scratch_files/${gid}.elements.temp scratch_files/${gid}.textures.temp scratch_files/${gid}.display.temp
  }
  wait_for_jobs
  resolve_parental "${file}" "${gid}" "${parental}" "${namespace}" "${model_path}" "${model_name}" "${path_hash}" &

done < scratch_files/pa.csv
wait # wait for all the jobs to finish

# update generated models in config
if [[ -f scratch_files/generated.csv ]]
then
  jq -cR 'split(",")' scratch_files/generated.csv | jq -s 'map({(.[0]): true}) | add' > scratch_files/generated.json
  jq -s '
  .[0] as $generated_models
  | .[1]
  | map_values(
    .geyserID as $gid
    | .generated = ($generated_models[($gid)] // false)
  )
  ' scratch_files/generated.json config.json | sponge config.json
fi

# add icon textures to item atlas
if [[ -f scratch_files/icons.csv ]]
then
  jq -cR 'split(",")' scratch_files/icons.csv | jq -s 'map({(.[0]): {"textures": (.[1] | gsub("//"; "/"))}}) | add' > scratch_files/icons.json
  jq -s '
  .[0] as $icons
  | .[1] 
  | .texture_data += $icons
  ' scratch_files/icons.json ./target/rp/textures/item_texture.json | sponge ./target/rp/textures/item_texture.json
fi

# delete unsuitable models
if [[ -f scratch_files/deleted.csv ]]
then
  jq -cR 'split(",")' scratch_files/deleted.csv  | jq -s '.' > scratch_files/deleted.json
  jq -s '.[0] as $deleted | .[1] | delpaths($deleted)' scratch_files/deleted.json config.json | sponge config.json
fi

status_message process "Compiling final model list"
# get our final 3d model list from the config
model_list=( $(jq -r '.[] | select(.generated == false) | .path' config.json) )

# get our final texture list to be atlased
# get a bash array of all texture files in our resource pack
status_message process "Generating an array of all model PNG files to crosscheck with our atlas"
jq -n '$ARGS.positional' --args $(find ./assets/**/textures -type f -name '*.png') | sponge scratch_files/all_textures.temp
# get bash array of all texture files listed in our models
status_message process "Generating union atlas arrays for all model textures"
jq -s '
def namespace: 
  if contains(":") then sub("\\:(.+)"; "") else "minecraft" end; 
[.[]| [.textures[]?] | unique] 
| map(map("./assets/" + (. | namespace) + "/textures/" + (. | sub("(.*?)\\:"; "")) + ".png"))
' ${model_list[@]} | sponge scratch_files/union_atlas.temp
jq '
def intersects(a;b): any(a[]; . as $x | any(b[]; . == $x));

def mapatlas(set):
(set | unique) as $unique_set
| (map(if intersects(.; $unique_set) then . else empty end) | add + $unique_set | unique) as $new_set
| map(if intersects(.; $new_set) then empty else . end) + [$new_set];

[["./assets/minecraft/textures/0.png"]] +
reduce .[] as $entry ([]; mapatlas($entry))
' scratch_files/union_atlas.temp | sponge scratch_files/union_atlas.temp
total_union_atlas=($(jq -r 'length - 1' scratch_files/union_atlas.temp))

mkdir -p scratch_files/spritesheet
status_message process "Generating $((1+${total_union_atlas})) sprite sheets..."
for i in $(seq 0 ${total_union_atlas})
do
  generate_atlas () {
    # find the union of all texture files listed in this atlas and all texture files in our resource pack
    local texture_list=( $(jq -s --arg index "${1}" -r '(.[1][($index | tonumber)] - .[0] | length > 0) as $fallback_needed | ((.[1][($index | tonumber)] - (.[1][($index | tonumber)] - .[0])) + (if $fallback_needed then ["./assets/minecraft/textures/0.png"] else [] end)) | .[]' scratch_files/all_textures.temp scratch_files/union_atlas.temp) )
    status_message process "Generating sprite sheet ${1} of ${total_union_atlas}"
    spritesheet-js -f json --name scratch_files/spritesheet/${1} --fullpath ${texture_list[@]} 1> /dev/null
    echo ${1} >> scratch_files/atlases.csv
  }
  wait_for_jobs
  generate_atlas "${i}" &
done
wait # wait for all the jobs to finish

# generate terrain texture atlas
jq -cR 'split(",")' scratch_files/atlases.csv | jq -s 'map({("gmdl_atlas_" + .[0]): {"textures": ("textures/" + .[0])}}) | add' > scratch_files/atlases.json
jq -s '
.[0] as $atlases
| .[1] 
| .texture_data += $atlases
' scratch_files/atlases.json ./target/rp/textures/terrain_texture.json | sponge ./target/rp/textures/terrain_texture.json

status_message completion "All sprite sheets generated"
mv scratch_files/spritesheet/*.png ./target/rp/textures

# begin conversion
jq -r '.[] | [.path, .geyserID, .generated, .namespace, .model_path, .model_name, .path_hash, .geometry] | @tsv | gsub("\\t";",")' config.json | sponge scratch_files/all.csv

while IFS=, read -r file gid generated namespace model_path model_name path_hash geometry
do
   convert_model () {
    local file="${1}"
    local gid="${2}"
    local generated="${3}"
    local namespace="${4}"
    local model_path="${5}"
    local model_name="${6}"
    local path_hash="${7}"
    local geometry="${8}"

    # find which texture atlas we will be using if not generated
    if [[ ${generated} = "false" ]]
    then
      local atlas_index=$(jq -r -s 'def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end; def intersects(a;b): any(a[]; . as $x | any(b[]; . == $x)); (.[0] | [.textures[]] | map("./assets/" + (. | namespace) + "/textures/" + (. | sub("(.*?)\\:"; "")) + ".png")) as $inp | [(.[1] | (map(if intersects(.;$inp) then . else empty end)[])) as $entry | .[1] | to_entries[] | select(.value == $entry).key][0] // 0' ${file} scratch_files/union_atlas.temp)
    else
      local atlas_index=0
    fi

    status_message process "Starting conversion of model with GeyserID ${gid}"
    mkdir -p ./target/rp/models/blocks/${namespace}/${model_path}
    jq --slurpfile atlas scratch_files/spritesheet/${atlas_index}.json --arg generated "${generated}" --arg binding "c.item_slot == 'head' ? 'head' : q.item_slot_to_bone_name(c.item_slot)" --arg geometry "${geometry}" -c '
    .textures as $texture_list |
    def namespace: if contains(":") then sub("\\:(.+)"; "") else "minecraft" end;
    def tobool: if .=="true" then true elif .=="false" then false else null end;
    def totexture($input): ($texture_list[($input[1:])]? // ([$texture_list[]][0]));
    def topath($input): ("./assets/" + ($input | namespace) + "/textures/" + ($input | sub("(.*?)\\:"; "")) + ".png");
    def texturedata($input): $atlas[] | .frames | (.[topath(totexture($input))] // ."./assets/minecraft/textures/0.png");
    def roundit: (.*10000 | round) / 10000;
    def element_array:
        if .elements then (.elements | map({
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
            (if ($input == "up" or $input == "down") then {
              "uv": [(($fn2 - (0.016 * $x_sign)) | roundit), (($fn3 - (0.016 * $y_sign)) | roundit)],
              "uv_size": [((($fn0 - $fn2) + (0.016 * $x_sign)) | roundit), ((($fn1 - $fn3) + (0.016 * $y_sign)) | roundit)]
            } else {
              "uv": [(($fn0 + (0.016 * $x_sign)) | roundit), (($fn1 + (0.016 * $y_sign)) | roundit)],
              "uv_size": [((($fn2 - $fn0) - (0.016 * $x_sign)) | roundit), ((($fn3 - $fn1) - (0.016 * $y_sign)) | roundit)]
            } end) else null end);
          {
          "north": uv_calc("north"),
          "south": uv_calc("south"),
          "east": uv_calc("east"),
          "west": uv_calc("west"),
          "up": uv_calc("up"),
          "down": uv_calc("down")
          })
      }) | walk( if type == "object" then with_entries(select(.value != null)) else . end)) else {} end
      ;
      def pivot_groups:
      if .elements then ((element_array) as $element_array |
      [[.elements[].rotation] | unique | .[] | select (.!=null)]
      | map((
      [((- .origin[0] + 8) | roundit), (.origin[1] | roundit), ((.origin[2] - 8) | roundit)] as $i_piv |
      (if (.axis) == "x" then [(.angle | tonumber * -1), 0, 0] elif (.axis) == "y" then [0, (.angle | tonumber * -1), 0] else [0, 0, (.angle | tonumber)] end) as $i_rot |
      {
        "parent": "geyser_custom_z",
        "pivot": ($i_piv),
        "rotation": ($i_rot),
        "cubes": [($element_array | .[] | select(.rotation == $i_rot and .pivot == $i_piv))]
      }))) else {} end
      ;
      {
        "format_version": "1.16.0",
        "minecraft:geometry": [{
          "description": {
            "identifier": ( "geometry.geyser_custom." + ($geometry)),
            "texture_width": 16,
            "texture_height": 16,
            "visible_bounds_width": 4,
            "visible_bounds_height": 4.5,
            "visible_bounds_offset": [0, 0.75, 0]
          },
          "bones": ([{
            "name": "geyser_custom",
            "binding": $binding,
            "pivot": [0, 8, 0]
          }, {
            "name": "geyser_custom_x",
            "parent": "geyser_custom",
            "pivot": [0, 8, 0]
          }, {
            "name": "geyser_custom_y",
            "parent": "geyser_custom_x",
            "pivot": [0, 8, 0]
          }, 
            if ($generated | tobool) == true then ({
            "name": "geyser_custom_z",
            "parent": "geyser_custom_y",
            "pivot": [0, 8, 0],
            "texture_meshes": ([{"texture": "default", "position": [0, 8, 0], "rotation": [90, 0, -180], "local_pivot": [8, 0.5, 8]}])
          }) else ({
            "name": "geyser_custom_z",
            "parent": "geyser_custom_y",
            "pivot": [0, 8, 0],
            "cubes": ([(element_array | .[] | select(.rotation == null))])
            }) end] + (pivot_groups | map(del(.cubes[].rotation)) | to_entries | map( (.value.name = "rot_\(1+.key)" ) | .value)))
        }]
      }
      ' ${file} | sponge ./target/rp/models/blocks/${namespace}/${model_path}/${model_name}.json

      # generate our rp animations via display settings
      mkdir -p ./target/rp/animations/${namespace}/${model_path}
      jq -c --arg geometry "${geometry}" '

      {
        "format_version": "1.8.0",
        "animations": {
          ("animation.geyser_custom." + ($geometry) + ".thirdperson_main_hand"): {
            "loop": true,
            "bones": {
              "geyser_custom_x": (if .display.thirdperson_righthand then {
                "rotation": (if .display.thirdperson_righthand.rotation then [(- .display.thirdperson_righthand.rotation[0]), 0, 0] else null end),
                "position": (if .display.thirdperson_righthand.translation then [(- .display.thirdperson_righthand.translation[0]), (.display.thirdperson_righthand.translation[1]), (.display.thirdperson_righthand.translation[2])] else null end),
                "scale": (if .display.thirdperson_righthand.scale then [(.display.thirdperson_righthand.scale[0]), (.display.thirdperson_righthand.scale[1]), (.display.thirdperson_righthand.scale[2])] else null end)
              } else null end),
              "geyser_custom_y": (if .display.thirdperson_righthand.rotation then {
                "rotation": (if .display.thirdperson_righthand.rotation then [0, (- .display.thirdperson_righthand.rotation[1]), 0] else null end)
              } else null end),
              "geyser_custom_z": (if .display.thirdperson_righthand.rotation then {
                "rotation": [0, 0, (.display.thirdperson_righthand.rotation[2])]
              } else null end),
              "geyser_custom": {
                "rotation": [90, 0, 0],
                "position": [0, 13, -3]
              }
            }
          },
          ("animation.geyser_custom." + ($geometry) + ".thirdperson_off_hand"): {
            "loop": true,
            "bones": {
              "geyser_custom_x": (if .display.thirdperson_lefthand then {
                "rotation": (if .display.thirdperson_lefthand.rotation then [(- .display.thirdperson_lefthand.rotation[0]), 0, 0] else null end),
                "position": (if .display.thirdperson_lefthand.translation then [(.display.thirdperson_lefthand.translation[0]), (.display.thirdperson_lefthand.translation[1]), (.display.thirdperson_lefthand.translation[2])] else null end),
                "scale": (if .display.thirdperson_lefthand.scale then [(.display.thirdperson_lefthand.scale[0]), (.display.thirdperson_lefthand.scale[1]), (.display.thirdperson_lefthand.scale[2])] else null end)
              } else null end),
              "geyser_custom_y": (if .display.thirdperson_lefthand.rotation then {
                "rotation": (if .display.thirdperson_lefthand.rotation then [0, (- .display.thirdperson_lefthand.rotation[1]), 0] else null end)
              } else null end),
              "geyser_custom_z": (if .display.thirdperson_lefthand.rotation then {
                "rotation": [0, 0, (.display.thirdperson_lefthand.rotation[2])]
              } else null end),
              "geyser_custom": {
                "rotation": [90, 0, 0],
                "position": [0, 13, -3]
              }
            }
          },
          ("animation.geyser_custom." + ($geometry) + ".head"): {
            "loop": true,
            "bones": {
              "geyser_custom_x": {
                "rotation": (if .display.head.rotation then [(- .display.head.rotation[0]), 0, 0] else null end),
                "position": (if .display.head.translation then [(- .display.head.translation[0] * 0.625), (.display.head.translation[1] * 0.625), (.display.head.translation[2] * 0.625)] else null end),
                "scale": (if .display.head.scale then (.display.head.scale | map(. * 0.625)) else 0.625 end)
              },
              "geyser_custom_y": (if .display.head.rotation then {
                "rotation": [0, (- .display.head.rotation[1]), 0]
              } else null end),
              "geyser_custom_z": (if .display.head.rotation then {
                "rotation": [0, 0, (.display.head.rotation[2])]
              } else null end),
              "geyser_custom": {
                "position": [0, 19.9, 0]
              }
            }
          },
          ("animation.geyser_custom." + ($geometry) + ".firstperson_main_hand"): {
            "loop": true,
            "bones": {
              "geyser_custom": {
                "rotation": [90, 60, -40],
                "position": [4, 10, 4],
                "scale": 1.5
              },
              "geyser_custom_x": {
                "position": (if .display.firstperson_righthand.translation then [(- .display.firstperson_righthand.translation[0]), (.display.firstperson_righthand.translation[1]), (- .display.firstperson_righthand.translation[2])] else null end),
                "rotation": (if .display.firstperson_righthand.rotation then [(- .display.firstperson_righthand.rotation[0]), 0, 0] else [0.1, 0.1, 0.1] end),
                "scale": (if .display.firstperson_righthand.scale then (.display.firstperson_righthand.scale) else null end)
              },
              "geyser_custom_y": (if .display.firstperson_righthand.rotation then {
                "rotation": [0, (- .display.firstperson_righthand.rotation[1]), 0]
              } else null end),
              "geyser_custom_z": (if .display.firstperson_righthand.rotation then {
                "rotation": [0, 0, (.display.firstperson_righthand.rotation[2])]
              } else null end)
            }
          },
          ("animation.geyser_custom." + ($geometry) + ".firstperson_off_hand"): {
            "loop": true,
            "bones": {
              "geyser_custom": {
                "rotation": [90, 60, -40],
                "position": [4, 10, 4],
                "scale": 1.5
              },
              "geyser_custom_x": {
                "position": (if .display.firstperson_lefthand.translation then [(.display.firstperson_lefthand.translation[0]), (.display.firstperson_lefthand.translation[1]), (- .display.firstperson_lefthand.translation[2])] else null end),
                "rotation": (if .display.firstperson_lefthand.rotation then [(- .display.firstperson_lefthand.rotation[0]), 0, 0] else [0.1, 0.1, 0.1] end),
                "scale": (if .display.firstperson_lefthand.scale then (.display.firstperson_lefthand.scale) else null end)
              },
              "geyser_custom_y": (if .display.firstperson_lefthand.rotation then {
                "rotation": [0, (- .display.firstperson_lefthand.rotation[1]), 0]
              } else null end),
              "geyser_custom_z": (if .display.firstperson_lefthand.rotation then {
                "rotation": [0, 0, (.display.firstperson_lefthand.rotation[2])]
              } else null end)
            }
          }
        }
      } | walk( if type == "object" then with_entries(select(.value != null)) else . end)

      ' ${file} | sponge ./target/rp/animations/${namespace}/${model_path}/animation.${model_name}.json

      # generate our bp block definition if this is a 3D item
      if [[ ${generated} = false ]]
      then
        mkdir -p ./target/bp/blocks/${namespace}/${model_path}
        jq -c -n --arg atlas_index "${atlas_index}" --arg block_material "${block_material}" --arg path_hash "${path_hash}" --arg geometry "${geometry}" '
        {
            "format_version": "1.16.100",
            "minecraft:block": {
                "description": {
                    "identifier": ("geyser_custom:" + $path_hash)
                },
                "components": {
                    "minecraft:material_instances": {
                        "*": {
                            "texture": ("gmdl_atlas_" + $atlas_index),
                            "render_method": $block_material,
                            "face_dimming": false,
                            "ambient_occlusion": false
                        }
                    },
                    "minecraft:geometry": ("geometry.geyser_custom." + $geometry),
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
        ' | sponge ./target/bp/blocks/${namespace}/${model_path}/${model_name}.json
      # generate our bp item definition if this is a 2D item
      else
        mkdir -p ./target/bp/items/${namespace}/${model_path}
        jq -c -n --arg path_hash "${path_hash}" '
        {
            "format_version": "1.16.100",
            "minecraft:item": {
                "description": {
                    "identifier": ("geyser_custom:" + $path_hash),
                    "category": "items"
                },
                "components": {
                  "minecraft:icon": {
                    "texture": $path_hash
                  }
                }
            }
        }
        ' | sponge ./target/bp/items/${namespace}/${model_path}/${model_name}.${path_hash}.json
      fi

      # generate our rp attachable definition
      mkdir -p ./target/rp/attachables/${namespace}/${model_path}
      jq -c -n --arg generated "${generated}" --arg atlas_index "${atlas_index}" --arg attachable_material "${attachable_material}" --arg v_main "v.main_hand = c.item_slot == 'main_hand';" --arg v_off "v.off_hand = c.item_slot == 'off_hand';" --arg v_head "v.head = c.item_slot == 'head';" --arg path_hash "${path_hash}" --arg namespace "${namespace}" --arg model_path "${model_path}" --arg model_name "${model_name}" --arg geometry "${geometry}" '
      def tobool: if .=="true" then true elif .=="false" then false else null end;
      {
        "format_version": "1.10.0",
        "minecraft:attachable": {
          "description": {
            "identifier": ("geyser_custom:" + $path_hash),
            "materials": {
              "default": $attachable_material,
              "enchanted": $attachable_material
            },
            "textures": {
              "default": (if ($generated | tobool) == true then ("textures/" + $namespace + "/" + $model_path + "/" + $model_name) else ("textures/" + $atlas_index) end),
              "enchanted": "textures/misc/enchanted_item_glint"
            },
            "geometry": {
              "default": ("geometry.geyser_custom." + $geometry)
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
              "thirdperson_main_hand": ("animation.geyser_custom." + $geometry + ".thirdperson_main_hand"),
              "thirdperson_off_hand": ("animation.geyser_custom." + $geometry + ".thirdperson_off_hand"),
              "thirdperson_head": ("animation.geyser_custom." + $geometry + ".head"),
              "firstperson_main_hand": ("animation.geyser_custom." + $geometry + ".firstperson_main_hand"),
              "firstperson_off_hand": ("animation.geyser_custom." + $geometry + ".firstperson_off_hand"),
              "firstperson_head": "animation.geyser_custom.disable"
            },
            "render_controllers": [ "controller.render.item_default" ]
          }
        }
      }

      ' | sponge ./target/rp/attachables/${namespace}/${model_path}/${model_name}.${path_hash}.attachable.json

      # progress
      echo >> scratch_files/count.csv
      local tot_pos=$((cur_pos + $(wc -l < scratch_files/count.csv)))
      status_message completion "${gid} converted\n$(ProgressBar ${tot_pos} ${_end})"
      echo
   }
   wait_for_jobs
   convert_model "${file}" "${gid}" "${generated}" "${namespace}" "${model_path}" "${model_name}" "${path_hash}" "${geometry}" &

done < scratch_files/all.csv
wait # wait for all the jobs to finish

# write lang file US
status_message process "Writing en_US and en_GB lang files"
mkdir ./target/rp/texts
jq -r '

def format: (.[0:1] | ascii_upcase ) + (.[1:] | gsub( "_(?<a>[a-z])"; (" " + .a) | ascii_upcase));
.[]|"\("item.geyser_custom:" + .path_hash + ".name")=\(.item | format)"

' config.json | sponge ./target/rp/texts/en_US.lang

# copy US lang to GB
cp ./target/rp/texts/en_US.lang ./target/rp/texts/en_GB.lang

# write supported languages file
jq -n '["en_US","en_GB"]' | sponge ./target/rp/texts/languages.json
status_message completion "en_US and en_GB lang files written\n"

# Ensure images are in the correct color space
status_message process "Setting all images to png8"
find ./target/rp/textures -name '*.png' -exec mogrify -define png:format=png8  {} +
status_message completion "All images set to png8"

if [[ ${rename_model_files} == "true" ]]
then
    status_message process "Consolidating model files"
    function consolidate_files () {
	## Get a list of all files
	list=$(find ${1} -mindepth 2 -type f -print)
	nr=1
	
	## Move all files that are unique
	find ${1} -mindepth 2 -type f -print0 | while IFS= read -r -d '' file; do
	    mv -n "$file" ${1}/
	done
	list=$(find ${1} -mindepth 2 -type f -print)
	
	## Checking which files need to be renamed
	while [[ $list != '' ]] ; do
	   ##Remaming the un-moved files to unique names and move the renamed files
	   find ${1} -mindepth 2 -type f -print0 | while IFS= read -r -d '' file; do
	       current_file=$(basename "$file")
	       mv -n "$file" "./${nr}${current_file}"
	   done
	   ## Incrementing counter to prefix to file name
	   nr=$((nr+1))
	   list=$(find ${1} -mindepth 2 -type f -print)
	done
     }
     consolidate_files './target/rp/animations'
     rm -rf ./target/rp/animations/*/
     consolidate_files './target/rp/models/blocks'
     rm -rf ./target/rp/models/blocks/*/
     consolidate_files './target/rp/attachables'
     rm -rf rm -rf ./target/rp/attachables/*/
fi

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
    {
      "resource_pack_name": "geyser_custom",
      "texture_name": "atlas.terrain",
      "texture_data": (.[1].texture_data + .[0].texture_data)
    }
    ' ./target/rp/textures/terrain_texture.json ./inputbedrockpack/textures/terrain_texture.json | sponge ./target/rp/textures/terrain_texture.json
  fi
  if test -f ./inputbedrockpack/textures/item_texture.json; then
    status_message process "Merging item texture files"
    jq -s '
    {
      "resource_pack_name": "geyser_custom",
      "texture_name": "atlas.items",
      "texture_data": (.[1].texture_data + .[0].texture_data)
    }
    ' ./target/rp/textures/item_texture.json ./inputbedrockpack/textures/item_texture.json | sponge ./target/rp/textures/item_texture.json
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

status_message process "Creating Geyser mappings in target directory"
echo
jq '
([map(
  {
    ("minecraft:" + .item): [
      {
        "name": .path_hash,
        "allow_offhand": true,
        "icon": (if .generated == true then .path_hash else .bedrock_icon.icon end)
      }
      + (if (.generated == false) then {"frame": (.bedrock_icon.frame)} else {} end)
      + (if .nbt.CustomModelData then {"custom_model_data": (.nbt.CustomModelData)} else {} end)
      + (if .nbt.Damage then {"damage_predicate": (.nbt.Damage)} else {} end)
      + (if .nbt.Unbreakable then {"unbreakable": (.nbt.Unbreakable)} else {} end)
    ]
  }
) 
| map(to_entries[])
| group_by(.key)[] 
| {(.[0].key) : map(.value) | add}] | add) as $mappings
| {
    "format_version": "1",
    "items": $mappings
  }
' config.json | sponge ./target/geyser_mappings.json

# Add sprites if sprites.json exists in the root pack
if [ -f sprites.json ]; then
  status_message process "Adding provided sprite paths from sprites.json"
  jq -r '
  to_entries 
  | map(.key as $item | .value | map(. += {"item": $item})) 
  | add[] 
  | [((.item | split(":")[-1]) + "_c" + (.custom_model_data | tostring) + "_d" + (.damage_predicate | tostring) + "_u" + (.unbreakable | tostring)), .sprite] 
  | @tsv 
  | gsub("\\t";",")
  ' sprites.json > scratch_files/sprites.csv

  function write_id_hash () { 
    local entry_hash=$(echo -n "${1}" | md5sum | head -c 7)
    echo "${2},${entry_hash}" >> "${3}"
  }
 
  while IFS=, read -r predicate icon
    do write_id_hash "${predicate}" "${icon}"  "scratch_files/sprite_hashes.csv" &
  done < scratch_files/sprites.csv > /dev/null

  jq -cR 'split(",")' scratch_files/sprite_hashes.csv | jq -s 'map({("gmdl_" + .[1]): {"textures": .[0]}}) | add' > scratch_files/sprite_hashmap.json

  jq -s '
  .[0] as $icon_sprites
  | .[1] 
  | .texture_data += $icon_sprites
  ' scratch_files/sprite_hashmap.json ./target/rp/textures/item_texture.json | sponge ./target/rp/textures/item_texture.json
  
  jq -s '
  {
  "format_version": "1",
  "items": 
    ((.[0] | keys | map({(.): (.)}) | add) as $sprites | .[1].items | to_entries | map(
    (.key | split(":")[1]) as $item
    | .value | {("minecraft:" + $item): (map(
      .name as $name
      | .icon as $icon
      | .icon = ($sprites[($name)] // $icon)
    ))}
    ) | add)
  }
  ' scratch_files/sprite_hashmap.json ./target/geyser_mappings.json | sponge ./target/geyser_mappings.json
  
fi

# cleanup
rm -rf assets && rm -f pack.mcmeta && rm -f pack.png
if [[ ${save_scratch} != "true" ]] 
then
  rm -rf scratch_files
  status_message critical "Deleted scratch files"
else
  cd ./scratch_files > /dev/null && zip -rq8 scratch_files.zip . -x "*/.*" && cd .. > /dev/null && mv ./scratch_files/scratch_files.zip ./target/scratch_files.zip
  status_message completion "Archived scratch files\n"
fi


status_message process "Compressing output packs"
mkdir ./target/packaged
cd ./target/rp > /dev/null && zip -rq8 geyser_resources_preview.mcpack . -x "*/.*" && cd ../.. > /dev/null && mv ./target/rp/geyser_resources_preview.mcpack ./target/packaged/geyser_resources_preview.mcpack
cd ./target/bp > /dev/null && zip -rq8 geyser_behaviors_preview.mcpack . -x "*/.*" && cd ../.. > /dev/null && mv ./target/bp/geyser_behaviors_preview.mcpack ./target/packaged/geyser_behaviors_preview.mcpack
cd ./target/packaged > /dev/null && zip -rq8 geyser_addon.mcaddon . -i "*_preview.mcpack" && cd ../.. > /dev/null
jq 'delpaths([paths | select(.[-1] | strings | startswith("gmdl_atlas_"))])' ./target/rp/textures/terrain_texture.json | sponge ./target/rp/textures/terrain_texture.json
cd ./target/rp > /dev/null && zip -rq8 geyser_resources.mcpack . -x "*/.*" && cd ../.. > /dev/null && mv ./target/rp/geyser_resources.mcpack ./target/packaged/geyser_resources.mcpack
mkdir ./target/unpackaged
mv ./target/rp ./target/unpackaged/rp && mv ./target/bp ./target/unpackaged/bp

echo
printf "\e[32m[+]\e[m \e[1m\e[37mConversion Process Complete\e[m\n\n\e[37mExiting...\e[m\n\n"
