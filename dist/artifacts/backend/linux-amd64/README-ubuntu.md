# Ubuntu backend deployment notes

## Files
- new-api-v0.0.0-dev: backend executable
- run-ubuntu.sh: launch wrapper script

## Recommended environment
- Ubuntu 20.04 / 22.04 / 24.04
- systemd
- Network access to database, Redis, and upstream services

## Start steps
1. Upload the whole directory to Ubuntu, for example `/opt/new-api`
2. Run `chmod +x new-api-v0.0.0-dev run-ubuntu.sh`
3. Prepare a `.env` file in the same directory
4. Run `./run-ubuntu.sh`

## Notes
- This build uses `GOOS=linux GOARCH=amd64`
- Linux builds use `CGO_ENABLED=0` by default for easier non-Docker deployment