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
    docker rm -f host_u host_v gateway
}

# Set up cleanup on script exit
trap cleanup EXIT

# Main script execution
check_docker_permissions

# Remove existing networks if they exist
docker network rm l02_nat_network l02_internal_network 2>/dev/null || true

# Build and start Docker containers
docker-compose build
docker-compose up -d

# Function to verify network creation
verify_network_creation() {
    local network_name=$1
    if ! docker network ls | grep -q "$network_name"; then
        echo "Error: Failed to create $network_name"
        exit 1
    fi
}

verify_network_creation "l02_nat_network"
verify_network_creation "l02_internal_network"

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
        sleep 1
        attempt=$((attempt + 1))
    done

    echo "Error: $container_name failed to start in time"
    return 1
}

# Wait for containers to be up
for container in host_u host_v gateway; do
    wait_for_container "$container" || exit 1
done

# Function to set up routes
setup_routes() {
    local host=$1
    shift
    local routes=("$@")
    for route in "${routes[@]}"; do
        if ! docker exec "$host" ip route show | grep -q "$route"; then
            docker exec "$host" ip route add $route || echo "Failed to add route for $host: $route"
        else
            echo "Route $route already exists for $host"
        fi
    done
}

# Set up routes for each host
setup_routes host_u "192.168.53.0/24 dev eth0" "192.168.60.0/24 via 10.0.2.1"
setup_routes host_v "192.168.53.0/24 via 192.168.60.1"
setup_routes gateway "192.168.53.0/24 dev eth0" "192.168.60.0/24 dev eth1"

# Check if TUN device exists and start VPN server and client
docker exec gateway sh -c '[ -c /dev/net/tun ] && echo "TUN device exists" || echo "TUN device does not exist"'
docker exec gateway /app/vpn-setup-server.sh || echo "Failed to start VPN server on gateway"
docker exec host_u bash -c "cd /app/vpn && make && ./vpnclient" || echo "Failed to start VPN client on host_u"

# Completion message
echo "VPN setup complete. You can now access the containers using:"
echo "docker exec -it host_u /bin/bash"
echo "docker exec -it host_v /bin/bash"
echo "docker exec -it gateway /bin/bash"

# Keep the script running to maintain the network setup
echo "Press Ctrl+C to stop and clean up the environment"
tail -f /dev/null
