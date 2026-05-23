# deploy-docker-compose

Connects to a remote server over SSH, logs in to a container registry, pulls updated images, and restarts a Docker Compose stack.

Main inputs:
- `host`: SSH host
- `ssh_key`: private key for the remote host
- `deploy_path`: remote directory containing the compose file
