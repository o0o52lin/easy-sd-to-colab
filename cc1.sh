#!/bin/bash

# 解析 JSON 数据并获取 webui 对象
B="/tmp/easy-sd-to-colab/templates/default.json"
A=$(cat $B | jq '.webui')

# 从 webui 对象中获取 branch 和 url
BRANCH=$(echo $A | jq -r '.branch')
URL=$(echo $A | jq -r '.url')

# 输出结果
echo "Branch: $BRANCH"
echo "URL: $URL"
