import requests
import os
import json
import re
import sys
import subprocess

def is_git_repo(directory):
  git_dir = os.path.join(directory, '.git')
  return os.path.isdir(git_dir)

def check_url(url):
  curl_command = "curl -I -X GET '"+url+"'"
  result = subprocess.run(curl_command, shell=True, capture_output=True, text=True)

  # 从结果中提取响应头信息
  arr = result.stdout.split('\n\n')[0]
  pattern = r"(?:L|l)ocation: (.*)\n"
  matched = re.findall(pattern, arr)

  location=matched[0] if len(matched) > 0 else ''
  l=re.sub(r"Signature=[^&]+$", '', location)
  l=re.sub(r"&X-Amz-Date=[^&]+&", '&', l)
  u=re.sub(r"Signature=[^&]+$", '', url)
  u=re.sub(r"&X-Amz-Date=[^&]+&", '&', u)

  location = "" if l == u else location

  return location
def get_header_content_length(url):
  curl_command = "curl -I -X GET '"+url+"'"
  result = subprocess.run(curl_command, shell=True, capture_output=True, text=True)
  arr = result.stdout.split('\n\n')[0]
  
  pattern = r"(?:c|C)ontent-(?:l|L)ength: (.*)\n"
  matched = re.findall(pattern, arr)

  val=int(matched[0]) if len(matched) > 0 else 0

  return val

def get_remote_file_size(url):
  location = check_url(url)
  print(f'location: {location}')
  while len(location) > 0:
    l = location
    location = check_url(location)
    if len(location) <= 0:
      url = l
  return get_header_content_length(url)

def get_num(config_file, type):
  with open(config_file) as f:
    data = json.load(f)
    num = len(data[type])

  return 1 if 'webui' == type else len(data[type])

def check_down(config_file, type, idx):
  with open(config_file) as f:
    data = json.load(f)
  if 'webui' == type:
    return "<"+data[type]+"<0<0"
  elif type in ["extensions", "scripts"]:
    return "<"+data[type][idx]+"<0<0"
  else:
    if len(data[type]) > 0 and data[type][idx]['url']:
      filename = data[type][idx]['filename'] if 'filename' in data.get(type, {}) and data[type]['filename'] else ''
      url = data[type][idx]['url']
      if os.path.isfile(filename):
        local_size = os.path.getsize(filename)
        remote_size = get_remote_file_size(url)
        if local_size == remote_size:
          return filename+"<<"+str(local_size)+"<"+str(remote_size)
        else:
          return filename+"<"+url+"<"+str(local_size)+"<"+str(remote_size)
      else:
        return filename+"<"+url+"<0<1"
    else:
      return "<<0<0"