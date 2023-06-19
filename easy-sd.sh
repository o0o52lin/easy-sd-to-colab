#/bin/bash

env PYTHONDONTWRITEBYTECODE=1 &>/dev/null
env TF_CPP_MIN_LOG_LEVEL=1 &>/dev/null

function safe_git {
  if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: safe_git <repo_url> <local_folder> [<branch_name>]"
    return 1
  fi

  local repo_url=$1 local_folder=$2 branch_name=${3:-""} retry_count=3

  if [ -d "$local_folder/.git" ] && git -C "$local_folder" rev-parse &> /dev/null; then
    echo "INFO: Repo $local_folder is valid, performing update."
    git -c core.hooksPath=/dev/null -C "$local_folder" pull && return 0
  else
    echo "INFO: Repo $local_folder is not valid or does not exist, cloning."
    rm -rf "$local_folder"
    for i in $(seq $retry_count); do
      git -c core.hooksPath=/dev/null clone ${branch_name:+-b "$branch_name"} "$repo_url" "$local_folder" && return 0
      echo "NOTICE: git clone failed, retrying in 5 seconds (attempt $i of $retry_count)..."
      sleep 5  # Wait for 5 seconds before retrying
      rm -rf "$local_folder"
    done

    echo "ERROR: All git clone attempts for '$repo_url' failed, please rerun the script." >&2
    exit 1
  fi
}

function safe_fetch {
  local url="$1"
  local output_dir="$2"
  local output_filename="$3"
  local retries=3
  local timeout=120
  local waitretry=5
  local tmp_file="$output_filename.tmp"

  if [[ $# -ne 3 ]]; then
    echo "Usage: safe_fetch <url> <output_dir> <output_filename>"
    return 1
  fi

  if [[ -f "$output_dir/$output_filename" ]]; then
    location=$(curl -Is -X GET "$url" | grep -i location | awk '{print $2}')
    if [[ ! -z $location ]]; then
      url=$location
    fi
    remote_size=$(curl -Is "$url" | awk '/content-length/ {clen=$2} /x-linked-size/ {xsize=$2} END {if (xsize) print xsize; else print clen;}' | tr -dc '0-9' || echo '')
    local_size=$(stat --format=%s "$output_dir/$output_filename" 2>/dev/null | tr -dc '0-9' || echo '')
    echo "LOCAL_SIZE: $local_size"
    echo "REMOTE_SIZE: $remote_size"
    if [[ $local_size != 0 ]] && [[ "$local_size" -eq "$remote_size" ]]; then
      echo "INFO: local file '$output_filename' is up-to-date, skipping download"
      return 0
    fi
  fi

  mkdir -p "$output_dir"
  for ((i=1; i<=retries; i++)); do
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "$url" -d "$output_dir" -o "$tmp_file" && { mv "$output_dir/$tmp_file" "$output_dir/$output_filename" && echo "INFO: downloaded '$output_filename' to '$output_dir'" && return 0; }
    echo "NOTICE: failed to download '$output_filename', retrying in $waitretry seconds (attempt $i of $retries)..."
    sleep "$waitretry"
  done

  echo "ERROR: failed to download '$output_filename' after $retries attempts, please rerun the script." >&2
  rm -f "$tmp_file"
  exit 1
}

function reset_repos {
    if [ "$#" -lt 1 ]; then
        echo "Usage: reset_repos <base_dir> [<all>]"
        return 1
    fi
    if [ ! -d "$1" ]; then
        echo "Error: The base_dir passed is not a valid path"
        return 1
    fi
    local base_path="$1" all=${2:-""}
    git -C $base_path reset --hard
    if test -d "$base_path/repositories/stable-diffusion-stability-ai"; then
      git -C $base_path/repositories/stable-diffusion-stability-ai reset --hard
    fi
    if [ "$all" = "all" ]; then
      cd $base_path/extensions && find . -maxdepth 1 -type d \( ! -name . \) -exec bash -c "echo '{}' && git -C '{}' reset --hard && git pull" \;
    fi
}

function sed_for {
    if [ "$#" -lt 2 ]; then
        echo "Usage: sed_for <installation|run> <base_dir>"
        return 1
    fi
    local option=$1
    local base_dir=$2
    if [ ! -d "$base_dir" ]; then
        echo "Error: '$base_dir' is not a valid directory"
        return 1
    fi
    if [[ $option == "installation" ]]; then
        sed -i -e 's/ checkout {commithash}/ checkout -f {commithash}/g' $base_dir/modules/launch_utils.py
        sed -i -e 's/    start()/    #start()/g' $base_dir/launch.py
    elif [[ $option == "run" ]]; then
        sed -i -e """/    prepare_environment()/a\    os.system\(f\'''sed -i -e ''\"s/dict()))/dict())).cuda()/g\"'' $base_dir/repositories/stable-diffusion-stability-ai/ldm/util.py''')""" $base_dir/modules/launch_utils.py
        sed -i -e 's/\"sd_model_checkpoint\"\,/\"sd_model_checkpoint\,sd_vae\,CLIP_stop_at_last_layers\"\,/g' $base_dir/modules/shared.py
    else
        echo "Error: Invalid argument '$option'"
        echo "Usage: sed_for <installation|run> <base_dir>"
        return 1
    fi
    sed -i -e 's/}" checkout {/}" checkout -f {/g' $base_dir/modules/launch_utils.py
}

function prepare_perf_tools {
    local packages=("http://launchpadlibrarian.net/367274644/libgoogle-perftools-dev_2.5-2.2ubuntu3_amd64.deb" "https://launchpad.net/ubuntu/+source/google-perftools/2.5-2.2ubuntu3/+build/14795286/+files/google-perftools_2.5-2.2ubuntu3_all.deb" "https://launchpad.net/ubuntu/+source/google-perftools/2.5-2.2ubuntu3/+build/14795286/+files/libtcmalloc-minimal4_2.5-2.2ubuntu3_amd64.deb" "https://launchpad.net/ubuntu/+source/google-perftools/2.5-2.2ubuntu3/+build/14795286/+files/libgoogle-perftools4_2.5-2.2ubuntu3_amd64.deb")
    regex="/([^/]+)\.deb$"
    install=false
    for package in "${packages[@]}"; do
        echo $package
        if [[ $package =~ $regex ]]; then
          filename=${BASH_REMATCH[1]}
          package_name=$(echo "${BASH_REMATCH[1]}" | cut -d "_" -f 1)
          package_version=$(echo "${BASH_REMATCH[1]}" | cut -d "_" -f 2)
          if dpkg-query -W "$package_name" 2>/dev/null | grep -q "$package_version"; then
            echo "already installed: $package_name with version $package_version, skipping"
            continue
          fi
          #not installed or not the required version
          safe_fetch $package /tmp $package_name.deb
          install=true
        else
          echo "Invalid URL format"
        fi
    done
    apt install -qq libunwind8-dev
    env LD_PRELOAD=libtcmalloc.so &>/dev/null
    $install && dpkg -i /tmp/*.deb
}

function assemble_target_path {
    if [[ "$#" -ne 1 ]]; then
      echo "Usage: assemble_target_path <type>"
      return 1
    fi
    local type=$1
    case $type in
      webui)
        echo $BASEPATH
        ;;
      extension|extensions)
        echo $BASEPATH/extensions
        ;;
      script|scripts)
        echo $BASEPATH/scripts
        ;;
      embedding|embeddings)
        echo $BASEPATH/embeddings
        ;;
      esrgan|ESRGAN_models)
        echo $BASEPATH/models/ESRGAN
        ;;
      checkpoint|checkpoints)
        echo $BASEPATH/models/Stable-diffusion
        ;;
      hypernetwork|hypernetworks)
        echo $BASEPATH/models/hypernetworks
        ;;
      lora|loras)
        echo $BASEPATH/models/Lora
        ;;
      lycori|lycoris)
        echo $BASEPATH/models/LyCORIS
        ;;
      vae|vaes)
        echo $BASEPATH/models/VAE
        ;;
      clip|clips)
        echo $BASEPATH/models/CLIP
        ;;
      controlnet|cn_models)
        echo $BASEPATH/extensions/sd-webui-controlnet/models
        ;;
      *)
        echo "Error: Unrecognized template config type $type."
        exit 1
        ;;
    esac
}
function install_from_template {
    if [ "$#" -ne 1 ]; then
      echo "Usage: install_from_template <config_path>"
      return 1
    fi
    local config_path=$1
    if [[ -f $config_path ]]; then
      mapfile -t lines < $config_path
      for line in "${lines[@]}"
      do
          echo "->Processing template config line: $line"
          trimmed_url=$(echo "$line" | tr -d ' ' | cut -d "#" -f 1)
          # 判断file<=url配置
          if [[ $trimmed_url == *"<="* ]]; then
            base_name=${trimmed_url%%<=*}
            trimmed_url=${trimmed_url#*<=}
          else
            base_name=$(basename $trimmed_url)
          fi
          echo "->base_name: $base_name"
          if [[ ! -z $trimmed_url ]]; then
            type=$(basename $config_path | cut -d "." -f 1)
            git ls-remote $trimmed_url &> /dev/null
            if [[ $? -eq 0 ]]; then
              #this is a git repo
              branch=$(echo "$line" | grep -q "#" && echo "$line" | cut -d "#" -f 2)
              echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
              if [[ $type == "webui" ]]; then
                safe_git "$trimmed_url" $(assemble_target_path $type) ${branch:+$branch}
                break
              else
                safe_git "$trimmed_url" $(assemble_target_path $type)/$base_name ${branch:+$branch}
              fi
            else
              echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
              safe_fetch $trimmed_url $(assemble_target_path $type) $base_name
            fi
          fi
      done
    fi
}

function prepare_pip_deps {
    pip install -q torch==2.0.0+cu118 torchvision==0.15.1+cu118 torchaudio==2.0.1+cu118 torchtext==0.15.1 torchdata==0.6.0 --extra-index-url https://download.pytorch.org/whl/cu118 -U
    pip install -q xformers==0.0.18 triton==2.0.0 -U
}

function prepare_fuse_dir {
    #Prepare drive fusion MOVE THIS TOLATER
    mkdir /content/fused-models
    mkdir /content/models
    mkdir /content/fused-lora
    mkdir /content/lora
    unionfs-fuse $BASEPATH/models/Stable-diffusion=RW:/content/models=RW /content/fused-models
    unionfs-fuse $BASEPATH/extensions/sd-webui-additional-networks/models/lora=RW:$BASEPATH/models/Lora=RW:/content/lora=RW /content/fused-lora
}

function install {
    #Prepare runtime
    component_types=( "webui" "extensions" "scripts" "embeddings" "ESRGAN_models" "checkpoints" "hypernetworks" "lora" "lycoris" "vae" "clip" "cn_models" )
    for component_type in "${component_types[@]}"
    do
      template_path=$1
      config_path=$template_path/$component_type.txt
      echo $config_path
      if [[ -f $config_path ]]; then
        install_from_template $config_path
      fi
    done

    reset_repos $BASEPATH all

    #Install Dependencies
    sed_for installation $BASEPATH
    cd $BASEPATH && python launch.py --skip-torch-cuda-test && echo "Installation Completed" > $BASEPATH/.install_status
}

function get_url_info {
  if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Error: get_url_info params are empty."
    return 1
  fi
  file="$1"
  type="$2"
  idx="$3"
  cmdstr="import down_util;print(down_util.check_down('${file}', '${type}', ${idx}))"
  res=$(python -c "$cmdstr")

  filename=$(echo $res | awk -F"[<]" '{print $1}')
  url=$(echo $res | awk -F"[<]" '{print $2}')
  local_size=$(echo $res | awk -F"[<]" '{print $3}')
  remote_size=$(echo $res | awk -F"[<]" '{print $4}')
  local_size=$((local_size))
  remote_size=$((remote_size))
}

function install_json {
    #Prepare runtime
    component_types=( "webui" "extensions" "scripts" "embeddings" "esrgans" "checkpoints" "hypernetworks" "loras" "lycoris" "vaes" "clips" "controlnets" )
    wget -qO down_util.py 'https://raw.githubusercontent.com/o0o52lin/easy-sd-to-colab/main/down_util.py'
    for component_type in "${component_types[@]}"
    do
#       num=$(python -c "import down_util;print(down_util.get_num('$JSON_CONFIG_FILE', '$component_type', 0))")
#       num=$((num))

#       if [ "$component_type" = "webui" ]; then
#         type="webui"
#         res=($(echo get_url_info $JSON_CONFIG_FILE $component_type 0)))
#         url=$res[1]
#         branch=$(echo "$url" | grep -q "#" && echo "$url" | cut -d "#" -f 2)
#         echo "->branch:$branch"
#         echo "->url:$url"
#         echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
#         safe_git "$url" $(assemble_target_path $type) ${branch:+$branch}
#       elif  [[ "$component_type" = "extensions" || "$component_type" = "scripts" ]]; then
#         for i in $(seq 1 $num)
#         do
# #           res=($(echo get_url_info $JSON_CONFIG_FILE $component_type 0)))
#         done
#       else

#       fi


      json_var="JSON_${component_type^^}"
      json_var_val=$(cat $JSON_CONFIG_FILE | jq -r ".$component_type")
      var_cmd="${json_var}=\"${json_var_val}\""
      # eval $var_cmd

      echo "$json_var_val"
      if [ "$component_type" = "webui" ]; then
        type="webui"
        branch=$(echo "$url" | grep -q "#" && echo "$url" | cut -d "#" -f 2)
        url=$(echo $json_var_val)
        
        echo "->branch:$branch"
        echo "->url:$url"
        echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
        safe_git "$url" $(assemble_target_path $type) ${branch:+$branch}
      elif  [ "$component_type" = "checkpoints" ]; then
        type="checkpoint"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      elif  [ "$component_type" = "embeddings" ]; then
        type="embedding"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      elif  [ "$component_type" = "loras" ]; then
        type="lora"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      elif  [ "$component_type" = "vaes" ]; then
        type="vae"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      elif  [ "$component_type" = "controlnets" ]; then
        type="controlnet"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      elif  [ "$component_type" = "extensions" ]; then
        type="extension"
        for one in $(echo "${json_var_val}" | jq -r '.[]'); do
          url=${one}
          base_name=$(basename $url)
          echo "->base_name: $base_name"
          echo "->url: $url"
          git ls-remote $url &> /dev/null
          if [[ $? -eq 0 ]]; then
            #this is a git repo
            branch=$(echo "$url" | grep -q "#" && echo "$url" | cut -d "#" -f 2)
            echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
            safe_git "$url" $(assemble_target_path $type)/$base_name ${branch:+$branch}
          else
            echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
            safe_fetch $url $(assemble_target_path $type) $base_name
          fi
        done
      elif  [ "$component_type" = "scripts" ]; then
        type="script"
        for one in $(echo "${json_var_val}" | jq -r '.[]'); do
          url=${one}
          base_name=$(basename $url)
          echo "->base_name: $base_name"
          echo "->url: $url"
          git ls-remote $url &> /dev/null
          if [[ $? -eq 0 ]]; then
            #this is a git repo
            branch=$(echo "$url" | grep -q "#" && echo "$url" | cut -d "#" -f 2)
            echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
            safe_git "$url" $(assemble_target_path $type)/$base_name ${branch:+$branch}
          else
            echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
            safe_fetch $url $(assemble_target_path $type) $base_name
          fi
        done
      elif  [ "$component_type" = "hypernetworks" ]; then
        echo "Usage: hypernetworks not done:$component_type"
      elif  [ "$component_type" = "lycoris" ]; then
        echo "Usage: lycoris not done:$component_type"
      elif  [ "$component_type" = "esrgans" ]; then
        type="esrgan"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      elif  [ "$component_type" = "clips" ]; then
        type="clip"
        # 使用 jq 解析 JSON 数据
        for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
          # 解码 base64 编码的 JSON 数据
          _jq() {
              echo "${one}" | base64 --decode | jq -r "${1}"
          }

          base_name=$(_jq '.filename')
          url=$(_jq '.url')

          if [[ ! -z $base_name ]]; then
            base_name=$(basename $url)
          fi
          echo "->base_name: $base_name"
          echo "->url: $url"

          echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
          safe_fetch $url $(assemble_target_path $type) $base_name
        done
      fi

    done

    reset_repos $BASEPATH all

    #Install Dependencies
    sed_for installation $BASEPATH
    cd $BASEPATH && python launch.py --skip-torch-cuda-test && echo "Installation Completed" > $BASEPATH/.install_status
}

function install_webui {
    type="webui"
    json_var_val="$1"
    if [ "$json_var_val" = false ]; then
      echo "Error: $FINAL_JSON not contain $type."
      return 1
    fi
    branch=$(echo $json_var_val | jq -r '.branch')
    url=$(echo $json_var_val | jq -r '.url')
    echo "->JSON_WEBUI:$json_var_val"
    echo "->branch:$branch"
    echo "->url:$url"
    echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
    safe_git "$trimmed_url" $(assemble_target_path $type) ${branch:+$branch}
}
function install_array_config {
  if [[ -z "$1" ]]; then
    echo "Error: install_array_object first param is empty."
    return 1
  fi
  type="$1"
  array_object="$2"
  for one in $(echo "${array_object}" | jq -r '.[]'); do
    url=${one}
    base_name=$(basename $url)
    echo "->base_name: $base_name"
    git ls-remote $url &> /dev/null
    if [[ $? -eq 0 ]]; then
      #this is a git repo
      branch=$(echo "$url" | grep -q "#" && echo "$url" | cut -d "#" -f 2)
      echo "->This is a $type component Git repo with branch $branch, will be saved to $(assemble_target_path $type)"
      safe_git "$url" $(assemble_target_path $type)/$base_name ${branch:+$branch}
    else
      echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
      safe_fetch $url $(assemble_target_path $type) $base_name
    fi
  done
}
function install_array_object_config {
  if [[ -z "$1" ]]; then
    echo "Error: install_array_object first param is empty."
    return 1
  fi
  type="$1"
  array_object="$2"
  # 使用 jq 解析 JSON 数据
  for one in $(echo "${array_object}" | jq -r '.[] | @base64'); do
    # 解码 base64 编码的 JSON 数据
    _jq() {
        echo "${one}" | base64 --decode | jq -r "${1}"
    }

    base_name=$(_jq '.filename')
    url=$(_jq '.url')

    if [[ ! -z $base_name ]]; then
      base_name=$(basename $url)
    fi
    echo "->base_name: $base_name"

    echo "->This is a $type component file, will be saved to $(assemble_target_path $type)"
    safe_fetch $url $(assemble_target_path $type) $base_name
  done
}
function install_checkpoints {
  type="checkpoint"
  json_var_val="$1"
  if [ "$json_var_val" = false ]; then
    echo "Error: $FINAL_JSON not contain $type."
    return 1
  fi
  install_array_object_config "checkpoint" "$json_var_val"
}
function install_embeddings {
  type="embedding"
  json_var_val="$1"
  if [ "$json_var_val" = false ]; then
    echo "Error: $FINAL_JSON not contain $type."
    return 1
  fi
  install_array_object_config "embedding" "$json_var_val"
}
function install_loras {
  type="lora"
  json_var_val="$1"
  if [ "$JSON_LORAS" = false ]; then
    echo "Error: $FINAL_JSON not contain $type."
    return 1
  fi
  install_array_object_config "lora" "$json_var_val"
}
function install_vaes {
  type="vae"
  json_var_val="$1"
  if [ "$JSON_VAES" = false ]; then
    echo "Error: $FINAL_JSON not contain $type."
    return 1
  fi
  install_array_object_config "vae" "$json_var_val"
}
function install_extensions {
  type="extension"
  json_var_val="$1"
  if [ "$JSON_EXTENSIONS" = false ]; then
    echo "Error: $FINAL_JSON not contain $type."
    return 1
  fi
  install_array_config "extension" "$json_var_val"
}
function install_scripts {
  type="script"
  json_var_val="$1"
  if [ "$JSON_SCRIPTS" = false ]; then
    echo "Error: $FINAL_JSON not contain $type."
    return 1
  fi
  install_array_config "script" "$json_var_val"
}
function install_esrgans {
  echo "Usage: install_esrgans not done:$JSON_ESRGANS"
}
function install_hypernetworks {
  echo "Usage: install_hypernetworks not done:$JSON_HYPERNETWORKS"
}
function install_lycoris {
  echo "Usage: install_lycoris not done:$JSON_LYCORIS"
}
function install_controlnets {
  echo "Usage: install_controlnets not done:$JSON_CONTROLNETS"
}
function install_clips {
  echo "Usage: install_clips not done:$JSON_CLIPS"
}

function run {
    #Install google perf tools
    prepare_perf_tools

    prepare_pip_deps
    prepare_fuse_dir

    #Healthcheck and update all repos
    reset_repos $BASEPATH

    #Prepare for running
    sed_for run $BASEPATH

    cd $BASEPATH && python launch.py --listen --share --xformers --enable-insecure-extension-access --theme dark --clip-models-path $BASEPATH/models/CLIP
}

BASEPATH=/content/drive/MyDrive/SD
if [ ! -d "/opt/SD" ]; then
  mkdir "/opt/SD"
fi
if [ ! -d $BASEPATH ]; then
  mkdir $BASEPATH
fi
mount --bind '/opt/SD' $BASEPATH
TEMPLATE_LOCATION="https://github.com/o0o52lin/easy-sd-to-colab"
TEMPLATE_TYPE="dir"
TEMPLATE_NAME="default"

export JSON_WEBUI=false
export JSON_EXTENSIONS=false
export JSON_SCRIPTS=false
export JSON_EMBEDDINGS=false
export JSON_ESRGANS=false
export JSON_CHECKPOINTS=false
export JSON_HYPERNETWORKS=false
export JSON_LORAS=false
export JSON_LYCORIS=false
export JSON_VAES=false
export JSON_CLIPS=false
export JSON_CONTROLNETS=false
export JSON_CONFIG=""
export JSON_CONFIG_FILE=""

while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -f|--force-install)
        FORCE_INSTALL=true
        shift
        ;;
        -l|--template-location)
        TEMPLATE_LOCATION="$2"
        git ls-remote $TEMPLATE_LOCATION &> /dev/null
        if [[ $? -ne 0 && ! -d $TEMPLATE_LOCATION ]]; then
          echo "Error: Specified template location is neither a valid git repo, nor a valid local path: $TEMPLATE_LOCATION"
          exit 1
        fi
        shift 
        shift
        ;;
        -n|--template-name)
        TEMPLATE_NAME="$2"
        shift
        shift
        ;;
        -t|--template-type)
        TEMPLATE_TYPE="$2"
        shift
        shift
        ;;
        -i|--install-path)
        BASEPATH="$2"
        shift
        shift
        ;;
        *)
        echo "Usage: $0 [-f|--force-install] [-l|--template-location <git repo|directory>] [-n|--template-name <name>] [-i|--install-path <directory>]"
        echo "Options:"
        echo "-f, --force-install          Force reinstall"
        echo "-l, --template-location      Location of the template repo or local directory (default: https://github.com/o0o52lin/easy-sd-to-colab)"
        echo "-n, --template-name          Name of the template to install (default: templates/default)"
        echo "-t, --template-type          Type of the template (default: file)"
        echo "-i, --install-path           Path to install SD (default: /content/drive/MyDrive/SD)"
        exit 1
        ;;
    esac
done

if [[ -z "$FORCE_INSTALL" ]]; then FORCE_INSTALL=false; fi

git ls-remote $TEMPLATE_LOCATION &> /dev/null
if [[ $? -eq 0 ]]; then
  #location is a git repo
  TEMPLATE_PATH=/tmp/$(basename $TEMPLATE_LOCATION)
  safe_git $TEMPLATE_LOCATION $TEMPLATE_PATH
else
  TEMPLATE_PATH=$TEMPLATE_LOCATION
fi

if [ "$TEMPLATE_TYPE" = "file" ]; then

  if [[ "$TEMPLATE_NAME" == *.json ]]; then
    TEMPLATE_NAME=${TEMPLATE_NAME%.json}
  fi
  TEMPLATE_NAME="$TEMPLATE_NAME.json"

  echo $(find "$TEMPLATE_PATH" -maxdepth 2 -type f -name "$TEMPLATE_NAME" -print -quit)
  JSON_CONFIG_FILE=$(find "$TEMPLATE_PATH" -maxdepth 2 -type f -name "$TEMPLATE_NAME" -print -quit)
  if [ -z $JSON_CONFIG_FILE ]; then
    echo "Error: $TEMPLATE_PATH does not contain a template named $TEMPLATE_NAME. Please confirm you have correctly specified template location and template name."
    exit 1
  fi

  echo "FORCE_INSTALL: $FORCE_INSTALL"
  echo "TEMPLATE_LOCATION: $TEMPLATE_LOCATION"
  echo "TEMPLATE_NAME: $TEMPLATE_NAME"
  echo "FINAL_JSON: $JSON_CONFIG_FILE"

  #Update packages
  apt -y update -qq && apt -y install -qq unionfs-fuse libcairo2-dev pkg-config python3-dev aria2

  if ! command -v jq &> /dev/null
  then
    echo "jq not found, installing..."
    apt -y install jq
  fi

  if [ "$FORCE_INSTALL" = true ] || [ ! -e "$BASEPATH/.install_status" ] || ! grep -qs "Installation Completed" "$BASEPATH/.install_status"; then
      install_json
  fi
else
  echo $(find "$TEMPLATE_PATH" -maxdepth 2 -type d -name "$TEMPLATE_NAME" -print -quit)
  FINAL_PATH=$(find "$TEMPLATE_PATH" -maxdepth 2 -type d -name "$TEMPLATE_NAME" -print -quit)
  if [ -z $FINAL_PATH ]; then
    echo "Error: $TEMPLATE_PATH does not contain a template named $TEMPLATE_NAME. Please confirm you have correctly specified template location and template name."
    exit 1
  fi

  echo "FORCE_INSTALL: $FORCE_INSTALL"
  echo "TEMPLATE_LOCATION: $TEMPLATE_LOCATION"
  echo "TEMPLATE_NAME: $TEMPLATE_NAME"
  echo "FINAL_PATH: $FINAL_PATH"

  #Update packages
  apt -y update -qq && apt -y install -qq unionfs-fuse libcairo2-dev pkg-config python3-dev aria2

  if [ "$FORCE_INSTALL" = true ] || [ ! -e "$BASEPATH/.install_status" ] || ! grep -qs "Installation Completed" "$BASEPATH/.install_status"; then
      install $FINAL_PATH
  fi
fi

run
