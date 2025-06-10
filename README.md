# Scripts

This repository contains a collection of scripts and utilities. Some are generic enough to be useful to many others. Some are highly specific and might not be useful to anyone else at all. Many were created with the help of an AI model, typically Grok 2, Grok 3 or one of the Claude variants. They're pretty good at sorting out things like awk parameters or handling formatting of numbers and dates - not exactly BASH's strong suit after all.

## Files

These scripts help analyze and manage files and directories:

- [Find Oldest](https://github.com/500Foods/Scripts/blob/main/files/findoldest.md) - Find oldest files in a directory tree with detailed stats and date filtering (BASH)
- [Top Files](https://github.com/500Foods/Scripts/blob/main/files/topfiles.md) - List largest files (>1MB) in a directory tree (Python)
- [Top Directories](https://github.com/500Foods/Scripts/blob/main/files/topdirs.md) - List directories by total size in MB (Python)
- [Top Counts](https://github.com/500Foods/Scripts/blob/main/files/topcounts.md) - List directories containing the most files (Python)

## Dates

These scripts help with date and time operations:

- [Uptime Fancy](https://github.com/500Foods/Scripts/blob/main/dates/uptime-fancy.md) - Show system uptime with week number in a compact format (BASH)
- [Week Number](https://github.com/500Foods/Scripts/blob/main/dates/weeknumber.md) - Calculate ISO week numbers with formatted date output (Python)

## GitHub

These tools help manage GitHub repositories:

- [GitHubSync](https://github.com/500Foods/Scripts/blob/main/githubsync/githubsync.md) - Sync GitHub repositories with local copies, mostly intended as a backup mechanism (BASH)
- [CLOC](https://github.com/500Foods/Scripts/blob/main/cloc/cloc.md) - Add "count lines of code" to the README.md of a GitHub repository (GitHub Action)

## Repository Information

[![Count Lines of Code](https://github.com/500Foods/Scripts/actions/workflows/main.yml/badge.svg)](https://github.com/500Foods/Scripts/actions/workflows/main.yml)
<!--CLOC-START -->
```cloc
Last updated at 2025-06-10 03:28:26 UTC
-------------------------------------------------------------------------------
Language                     files          blank        comment           code
-------------------------------------------------------------------------------
Bourne Shell                    13            601            557           3214
Markdown                         9            326              4            887
Python                           4             56              1            112
YAML                             3             16             26             72
-------------------------------------------------------------------------------
SUM:                            29            999            588           4285
-------------------------------------------------------------------------------
4 Files were skipped (duplicate, binary, or without source code):
  gitattributes: 1
  gitignore: 1
  license: 1
  txt: 1
```
<!--CLOC-END-->

## Sponsor / Donate / Support

If you find this work interesting, helpful, or valuable, or that it has saved you time, money, or both, please consider directly supporting these efforts financially via [GitHub Sponsors](https://github.com/sponsors/500Foods) or donating via [Buy Me a Pizza](https://www.buymeacoffee.com/andrewsimard500). Also, check out these other [GitHub Repositories](https://github.com/500Foods?tab=repositories&q=&sort=stargazers) that may interest you.
