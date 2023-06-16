#!/bin/bash
if ! command -v jq &> /dev/null
then
  echo "jq not found, installing..."
  apt -y install jq
else
  echo "jq ok"
fi
JSON_WEBUI="{\"webui\":{\"url\":\"http\"}}"
echo $("$JSON_WEBUI" | jq -r '.webui.url')
