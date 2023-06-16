#!/bin/bash

checkpoints='[
   {
      "filename":"majicmixRealistic_v6.2",
      "url": "https://civitai.com/api/download/models/1"
   },
   {
      "filename":"majicmixRealistic_v6.safetensors",
      "url": "https://civitai.com/api/download/models/2"
   }
]'

# 使用 jq 解析 JSON 数据
for checkpoint in $(echo "${checkpoints}" | jq -r '.[] | @base64'); do
    # 解码 base64 编码的 JSON 数据
    _jq() {
        echo "${checkpoint}" | base64 --decode | jq -r "${1}"
    }

    filename=$(_jq '.filename')
    url=$(_jq '.url')

    echo "filename: ${filename}, url: ${url}"
done
