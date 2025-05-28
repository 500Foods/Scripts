# GitHubSync

GitHubSync is a robust solution for maintaining synchronized copies of GitHub repositories locally. Think of it as an automated backup system that keeps your GitHub projects safely stored on your local machine, always up to date with the latest changes.

## Quick Start Guide

1. **First-Time Setup**:
   ```bash
   # Clone this repository
   git clone git@github.com:500Foods/Scripts.git
   cd Scripts/githubsync

   # Make scripts executable
   chmod +x githubsync.sh sync_all.sh

   # Setup SSH (if needed)
   ssh-keygen -t rsa -b 4096
   ```

2. **Basic Usage**:
   ```bash
   # Single repository backup
   ./githubsync.sh owner/repo R /backup/path

   # Multiple repositories (create repos.txt first)
   ./sync_all.sh repos.txt
   ```

3. **Verify It's Working**:
   ```bash
   # Check the logs
   tail -f ~/githubsync_logs/githubsync_*.log

   # List synchronized files
   ls -la /backup/path
   ```

### Common Commands Explained

```bash
# View last 10 lines of log file (monitoring)
tail -f logfile.log

# Check disk space usage
du -sh /path/to/repos/*

# List all repositories
ls -l /path/to/repos

# Check SSH connection
ssh -T git@github.com

# View cron jobs
crontab -l

# Edit cron jobs
crontab -e
```

## Getting Started

### Basic Concepts

1. **What is Repository Synchronization?**
   - A repository (or "repo") is where your code lives on GitHub
   - Synchronization means keeping a local copy matched with the GitHub version
   - Think of it like having a backup that stays up-to-date automatically

2. **Access Modes Explained**:
   - Read-only (R): Only downloads changes from GitHub (like making a backup)
   - Read-write (RW): Can both download and upload changes (for active development)

3. **What You'll Need**:
   - A GitHub account
   - Basic command line familiarity
   - SSH access to GitHub (we'll help you set this up)
   - Email setup for notifications (optional)

### Initial Setup Guide

1. **Setting up SSH for GitHub**:
   ```bash
   # Generate an SSH key (press Enter for default options)
   ssh-keygen -t rsa -b 4096 -C "your.email@example.com"

   # Start the SSH agent (this helps manage your SSH keys)
   eval "$(ssh-agent -s)"

   # Add your key to the agent
   ssh-add ~/.ssh/id_rsa

   # Copy your public key (you'll add this to GitHub)
   cat ~/.ssh/id_rsa.pub
   ```
   Then:
   - Go to GitHub.com → Settings → SSH Keys
   - Click "New SSH Key"
   - Paste your key and save

4. **SSH Configuration** (Important for Custom Setups):
   ```bash
   # Create or edit SSH config file
   mkdir -p ~/.ssh
   nano ~/.ssh/config
   ```
   
   Basic SSH config for GitHub:
   ```
   # Default GitHub configuration
   Host github.com
       HostName github.com
       User git
       Port 22  # GitHub only works on port 22
       IdentityFile ~/.ssh/id_rsa
   
   # If your system uses a different default port
   Host *
       Port 964  # Your system's default port
   ```

   Additional useful SSH settings:
   ```
   Host github.com
       HostName github.com
       User git
       Port 22
       IdentityFile ~/.ssh/id_rsa
       # Connection optimization
       Compression yes
       TCPKeepAlive yes
       ServerAliveInterval 60
       ServerAliveCountMax 5
       # Security settings
       PasswordAuthentication no
       PubkeyAuthentication yes
   ```

   Save the file and set permissions:
   ```bash
   chmod 600 ~/.ssh/config
   ```

   Common issues and solutions:
   - If your system uses a non-standard SSH port (not 22), GitHub connections will fail
   - The SSH config file lets you set different ports for different hosts
   - Always use port 22 for github.com while maintaining other ports for other connections

5. **Setting up Email Notifications** (Optional):
   ```bash
   # Install mutt (email client) if needed
   # For Ubuntu/Debian:
   sudo apt-get install mutt

   # For CentOS/RHEL:
   sudo yum install mutt

   # Create basic mutt config
   echo "set from = \"your.email@example.com\"
   set smtp_url = \"smtp://smtp.gmail.com:587/\"
   set smtp_user = \"your.email@example.com\"
   set smtp_pass = \"your-app-specific-password\"" > ~/.muttrc

   # Secure the config file
   chmod 600 ~/.muttrc
   ```
   Note: For Gmail, use an App Password, not your regular password

3. **Quick Test**:
   ```bash
   # Test SSH connection to GitHub
   ssh -T git@github.com
   # You should see: "Hi username! You've successfully authenticated..."

   # Test email if configured
   echo "Test" | mutt -s "Test Email" your.email@example.com
   ```

### Understanding Cron Jobs (for Automation)

Cron is like a scheduler for your computer. It runs commands at specified times:
```bash
# Structure of a cron job:
# Minute Hour Day Month DayOfWeek Command
#   │     │    │    │      │
#   │     │    │    │      └── 0-6 (Sunday-Saturday)
#   │     │    │    └──────── 1-12 (January-December)
#   │     │    └───────────── 1-31 (Day of Month)
#   │     └──────────────── 0-23 (Hour)
#   └────────────────────── 0-59 (Minute)

# Example: Run at 2 AM every day
0 2 * * * /path/to/command

# Example: Run at 2 AM and 2 PM
0 2,14 * * * /path/to/command
```

## Features

- **Flexible Access Modes**: Support for both read-only (R) and read-write (RW) operations
- **Automatic Conflict Resolution**: Remote changes take precedence to prevent sync conflicts
- **Local Change Preservation**: Automatically stashes and reapplies local changes in RW mode
- **Detailed Logging**: Comprehensive logging of all operations with timestamps
- **Batch Processing**: Support for syncing multiple repositories via sync_all.sh
- **Email Reporting**: HTML-formatted summary reports with repository statistics
- **Repository Analytics**: Tracks repository age, activity, size, and change metrics

## Prerequisites

1. **SSH Setup**:
   - A valid SSH key pair
   - SSH key added to your GitHub account
   - SSH key loaded in ssh-agent (`~/.ssh/id_rsa`)

2. **For Email Reporting** (optional):
   - Mutt email client installed
   - Mutt configured for sending emails

## Usage

### Single Repository Sync (githubsync.sh)

```bash
./githubsync.sh <repo> <access> <local_path> [--log-dir <log_dir>]
```

Example for a Single Repository:
```bash
# Create log directory
mkdir -p ~/github_logs

# Sync the Scripts repository with read-write access
/path/to/githubsync.sh 500Foods/Scripts RW /fvl/git/500Foods/Scripts --log-dir ~/github_logs

# Check the logs
tail -f ~/github_logs/githubsync_500Foods-Scripts_*.log
```

Parameters:
- `repo`: GitHub repository in format "owner/repo"
- `access`: Access mode - "R" (read-only) or "RW" (read-write)
- `local_path`: Local directory path for the repository
- `--log-dir`: (Optional) Custom log directory path

Examples:
```bash
# Read-only sync
./githubsync.sh 500Foods/Scripts R /path/to/local/Scripts

# Read-write sync with custom log directory
./githubsync.sh 500Foods/MyApp RW /path/to/local/MyApp --log-dir /custom/log/path
```

### Multiple Repository Sync (sync_all.sh)

```bash
./sync_all.sh <repo_list_file>
```

The repo list file should contain one repository per line in the format:
```
owner/repo access local_path
```

Example repo_list.txt:
```
500Foods/Scripts R /path/to/Scripts
500Foods/MyApp RW /path/to/MyApp
```

## Configuration

### githubsync.sh Configuration
- Default log directory: `$HOME/githubsync_logs`
- SSH key path: `~/.ssh/id_rsa`

### sync_all.sh Configuration
Edit these variables at the top of sync_all.sh:
```bash
GITHUBSYNC_PATH="/path/to/githubsync.sh"  # Path to githubsync.sh
EMAIL="your@email.com"                     # Email for reports
LOG_DIR="/path/to/logs"                    # Log directory
MUTT_CMD="mutt"                           # Email command
```

## Logging and Reports

### Log Files
- Individual sync logs: `<log_dir>/githubsync_<repo>_<timestamp>.log`
- Batch sync logs: `<log_dir>/sync_all_<timestamp>.log`

## Email Reporting System

The sync_all.sh script includes a sophisticated HTML email reporting system that provides detailed insights into your repository synchronization operations.

### Email Structure and Design

1. **HTML Template**:
   - Clean, modern table-based layout
   - Responsive design for mobile viewing
   - Zebra-striped rows (every 4th row) for better readability
   - Customizable CSS styling embedded in the template

2. **Report Sections**:
   - Header with sync operation summary
   - Main data table with repository details
   - Summary statistics footer
   - Timestamp and completion status

### Repository Metrics

Each repository entry includes:
- **Age**: Project lifetime in years/months/days format
- **Activity**: Time since last modification
- **Repository**: Link to GitHub repository
- **Access Mode**: R/RW status
- **Local Path**: Synchronized directory location
- **Size**: Repository size with thousands separators
- **Changes**: Files pushed/pulled during sync
- **Duration**: Sync operation timing
- **Status**: Success/failure indication

### Summary Statistics

The report footer provides aggregate data:
- Total number of repositories
- Maximum project age
- Minimum activity period
- Combined repository size
- Total files synchronized
- Overall operation duration

### Customization Options

The email template can be customized by modifying the HTML/CSS in sync_all.sh:
```css
/* Example of built-in styles */
table { 
    border-collapse: collapse; 
    width: auto; 
    font-family: Arial, sans-serif; 
    font-size: 12px; 
}
th, td { 
    padding: 0 5px; 
    text-align: left; 
    line-height: 1.2; 
}
```

### Email Configuration

1. **Basic Setup**:
   ```bash
   EMAIL="your@email.com"     # Recipient address
   MUTT_CMD="mutt"           # Email command
   ```

2. **Advanced Options**:
   - Subject line includes timestamp and status
   - HTML content type setting
   - Support for email attachments
   - Error notification configuration

### Best Practices for Email Reporting

1. **Recipients**:
   - Use distribution lists for team notification
   - Consider separate addresses for success/failure notifications

2. **Frequency**:
   - Balance between timely updates and email volume
   - Consider consolidating reports for multiple sync operations

3. **Monitoring**:
   - Set up email filters for organization
   - Archive reports for historical tracking
   - Monitor delivery success

## Special Features

### Project Age Tracking with .project_start

The `.project_start` file is a special marker used to accurately track a project's true age, independent of Git history or file modifications.

1. **Purpose**:
   - Marks the actual project start date
   - Ensures accurate age reporting in sync reports
   - Overrides file timestamp-based age calculation

2. **Implementation**:
   ```bash
   # Create .project_start with specific date
   touch -t 202001010000 .project_start  # Sets Jan 1, 2020
   
   # Or use current date for new projects
   touch .project_start
   ```

3. **Git Configuration**:
   ```bash
   # Add to .gitignore to keep it local
   echo ".project_start" >> .gitignore
   
   # Or commit it to share project age across clones
   git add .project_start
   git commit -m "chore: add project start date marker"
   ```

4. **Usage Considerations**:
   - Add at project creation for accurate tracking
   - Use with existing projects by setting historical date
   - Choose between local or shared tracking
   - Can be used per branch for feature age tracking

5. **Best Practices**:
   - Document the rationale if setting historical date
   - Consider timezone implications
   - Use consistent date format (YYYYMMDDHHMM)
   - Include in project setup documentation

6. **Advanced Usage**:
   ```bash
   # Set specific timestamp including time
   touch -t $(date -d "2020-01-01 09:00:00" +%Y%m%d%H%M) .project_start
   
   # View current project age
   find . -name .project_start -exec stat -c %y {} \;
   ```

### Age and Activity Tracking
- **Age**: Time since project creation (uses .project_start file if present)
- **Activity**: Time since last file modification
- Format: "XyYmZd" (years, months, days)

### Size Tracking
- Repository sizes tracked in MB
- Formatted with thousands separators
- Total size calculation for all repositories

### Change Tracking
- Counts of files pushed and pulled
- Duration of sync operations
- Success/failure status for each operation

## Error Handling

The scripts include comprehensive error handling for:
- Invalid repository formats
- SSH key issues
- Directory creation failures
- Git operation failures
- Email sending failures

## Automation with Cron

### Sync Jobs

1. **Single Repository Daily Sync**
```bash
# Edit crontab
crontab -e

# Add daily sync at 2 AM
0 2 * * * /path/to/githubsync.sh 500Foods/Scripts RW /fvl/git/500Foods/Scripts --log-dir /path/to/logs
```

2. **Multiple Repositories Sync (Twice Daily)**
```bash
# Sync all repositories at 2 AM and 2 PM
0 2,14 * * * /path/to/sync_all.sh /path/to/repos.txt
```

### Log Management

1. **Weekly Log Cleanup (Keep Last 30 Days)**
```bash
# Add to crontab
0 3 * * 0 find /path/to/logs -name "githubsync_*.log" -mtime +30 -delete
0 3 * * 0 find /path/to/logs -name "sync_all_*.log" -mtime +30 -delete
```

2. **Monthly Log Archive**
```bash
# Archive logs older than 30 days to a compressed file
0 4 1 * * cd /path/to/logs && tar czf logs_$(date +\%Y\%m).tar.gz githubsync_*.log sync_all_*.log --older-than='30 days' --remove-files
```

### Cron Best Practices

1. **Stagger Job Timing**:
   - Space out jobs to avoid resource contention
   - Use random minutes (e.g., 23 2 * * *) to avoid peak times

2. **Log Rotation**:
   - Keep logs for a reasonable duration (e.g., 30-90 days)
   - Compress older logs before archiving
   - Monitor disk space usage

3. **Error Handling**:
   - Redirect cron output to a log file
   - Consider using a wrapper script for error notifications
   ```bash
   23 2 * * * /path/to/sync_all.sh /path/to/repos.txt 2>&1 | mail -s "Sync Result" admin@example.com
   ```

## Production Deployment Recommendations

### Backup Strategies

1. **Tiered Backup Approach**:
   - Primary backup: Hourly syncs for critical repositories
   - Secondary backup: Daily syncs for standard repositories
   - Archive backup: Weekly full backups with compression

2. **Backup Verification**:
   ```bash
   # Add to your sync scripts
   git fsck --full
   git gc --aggressive
   ```

3. **Disaster Recovery**:
   - Keep backup copies on different physical servers
   - Document restore procedures
   - Regular restore testing

### Large-Scale Deployment

1. **Resource Management**:
   - Use separate disk partitions for repositories
   - Monitor I/O performance
   - Consider network bandwidth usage

2. **Load Distribution**:
   ```bash
   # Example of staggered sync times in crontab
   15 */4 * * * /path/to/sync_all.sh /path/to/critical-repos.txt
   45 */6 * * * /path/to/sync_all.sh /path/to/standard-repos.txt
   ```

3. **Scaling Considerations**:
   - Split repository lists by priority
   - Use multiple sync servers for large installations
   - Implement rate limiting for API calls

### Performance Optimization

1. **Git Configuration**:
   ```bash
   # Add to your global git config
   git config --global core.compression 9
   git config --global core.bigFileThreshold 1m
   git config --global pack.windowMemory "100m"
   git config --global pack.packSizeLimit "100m"
   ```

2. **Network Optimization**:
   - Use compression in SSH config
   - Configure appropriate timeout values
   - Consider using a proxy for remote locations

### Monitoring and Alerting

1. **System Monitoring**:
   ```bash
   # Check disk space before sync
   df -h /path/to/repos | awk 'NR==2 {if ($5+0 > 85) exit 1}'
   
   # Monitor sync duration
   time /path/to/sync_all.sh /path/to/repos.txt
   ```

2. **Alert Configuration**:
   - Set up alerts for sync failures
   - Monitor disk space thresholds
   - Track sync duration anomalies

3. **Health Checks**:
   ```bash
   # Example health check script
   #!/bin/bash
   last_sync=$(find /path/to/logs -name "sync_all_*.log" -mmin -360)
   if [ -z "$last_sync" ]; then
       echo "Warning: No sync in last 6 hours"
       exit 1
   fi
   ```

### Security Considerations

1. **Access Control**:
   - Use separate SSH keys for different environments
   - Implement IP restrictions where possible
   - Regular key rotation schedule

2. **Data Protection**:
   ```bash
   # Encrypt sensitive logs
   gpg --encrypt --recipient "backup@company.com" logfile.log
   
   # Secure cleanup
   shred -u old_logs/*.log
   ```

3. **Audit Trail**:
   - Log all sync operations
   - Track access patterns
   - Maintain change history

## Best Practices

1. **Regular Syncs**: Schedule regular syncs to maintain up-to-date backups
2. **Access Modes**: Use read-only (R) for backup-only repositories
3. **Log Management**: Regularly archive or clean old log files
4. **SSH Keys**: Ensure SSH keys have appropriate GitHub access
5. **Email Configuration**: Test email reporting with a small repository list first
6. **Cron Jobs**: Monitor cron job execution and logs regularly
7. **Disk Space**: Keep an eye on log directory size and archive old logs
8. **Performance**: Implement recommended Git and SSH optimizations
9. **Security**: Follow security best practices and maintain audit trails
10. **Monitoring**: Set up comprehensive monitoring and alerting
11. **Documentation**: Keep deployment configurations and procedures documented
12. **Testing**: Regularly test backup and restore procedures

## Troubleshooting

Common issues and solutions:

1. **SSH Key Issues**:
   - Ensure SSH key is added to GitHub
   - Check ssh-agent is running
   - Verify key permissions

2. **Permission Denied**:
   - Check repository access on GitHub
   - Verify local directory permissions

3. **Email Report Issues**:
   - Check mutt configuration
   - Verify email address
   - Check log directory permissions