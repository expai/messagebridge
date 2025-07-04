# Troubleshooting MessageBridge

This document contains solutions for common issues with MessageBridge installation and operation.

## Permission Issues

### Service fails to start with "permission denied" error

**Symptoms:**
```bash
sudo systemctl status messagebridge
# Shows: Failed to load configuration: failed to read config file: open /etc/messagebridge/config.yaml: permission denied
```

**Cause:** The configuration file has incorrect permissions and cannot be read by the `messagebridge` user.

**Quick Fix:**
```bash
# Download and run the permission fix script
sudo ./scripts/fix-permissions.sh

# Or manually fix permissions:
sudo chown root:messagebridge /etc/messagebridge
sudo chmod 750 /etc/messagebridge
sudo chown root:messagebridge /etc/messagebridge/config.yaml
sudo chmod 640 /etc/messagebridge/config.yaml
sudo systemctl restart messagebridge
```

**Prevention:** This issue has been fixed in newer versions of the installer. When upgrading, always use the `--force` flag:
```bash
sudo ./scripts/install.sh --force
```

### Database readonly error

**Symptoms:**
```bash
# In logs: attempt to write a readonly database
sudo journalctl -u messagebridge -f
# Shows: Failed to save message to storage: attempt to write a readonly database
```

**Cause:** The SQLite database files have incorrect permissions and cannot be written by the `messagebridge` user.

**Quick Fix:**
```bash
# Fix database permissions
sudo chown -R messagebridge:messagebridge /var/lib/messagebridge
sudo chmod 750 /var/lib/messagebridge
sudo find /var/lib/messagebridge -name "*.db*" -exec chmod 640 {} \;
sudo systemctl restart messagebridge

# Or use the fix script (recommended)
sudo ./scripts/fix-permissions.sh

# Or fix only database permissions (faster)
sudo ./scripts/fix-database-permissions.sh
```

## Service Issues

### Service fails to start

**Check service status:**
```bash
sudo systemctl status messagebridge
```

**View detailed logs:**
```bash
sudo journalctl -u messagebridge -f
```

**Common issues:**
1. **Configuration file missing**: Ensure `/etc/messagebridge/config.yaml` exists
2. **Permission issues**: Use the fix script above
3. **Port already in use**: Check if another service is using port 8080
4. **Database issues**: Check if SQLite database can be created in `/var/lib/messagebridge/`

### Service starts but webhooks fail

**Check nginx configuration:**
```bash
sudo nginx -t
sudo systemctl status nginx
```

**Test direct connection:**
```bash
curl -X POST http://localhost:8080/health
```

**Check SSL configuration:**
```bash
curl -X POST https://your-domain.com/health
```

## Installation Issues

### Installer fails on dependencies

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install sqlite3 nginx curl
```

**Arch Linux:**
```bash
sudo pacman -S sqlite nginx curl
```

### User already exists error

This is not an error - the installer handles existing users gracefully.

### Systemd service not found

Ensure systemd is installed and running:
```bash
systemctl --version
sudo systemctl daemon-reload
```

## SSL/TLS Issues

### Cannot access via HTTPS

**Check SSL certificate:**
```bash
sudo certbot certificates
```

**Renew certificates:**
```bash
sudo certbot renew
```

**Test SSL configuration:**
```bash
sudo nginx -t
openssl s_client -connect your-domain.com:443
```

## Database Issues

### Database locked errors

**Check database permissions:**
```bash
ls -la /var/lib/messagebridge/
sudo chown messagebridge:messagebridge /var/lib/messagebridge/database.db
```

**Check for competing processes:**
```bash
sudo lsof /var/lib/messagebridge/database.db
```

### Database corruption

**Create backup and recreate:**
```bash
sudo systemctl stop messagebridge
sudo cp /var/lib/messagebridge/database.db /var/lib/messagebridge/database.db.backup
sudo rm /var/lib/messagebridge/database.db
sudo systemctl start messagebridge
```

## Network Issues

### Cannot reach webhook endpoint

**Check firewall:**
```bash
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**Check port binding:**
```bash
sudo netstat -tlnp | grep :8080
sudo netstat -tlnp | grep :80
```

### DNS issues

**Test domain resolution:**
```bash
nslookup your-domain.com
dig your-domain.com
```

## Configuration Issues

### Invalid YAML configuration

**Test configuration syntax:**
```bash
python3 -c "import yaml; yaml.safe_load(open('/etc/messagebridge/config.yaml'))"
```

### Wrong remote URL

Check the `remote_url.url` setting in your config and ensure:
1. The URL is accessible from the server
2. The endpoint accepts POST requests
3. Authentication is properly configured

## Monitoring and Debugging

### Enable debug logging

Edit `/etc/messagebridge/config.yaml`:
```yaml
log:
  level: "DEBUG"
  file: "/var/log/messagebridge/app.log"
```

Then restart the service:
```bash
sudo systemctl restart messagebridge
```

### Check message queue status

Use the stats script:
```bash
sudo ./scripts/stats.sh
sudo ./scripts/stats.sh --status failed
sudo ./scripts/stats.sh --queue payment
```

### Monitor real-time logs

```bash
sudo journalctl -u messagebridge -f
sudo tail -f /var/log/messagebridge/app.log
sudo tail -f /var/log/nginx/messagebridge_access.log
```

## Performance Issues

### High memory usage

**Check worker configuration:**
```yaml
worker:
  batch_size: 10    # Reduce if high memory usage
  retry_delay: 30s  # Increase if remote endpoint is slow
```

### Database growing too large

**Clean old successful messages:**
```bash
sudo ./scripts/stats.sh --cleanup --older-than 30
```

## Getting Help

If none of these solutions work:

1. **Check the logs** first: `sudo journalctl -u messagebridge -f`
2. **Test basic connectivity**: `curl -X POST http://localhost:8080/health`
3. **Verify configuration**: Check YAML syntax and values
4. **Create an issue**: Include logs, config (redacted), and system info

### System Information for Bug Reports

```bash
echo "OS: $(lsb_release -d 2>/dev/null || cat /etc/os-release | head -1)"
echo "Kernel: $(uname -r)"
echo "MessageBridge: $(messagebridge -version 2>/dev/null || echo 'not found')"
echo "Go: $(go version 2>/dev/null || echo 'not found')"
echo "SQLite: $(sqlite3 --version 2>/dev/null || echo 'not found')"
echo "Nginx: $(nginx -v 2>&1 || echo 'not found')"
sudo systemctl status messagebridge --no-pager
``` 