# GitHub Sitemap Script

## Overview

**github-sitemap.sh** is a sophisticated Bash script meticulously developed to enhance the maintenance of documentation within a GitHub repository. This tool addresses the critical need for ensuring the integrity of markdown links, a common challenge in large documentation projects. By automating the process of link checking and file relationship mapping, it saves developers significant time and effort in keeping their repository's documentation accurate and accessible.

## Core Functionality

The script offers a robust set of features designed to provide a comprehensive analysis of markdown files:

- **Markdown Link Checking**: It scans markdown files to extract local links, meticulously verifying their existence. Any broken or missing links are flagged, allowing developers to quickly address issues that could frustrate users or disrupt navigation within the documentation.
- **Orphaned File Detection**: The script identifies markdown files that are not linked to by any other markdown file in the repository. This feature helps uncover "orphaned" documentation that might otherwise be overlooked, ensuring all content remains relevant and connected.
- **Detailed Reporting**: After analysis, it generates structured reports and visually appealing tables that summarize the status of links and highlight orphaned files. These reports are invaluable for repository maintainers, providing clear insights into the health of their documentation structure.
- **Customizable Output**: With options like `--debug` for verbose logging, `--quiet` to suppress non-essential output, `--noreport` to skip report file creation, and `--theme` to adjust table aesthetics (Red or Blue), the script caters to varied user preferences and use cases.

## Development Journey

The development of `github-sitemap.sh` reflects a commitment to continuous improvement, as evidenced by its detailed change history:

- **Version 0.4.0 (2025-06-19)**: Updated link checking to recognize existing folders as valid links, enhancing accuracy.
- **Version 0.3.9 (2025-06-15)**: Fixed repository root detection to use the input file's directory, improving path resolution.
- **Version 0.3.7 (2025-06-15)**: Optimized file discovery with pruning for `.git` directories, refining orphaned file detection.
- **Version 0.3.0 (2025-06-15)**: Introduced debug capabilities for detailed logging, bolstering robustness.
- **Version 0.2.0 (2025-06-15)**: Added table output for better visualization, along with issue counts and detailed tables for missing links and orphaned files.
- **Initial Version 0.1.0 (2025-06-15)**: Laid the foundation with basic link checking and summary output.

This iterative development process, with multiple updates often on the same day, showcases the dedication to refining the tool's functionality and user experience. Each version builds upon the last, addressing bugs, optimizing performance, and adding features based on real-world usage and feedback.

## Technical Sophistication

Under the hood, `github-sitemap.sh` employs advanced Bash scripting techniques, including associative arrays for tracking checked files, regular expressions for link extraction, and path resolution logic to handle both relative and absolute links. It integrates with external tools like `jq` for JSON processing and a custom `tables.sh` script for rendering output tables. The script also includes error handling, timeout mechanisms for file discovery, and dependency checks to ensure reliable operation across different environments.

## Value to Developers

For developers, this tool is more than just a utility—it's a vital asset for maintaining high-quality documentation. Broken links and orphaned files can erode trust in a repository, making it difficult for users to navigate and find relevant information. `github-sitemap.sh` mitigates these issues by providing actionable insights, enabling developers to focus on coding rather than manual documentation checks. Whether you're managing a small project or a sprawling repository, this script ensures your markdown content remains a seamless, interconnected web of knowledge.

By using `github-sitemap.sh`, developers can appreciate the meticulous effort invested in creating a tool that not only solves a practical problem but does so with elegance, configurability, and a clear focus on user needs.
