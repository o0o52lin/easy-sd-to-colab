#!/bin/bash

json='{
   "checkpoints": [
      {
         "filename":"majicmixRealistic_v6.safetensors",
         "url": "https://civitai.com/api/download/models/94640"
      }
   ]
}'

echo $json | jq -r '.checkpoints[] | "\(.filename) \(.url)"'
