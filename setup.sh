# debug
# set -o xtrace

KEY_NAME="Noam-Roy-parkingLot-privatekey-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-`date +'%N'`"

echo "setup firewall $SEC_GRP"
SEC_GRP_ID=$(aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances" | jq -r '.GroupId')

MY_IP=$(curl ipinfo.io/ip)
echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP \
    --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port 5000) access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP \
    --port 5000 --protocol tcp \
    --cidr $MY_IP/32

UBUNTU_20_04_AMI="ami-0767046d1677be5a0"

echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID |
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID @ $PUBLIC_IP"

PRIVATE_IP=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID |
    jq -r '.Reservations[0].Instances[0].NetworkInterfaces[0].PrivateIpAddress'
)

echo "setup rule allowing PSQL (port 5432) access to $PRIVATE_IP only"
aws ec2 authorize-security-group-ingress \
--group-name $SEC_GRP \
--port 5432 --protocol tcp \
--cidr $PRIVATE_IP/32

DB_ID="db-`date +'%N'`"
USERNAME="postgres"
PASSWORD="12345678"

echo "Creating new RDS DataBase"
CREATE_DB=$(aws rds create-db-instance \
    --db-instance-identifier $DB_ID \
    --db-instance-class db.t2.micro \
    --engine postgres \
    --master-username $USERNAME \
    --master-user-password $PASSWORD \
    --backup-retention-period 0 \
    --vpc-security-group-ids $SEC_GRP_ID \
    --allocated-storage 5 | jq )

echo "Waiting for DB creation..."
aws rds wait db-instance-available --db-instance-identifier $DB_ID

DB_ADDRESS=$(aws rds describe-db-instances --db-instance-identifier $DB_ID | jq -r '.DBInstances[0].Endpoint.Address')
echo "$DB_ADDRESS"

echo "New DB created @ $DB_ADDRESS"

echo "deploying code to production"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" app.py ubuntu@$PUBLIC_IP:/home/ubuntu/

echo "setup production environment"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" ubuntu@$PUBLIC_IP <<EOF
    sudo apt-get update
    sudo apt install python3-flask postgresql postgresql-contrib  -y

    # save DB address
    touch address.txt
    echo $DB_ADDRESS > address.txt
    echo $USERNAME >> address.txt
    echo $PASSWORD >> address.txt

    # setup DB
    PGPASSWORD=$PASSWORD  psql -h $DB_ADDRESS -p 5432 -U $USERNAME -c 'create table parkingSystem (ticketId text primary key not null, plate text not null, parkingLot text not null, entry_time text not null)'

    # run app
    nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF

echo "test that it all worked"
curl  --retry-connrefused --retry 10 --retry-delay 1  http://$PUBLIC_IP:5000

echo "Please connect to http://$PUBLIC_IP:5000 for our parking lot"