#!/bin/bash
set -e

# Function to check Docker permissions
check_docker_permissions() {
    if ! docker info > /dev/null 2>&1; then
        echo "Error: Unable to run Docker commands. Please ensure Docker is running and you have the necessary permissions."
        echo "You can try running this script with sudo, or add your user to the docker group:"
        echo "sudo usermod -aG docker $USER"
        echo "Log out and log back in for the changes to take effect."
        exit 1
    fi
}

# Cleanup function to remove resources
cleanup() {
    echo "Cleaning up resources..."
    docker-compose down --volumes --remove-orphans
    docker network rm l02_nat_network l02_internal_network 2>/dev/null || true
}

# Set up cleanup on script exit
trap cleanup EXIT

# Main script execution
check_docker_permissions

# Remove existing networks if they exist
docker network rm l02_nat_network l02_internal_network 2>/dev/null || true

# Build and start Docker containers
docker-compose up -d --build

# Function to wait for a container to be up
wait_for_container() {
    local container_name=$1
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q "true"; then
            echo "$container_name is up and running"
            return 0
        fi
        echo "Waiting for $container_name to start (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done

    echo "Error: $container_name failed to start in time"
    return 1
}

# Wait for containers to be up
for container in host_u host_v gateway; do
    wait_for_container "$container" || exit 1
done

echo "Checking TUN device..."
docker exec gateway sh -c '[ -c /dev/net/tun ] && echo "TUN device exists" || echo "TUN device does not exist"'

echo "Starting VPN server..."
docker exec -d gateway /app/vpn/vpnserver
sleep 5  # Give the server time to start up

echo "Starting VPN client..."
docker exec -d host_u /app/vpn/vpnclient
sleep 5  # Give the client time to connect

## Debug: Check if telnet service is running on host_v
#echo "Checking telnet service on host_v..."
#docker exec host_v netstat -tuln | grep :23 || { echo "Telnet service is not running on host_v"; }
#
## Debug: Check xinetd status on host_v
#echo "Checking xinetd status on host_v..."
#docker exec host_v service xinetd status
#
## Debug: Check if port 23 is open on host_v
#echo "Checking if port 23 is open on host_v..."
#docker exec host_u bash -c '(echo > /dev/tcp/192.168.60.8/23) >/dev/null 2>&1 && echo "Port 23 is open" || echo "Port 23 is closed"'
#
## Debug: Try telnet connection
#echo "Attempting telnet connection..."
#docker exec -it host_u telnet 192.168.60.8 23

# Completion message
echo "VPN setup complete. You can now access the containers using:"
echo "docker exec -it host_u /bin/bash"
echo "docker exec -it host_v /bin/bash"
echo "docker exec -it gateway /bin/bash"

# Keep the script running to maintain the network setup
echo "Press Ctrl+C to stop and clean up the environment"
#echo "Tailing logs from gateway container..."
docker logs -f gateway