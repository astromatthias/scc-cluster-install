#!/bin/bash

# Fedora 4 node script for creation/starting and stopping of nodes

TEMPLATE="/home/ubuntu/fedora_template"
TARGET_DIRECTORY="/data/fedora"
JGROUPS_PORT="7800"

# functions
function setup_nodes_tcp { 
	IFS=","
	for NODE in $1; do
		echo "setting up node: ${NODE}"
		node_ip ${NODE}
		# copy the fedora template
		ssh -t ubuntu@${NODE_IP} "sudo mkdir ${TARGET_DIRECTORY} && sudo chown ubuntu:ubuntu ${TARGET_DIRECTORY} && cp -R ${TEMPLATE}/* ${TARGET_DIRECTORY}/"
		# add the host to the TCPPING configuration
		TCP_PING="${TCP_PING}${NODE_IP}[${JGROUPS_PORT}],"
	done
	
	for NODE in $1; do
		node_ip ${NODE}
		# update the setenv.sh script
		SETENV_TEMPLATE=$(cat setenv.template)
	        CATALINA_CONFIG="CATALINA_OPTS=\\\"${SETENV_TEMPLATE} -Djgroups.tcp.address=${NODE_IP} -Djgroups.tcpping.initial_hosts=${TCP_PING%?}\\\""
		JDK_CONFIG="JAVA_HOME=\\\"${TARGET_DIRECTORY}/jdk7\\\""
	        ssh ubuntu@$NODE_IP "echo -e \"#!/bin/bash\n$JDK_CONFIG\n$CATALINA_CONFIG\" > ${TARGET_DIRECTORY}/tomcat7/bin/setenv.sh"
	done
}
 
function setup_nodes {
	IFS=","
	for NODE in $1; do
		echo "setting up node: ${NODE}"
		node_ip ${NODE}
		# copy the fedora template
		ssh -t ubuntu@${NODE_IP} "sudo mkdir ${TARGET_DIRECTORY} && sudo chown ubuntu:ubuntu ${TARGET_DIRECTORY} && cp -R ${TEMPLATE}/* ${TARGET_DIRECTORY}/"
		JDK_CONFIG="JAVA_HOME=\\\"${TARGET_DIRECTORY}/jdk7\\\""
		SETENV_TEMPLATE=$(cat setenv.template)
	        CATALINA_CONFIG="CATALINA_OPTS=\\\"${SETENV_TEMPLATE}\\\""
	        ssh ubuntu@$NODE_IP "echo -e \"#!/bin/bash\n$JDK_CONFIG\n$CATALINA_CONFIG\" > ${TARGET_DIRECTORY}/tomcat7/bin/setenv.sh"
	done
}
function setup_loadbalancer {
	node_ip $1
	LB_IP=$NODE_IP
	IFS=","
	PROPERTIES="worker.list=loadbalancer\n"
	for NODE in $2; do
		node_ip $NODE
		PROPERTIES="$PROPERTIES\nworker.node${NODE}.host=$NODE_IP\n"
		PROPERTIES="${PROPERTIES}worker.node${NODE}.port=8009\n"
		PROPERTIES="${PROPERTIES}worker.node${NODE}.type=ajp13\n"
		PROPERTIES="${PROPERTIES}worker.node${NODE}.ping_mode=A\n"
		PROPERTIES="${PROPERTIES}worker.node${NODE}.lbfactor=10\n"
		NODELIST="${NODELIST}node${NODE}\x2C"
	done
	
	PROPERTIES="${PROPERTIES}\nworker.loadbalancer.type=lb\n"
	PROPERTIES="${PROPERTIES}worker.loadbalancer.sticky_session=1\n"
	PROPERTIES="${PROPERTIES}worker.loadbalancer.balance_workers=${NODELIST%????}\n"
	echo -e $PROPERTIES > /tmp/jk_workers.properties
	scp /tmp/jk_workers.properties ubuntu@${LB_IP}:
	ssh ubuntu@${LB_IP} "sudo mv /home/ubuntu/jk_workers.properties /etc/apache2/"
}

function node_ip {
	# find the ip of the VM
	eval NODE_IP=$(onevm show ${1} | grep IP_PUBLIC | awk 'BEGIN{FS="(=|,)"};{print $2}')
	if [ -z "$NODE_IP" ];
	then
		echo "ERROR: Unable to get IP for node $1"
		exit 2
	fi
}

function start_loadbalancer {
	node_ip $1
	ssh ubuntu@${NODE_IP} "sudo service apache2 restart"
}

function start_node {
	IFS=","
	for NODE in $1; do
		node_ip ${NODE}
		ssh ubuntu@${NODE_IP} "cd ${TARGET_DIRECTORY} && ${TARGET_DIRECTORY}/tomcat7/bin/startup.sh"
		NODE_TIMEOUT=$(date +%s)
		let NODE_TIMEOUT=NODE_TIMEOUT+1000*60*3			
		echo "waiting 3 mins for node $NODE [$NODE_IP]"
		RESPONSE=404
		while [[ "$RESPONSE" != "200" && $(date +%s) -lt $NODE_TIMEOUT ]]; do
			sleep 5
			RESPONSE=$(curl --write-out %{http_code} --silent --output /dev/null {$NODE_IP}:8000/fcrepo/rest)
		done
		if [ "$RESPONSE" != "200" ]; then
			echo "ERROR: Node is not alive after 3 minutes"
			exit 1
		fi
		echo "node ${NODE_IP} is alive"
	done
}

function stop_node {
	node_ip $1
	ssh ubuntu@${NODE_IP} "cd ${TARGET_DIRECTORY} && ${TARGET_DIRECTORY}/tomcat7/bin/shutdown.sh"
}

function usage {
	echo -e "\nUsage: $0 [option]\n"
	echo "Options may be one of the following:"
	echo -e "------------------------------------\n"
	echo -e "setup-node <node-list>\t\t\t setup the comma seperated nodes"
	echo -e "setup-lb <lb-id> <node-list>\t\t\t setup a load blanacer with the comma seperated nodes"
	echo -e "start-node <node-list>" 
	echo -e "stop-node <node-list>"
	echo -e "start-lb <lb-id>"
	echo -e "\nExamples:"
	echo -e "---------"
	exit 1
}

# main entry point

case "$1" in
	"setup-node")
	if [ $# -lt 2 ]; then
		usage
	fi
	setup_nodes $2
	;;
	"setup-lb")
	if [ $# -lt 3 ]; then
		usage
	fi
	setup_loadbalancer $2 $3
	;;
	"start-lb")
	if [ $# -lt 2 ]; then
		usage
	fi
	start_loadbalancer $2
	;;
	"start-node")
	if [ $# -lt 2 ]; then
		usage
	fi
	start_node $2
	;;
	"stop-node")
	if [ $# -lt 2 ]; then
		usage
	fi
	stop_node $2
	;;
	"ip")
	if [ $# -lt 2 ]; then
		usage
	fi
	node_ip $2
	echo $NODE_IP
	;;
	*)
	usage
	;;
esac
