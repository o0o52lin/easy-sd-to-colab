#!/bin/bash
url='https://civitai.com/api/download/models/66043'
location=$(curl -Is -X GET "$url" | grep -i location | awk '{print $2}')
if [[ ! -z $location ]]; then
  url=$location
fi
echo "url: $url"
header=$(curl -Is -X GET $url)
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
curl -Is -X "GET" "https://civitai-delivery-worker-prod-2023-06-01.5ac0637cfd0766c97916cefa3764fbdf.r2.cloudflarestorage.com/749997/model/badPictures.Vlw2.pt?X-Amz-Expires=86400&response-content-disposition=attachment%3B%20filename%3D%22bad_pictures.pt%22&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=2fea663d76bd24a496545da373d610fc/20230625/us-east-1/s3/aws4_request&X-Amz-Date=20230625T055636Z&X-Amz-SignedHeaders=host&X-Amz-Signature=f6ac4d50328cd8d58cc97aa2ebd9fa9fb7e9b358bfb245a52f349bcdc6abd589"
