#!/bin/bash

# Check if the user has permission to run Docker commands
if ! docker info > /dev/null 2>&1; then
    echo "Error: Unable to run Docker commands. Please make sure Docker is running and you have the necessary permissions."
    echo "You can try running this script with sudo, or add your user to the docker group:"
    echo "sudo usermod -aG docker $USER"
    echo "After adding your user to the docker group, log out and log back in for the changes to take effect."
    exit 1
fi
# Build the Docker images
docker-compose build

# Start the containers in detached mode
docker-compose up -d

# Wait for containers to be up
sleep 5

# Set up routes for host_u
docker exec host_u ip route add 192.168.53.0/24 dev eth0
docker exec host_u ip route add 192.168.60.0/24 via 192.168.53.1

# Set up routes for host_v
docker exec host_v ip route add 192.168.53.0/24 via 192.168.60.1

# Set up routes for gateway
docker exec gateway ip route add 192.168.53.0/24 dev eth0
docker exec gateway ip route add 192.168.60.0/24 dev eth1

# Start VPN server on gateway
docker exec -d gateway /app/vpn-setup-server.sh

# Compile and start VPN client on host_u
docker exec -d host_u bash -c "cd /app/vpn && make && ./vpnclient"

echo "VPN setup complete. You can now access the containers using:"
#echo "docker exec -it host_u /bin/bash"
#echo "docker exec -it host_v /bin/bash"
#echo "docker exec -it gateway /bin/bash"
docker exec -it gateway /bin/bash

# Clean up resources after all operations
docker-compose down --volumes --remove-orphans
