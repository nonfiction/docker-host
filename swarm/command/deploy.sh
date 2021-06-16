#!/bin/bash

# Bash helper functions
include "lib/helpers.sh"
verify_esh

# Digital Ocean API
include "lib/doctl.sh"
verify_doctl

if undefined $SWARM; then
  echo
  echo "Usage:  swarm deploy SWARM"
  echo
  exit 1
fi

# Check if swarmfile exists
if hasnt $SWARMFILE; then
  echo_stop "Swarm named \"${SWARM}\" not found:"
  echo $SWARMFILE
  echo
  exit 1
fi

# Skip this if provision is called from "swarm size"
if undefined $RESIZE; then

  # Get primary and its size 
  PRIMARY=$(get_swarm_primary)
  VOLUME_SIZE=$(get_volume_size $PRIMARY)
  DROPLET_SIZE=$(get_droplet_size $PRIMARY)

  # Environment Variables
  include "lib/env.sh"

fi

REPLICAS=$(get_swarm_replicas)
NODES="$(echo "${PRIMARY} ${REPLICAS}" | xargs)"

# ---------------------------------------------------------
# Verify all nodes are ready
# ---------------------------------------------------------
if droplets_ready "$NODES"; then
  echo_next "...ready!"
else
  echo_stop "Not ready for configuration! Newly created droplets require 5-10 minutes."
  exit
fi

# Count the nodes
sum=$(echo $NODES | wc -w)

# ---------------------------------------------------------
# System configuration for each node
# ---------------------------------------------------------
echo_main "1. Node Config..."
count=1

# Build hosts file
hosts="127.0.0.1 localhost"
for node in $NODES; do
  ip="$(get_droplet_private_ip $node)"
  [ "$node" = "$PRIMARY" ] && node="${node} primary"
  hosts="${hosts}\n${ip} ${node}"
done

# Loop all nodes in swarm
for node in $NODES; do
  
  # Current node heading
  echo_node_counter $count $sum $node
  ((count++))

  # Pull updates from git
  run $node "/root/platform/swarm/node/update"

  # Prepare environment variables for run command
  env=""
  env="${env} NODE=\"$node\""
  env="${env} PRIMARY_IP=\"$(get_droplet_private_ip $PRIMARY)\""
  env="${env} HOSTS_FILE=\"$hosts\""
  env="${env} DO_AUTH_TOKEN=\"$DO_AUTH_TOKEN\""
  env="${env} WEBHOOK=\"$WEBHOOK\""

  env="${env} BASICAUTH_USER=\"$BASICAUTH_USER\""
  env="${env} BASICAUTH_PASSWORD=\"$BASICAUTH_PASSWORD\""

  env="${env} GIT_USER_NAME=\"$GIT_USER_NAME\""
  env="${env} GIT_USER_EMAIL=\"$GIT_USER_EMAIL\""
  env="${env} GITHUB_USER=\"$GITHUB_USER\""
  env="${env} GITHUB_TOKEN=\"$GITHUB_TOKEN\""

  env="${env} CODE_PASSWORD=\"$CODE_PASSWORD\""
  env="${env} SUDO_PASSWORD=\"$SUDO_PASSWORD\""
  env="${env} ROOT_PASSWORD=\"$ROOT_PASSWORD\""
  env="${env} ROOT_PUBLIC_KEY=\"$ROOT_PUBLIC_KEY\""

  env="${env} DB_USER=\"$DB_USER\""
  env="${env} DB_HOST=\"$DB_HOST\""
  env="${env} DB_ROOT_PASSWORD=\"$DB_ROOT_PASSWORD\""
  env="${env} DB_ROOT_PORT=\"$DB_ROOT_PORT\""

  env="${env} ROOT_PRIVATE_KEY=\"$ROOT_PRIVATE_KEY\""
  env="${env} DROPLET_IMAGE=\"$DROPLET_IMAGE\""
  env="${env} REGION=\"$REGION\""
  env="${env} FS_TYPE=\"$FS_TYPE\""

  env="${env} SWARMFILE_CONTENTS=\"$(cat $SWARMFILE | base64 | tr -d '\n')\""

  # Run script on node
  run $node "${env} /root/platform/swarm/node/node"

done  
  

# ---------------------------------------------------------
# Create Docker Swarm and join workers
# ---------------------------------------------------------
echo_main "2. Docker Config..."
count=1

# Loop all nodes in swarm
for node in $NODES; do

  # Current node heading
  echo_node_counter $count $sum $node
  ((count++))

  # Set join token to "primary" if not replica
  if [ "$node" = "$PRIMARY" ]; then
    join_token="primary"

  # Else, get join token from primary node
  else
    join_token="$(run $PRIMARY "cat /usr/local/env/DOCKER_JOIN_TOKEN")"
  fi
  
  # Prepare environment variables for run command
  env="JOIN=1"
  env="${env} NODE=\"$node\""
  env="${env} PRIVATE_IP=\"$(get_droplet_private_ip $node)\""
  env="${env} JOIN_TOKEN=\"$join_token\""

  # Run script on node
  run $node "${env} /root/platform/swarm/node/docker"

done



# ---------------------------------------------------------
# Create Gluster Volume
# ---------------------------------------------------------
echo_main "3. Gluster Config..."
count=1

# Loop all nodes in swarm
for node in $NODES; do

  # Current node heading
  echo_node_counter $count $sum $node
  ((count++))

  # Prepare environment variables for run command
  env="JOIN=1"
  env="${env} NODE=\"$node\""
  env="${env} NODES=\"$NODES\""
  env="${env} PRIMARY=\"$PRIMARY\""

  # Run script on node
  run $node "${env} /root/platform/swarm/node/gluster"

done


# ---------------------------------------------------------
# Deploy Swarm
# ---------------------------------------------------------
echo_main "4. Deploy Swarm..."
run $PRIMARY "cd /root/platform && make init"
run $PRIMARY "cd /root/platform && make deploy"


# ---------------------------------------------------------
# Finish
# ---------------------------------------------------------
echo
echo_line green
echo_color black/on_green " COMPLETE! "
echo_line green

exit
