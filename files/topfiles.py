#!/usr/bin/env python3

import os
import sys

MIN_FILE_SIZE = 1.0 # 1 MB

def find_large_files(start_dir, max_files):

  files = []

  for root, dirs, filenames in os.walk(start_dir):
    for filename in filenames:

      file_path = os.path.join(root, filename)

      try:
        size_bytes = os.path.getsize(file_path)
        size_mb = size_bytes / (1024 * 1024)

        if size_mb >= MIN_FILE_SIZE:
          files.append((size_mb, file_path))

        if len(files) >= max_files:
          files.sort(key=lambda f: f[0], reverse=True)
          files = files[:max_files]
            
      except FileNotFoundError:
        pass
        
  return files

def get_top_n(files, n):

  files.sort(key=lambda f: f[0], reverse=True)

  return files[:n]

if __name__ == "__main__":

  if len(sys.argv) != 3:
    print("Usage: topfiles <num_files> <start_dir>", file=sys.stderr)
    sys.exit(1)

  print("{:>5}  {:>5}  {}".format("Index", "Size (MB)", "Filename"))

  num_files = int(sys.argv[1])
  start_dir = sys.argv[2]

  files = find_large_files(start_dir, num_files)

  for i, (size, path) in enumerate(get_top_n(files, num_files), 1):
    print("{:>5} {:>10.1f}  {}".format(i, size, path))
