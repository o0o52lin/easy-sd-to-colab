import requests
import os
import json
import re
import sys
import subprocess

config_file = None
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

def checkDown(type, idx):
  with open('default.json') as f:
      data = json.load(f)
  num = len(data[type])
  filename = data[type][idx]['filename']
  url = data[type][idx]['url']
  
  if os.path.isfile(filename):
    print(f"{filename} already exists, check if an update is needed...")
    # Check file size
    local_size = os.path.getsize(filename)
    print(f"->local size:{local_size}")
    remote_size = get_remote_file_size(url)
    print(f"->remote size:{remote_size}")
    if local_size == remote_size:
      print(f"{filename} is up to date.")
    else:
      print(f"{filename} is outdated. Downloading...")

  return filename, url, num

def init(p, func):
  global config_file
  config_file = p
  print(f"{config_file} is the path.")
  func = getattr(__main__, func)
  func()
  
def test():
  print(f"path is {config_file}.")
