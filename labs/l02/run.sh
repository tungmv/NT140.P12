#!/bin/bash

set -e

# Check if the user has permission to run Docker commands
if ! docker info > /dev/null 2>&1; then
    echo "Error: Unable to run Docker commands. Please make sure Docker is running and you have the necessary permissions."
    echo "You can try running this script with sudo, or add your user to the docker group:"
    echo "sudo usermod -aG docker $USER"
    echo "After adding your user to the docker group, log out and log back in for the changes to take effect."
    exit 1
fi

cleanup() {
    echo "Cleaning up resources..."
    docker-compose down --volumes --remove-orphans
    docker network rm l02_nat_network l02_internal_network 2>/dev/null || true
}

# Set up cleanup on script exit
trap cleanup EXIT

# Remove existing networks if they exist
docker network rm l02_nat_network l02_internal_network 2>/dev/null || true

# Build the Docker images
docker-compose build

# Start the containers in detached mode
docker-compose up -d

# Check if networks were created successfully
if ! docker network ls | grep -q "l02_nat_network"; then
    echo "Error: Failed to create l02_nat_network"
    exit 1
fi

if ! docker network ls | grep -q "l02_internal_network"; then
    echo "Error: Failed to create l02_internal_network"
    exit 1
fi

wait_for_container() {
    local container_name=$1
    local max_attempts=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q "true"; then
            echo "$container_name is up and running"
            return 0
        fi
        echo "Waiting for $container_name to start (attempt $attempt/$max_attempts)..."
        sleep 1
        attempt=$((attempt + 1))
    done

    echo "Error: $container_name failed to start in time"
    return 1
}

# Wait for containers to be up
wait_for_container host_u || exit 1
wait_for_container host_v || exit 1
wait_for_container gateway || exit 1

# Set up routes for host_u
docker exec host_u ip route add 192.168.53.0/24 dev eth0 || echo "Failed to add route for host_u"
docker exec host_u ip route add 192.168.60.0/24 via 10.0.2.1 || echo "Failed to add route for host_u"

# Set up routes for host_v
docker exec host_v ip route add 192.168.53.0/24 via 192.168.60.1 || echo "Failed to add route for host_v"

# Set up routes for gateway
docker exec gateway ip route add 192.168.53.0/24 dev eth0 || echo "Failed to add route for gateway"
docker exec gateway ip route add 192.168.60.0/24 dev eth1 || echo "Failed to add route for gateway"

# Start VPN server on gateway
docker exec -d gateway /app/vpn-setup-server.sh || echo "Failed to start VPN server on gateway"

# Compile and start VPN client on host_u
docker exec -d host_u bash -c "cd /app/vpn && make && ./vpnclient" || echo "Failed to start VPN client on host_u"

echo "VPN setup complete. You can now access the containers using:"
echo "docker exec -it host_u /bin/bash"
echo "docker exec -it host_v /bin/bash"
echo "docker exec -it gateway /bin/bash"

# Keep the script running to maintain the network setup
echo "Press Ctrl+C to stop and clean up the environment"
tail -f /dev/null
