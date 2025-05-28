#!/usr/bin/env python3

import os
import sys

def get_dir_sizes(start_dir, num_dirs):

  sizes = []

  for root, dirs, filenames in os.walk(start_dir):

    size = 0
    for filename in filenames:
      file_path = os.path.join(root, filename)
      try:
        size += os.path.getsize(file_path) / (1024 * 1024)
      except FileNotFoundError:
        pass

    sizes.append((size, root))
    sizes.sort(key=lambda f: f[0], reverse=True)
    sizes = sizes[:num_dirs]

  return sizes

if __name__ == "__main__":

  if len(sys.argv) != 3:
    print("Usage: topdirs <num_dirs> <start_dir>", file=sys.stderr)
    sys.exit(1)

  print("{:>5}  {:>5}  {}".format("Index", "Size (MB)", "Directory"))

  num_dirs = int(sys.argv[1])
  start_dir = sys.argv[2]

  sizes = get_dir_sizes(start_dir, num_dirs)

  for i, (size, path) in enumerate(sizes, 1):
    print("{:>5} {:>10.1f}  {}".format(i, size, path))  
