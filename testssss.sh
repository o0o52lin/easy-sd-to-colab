#!/bin/bash
url='https://civitai.com/api/download/models/66043'
location=$(curl -Is -X GET "$url" | grep -i location | awk '{print $2}')
if [[ ! -z $location ]]; then
  url=$location
fi
echo "url: $url"
a='curl -Is -X "GET" "<url>"'
a=${a/<url>/$url}
echo $a
header=$(curl -Is -X "GET" $url)
echo "header:$header"
header=$(echo "$header" | tr '[:upper:]' '[:lower:]')
echo "header2:$header"
remote_size=$(echo "$header" | awk '/content-length/ {clen=$2} /x-linked-size/ {xsize=$2} END {if (xsize) print xsize; else print clen;}' | tr -dc '0-9' || echo '')
local_size=0
echo "LOCAL_SIZE: $local_size"
echo "REMOTE_SIZE: $remote_size"
if [[ $local_size != 0 ]] && [[ "$local_size" -eq "$remote_size" ]]; then
  echo "INFO: local file '$output_filename' is up-to-date, skipping download"
  return 0
fi
curl -Is -X "GET" "$url"
