#!/usr/bin/env python3

import os
import sys

def get_dir_counts(start_dir, num_dirs):

  counts = []

  for root, dirs, filenames in os.walk(start_dir):

    count = len(filenames) 

    counts.append((count, root))
    counts.sort(key=lambda f: f[0], reverse=True)
    counts = counts[:num_dirs]

  return counts

if __name__ == "__main__":

  if len(sys.argv) != 3:
    print("Usage: topcounts <num_dirs> <start_dir>", file=sys.stderr)
    sys.exit(1)

  print("{:>5}  {:>5}  {}".format("Index", "Counts", "Directory"))

  num_dirs = int(sys.argv[1])
  start_dir = sys.argv[2]  

  counts = get_dir_counts(start_dir, num_dirs)

  for i, (count, path) in enumerate(counts, 1):
    print("{:>5} {:>7}  {}".format(i, count, path)) 
