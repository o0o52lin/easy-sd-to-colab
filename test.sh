#!/bin/bash

url='https://civitai.com/api/download/models/66043'
location=$(curl -Is -X GET "$url" | grep -i location | awk '{print $2}')
if [[ ! -z $location ]]; then
  url=$(echo -e "$location" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n')
fi
cmd='curl -Is -X "GET" "<url>"'
header=$(eval ${cmd/<url>/$url})
header=$(echo "$header" | tr '[:upper:]' '[:lower:]')
remote_size=$(echo "$header" | awk '/content-length/ {clen=$2} /x-linked-size/ {xsize=$2} END {if (xsize) print xsize; else print clen;}' | tr -dc '0-9' || echo '')
local_size=0
echo "LOCAL_SIZE: $local_size"
echo "REMOTE_SIZE: $remote_size"
if [[ $local_size != 0 ]] && [[ "$local_size" -eq "$remote_size" ]]; then
  echo "INFO: local file '$output_filename' is up-to-date, skipping download"
  return 0
fi