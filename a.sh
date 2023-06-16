#!/bin/bash
#判断是否安装 json解析工具“jq”
echo  `command -v jq`
if [ `command -v jq` ];then
    echo 'jq 已经安装'
else
    echo 'jq 未安装,开始安装json解析工具'
    #安装jq
    apt -y install jq
fi
