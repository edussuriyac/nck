echo ""
echo "  _   _  _____ _  __      _   _ ______ _________          ______  _____  _  __  "
echo " | \ | |/ ____| |/ /     | \ | |  ____|__   __\ \        / / __ \|  __ \| |/ /  "
echo " |  \| | |    | ' /      |  \| | |__     | |   \ \  /\  / / |  | | |__) | ' /   "
echo " | .   | |    |  <       | .   |  __|    | |    \ \/  \/ /| |  | |  _  /|  <    "
echo " | |\  | |____| . \      | |\  | |____   | |     \  /\  / | |__| | | \ \| . \   "
echo " |_| \_|\_____|_|\_|     |_| \_|______|  |_|      \/  \/   \____/|_|  \_\_|\_\  "
echo ""
chmod +x cryptogen
chmod +x configtxgen

export SYS_CHANNEL=byfn-sys-channel
export COMPOSE_PROJECT_NAME=nck
export CHANNEL_NAME=nckchannel

cd nck-network
#---------------------------------------------------------------------------------------------------------
#                                       Network creation
#---------------------------------------------------------------------------------------------------------

#==================================================
#       crypto generation
#==================================================

echo "create generate necessary crypto files"
./cryptogen generate --config=./crypto-config.yaml
sleep 5

#==================================================
#       artifacts creation
#==================================================

mkdir channel-artifacts

echo "Generate genesis block"
./configtxgen -profile TwoOrgsOrdererGenesis -channelID $SYS_CHANNEL -outputBlock ./channel-artifacts/genesis.block
sleep 5

echo "Generate channel artifacts"
./configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
sleep 5

echo "Create anchor peers of the organizations"
./configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/WarehouseMSPanchors.tx -channelID nckchannel -asOrg WarehouseMSP

./configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/IssuerMSPanchors.tx -channelID nckchannel -asOrg IssuerMSP

./configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/SupplierMSPanchors.tx -channelID nckchannel -asOrg SupplierMSP
sleep 5

#==================================================
#       Docker environment setup
#==================================================

export IMAGE_TAG=latest
export SYS_CHANNEL=byfn-sys-channel
export COMPOSE_PROJECT_NAME=nck
export CHANNEL_NAME=nckchannel

echo "pull latest images for the cli"
docker-compose -f docker-compose-cli.yaml up -d


export WAREHOUSE_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/warehouse.nck.com/users/Admin@warehouse.nck.com/msp
export WAREHOUSE_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/warehouse.nck.com/peers/peer0.warehouse.nck.com/tls/ca.crt

export SUPPLIER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/supplier.nck.com/users/Admin@supplier.nck.com/msp 
export SUPPLIER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/supplier.nck.com/peers/peer0.supplier.nck.com/tls/ca.crt

export ISSUER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/issuer.nck.com/users/Admin@issuer.nck.com/msp 
export ISSUER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/issuer.nck.com/peers/peer0.issuer.nck.com/tls/ca.crt

export ORDERER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/nck.com/orderers/orderer.nck.com/msp/tlscacerts/tlsca.nck.com-cert.pem

#==================================================
#       Channel installation
#==================================================

echo "install channel"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="WarehouseMSP" \
  -e CORE_PEER_ADDRESS=peer0.warehouse.nck.com:7051 \
  -e CORE_PEER_MSPCONFIGPATH=$WAREHOUSE_MSPCONFIGPATH \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${WAREHOUSE_TLS_ROOTCERT_FILE} \
  cli \
  peer channel create \
    -o orderer.nck.com:7050 \
    -c $CHANNEL_NAME \
    -f ./channel-artifacts/channel.tx \
    --tls --cafile $ORDERER_TLS_ROOTCERT_FILE

sleep 3
echo "install in the warehouse organization"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="WarehouseMSP" \
  -e CORE_PEER_ADDRESS=peer0.warehouse.nck.com:7051 \
  -e CORE_PEER_MSPCONFIGPATH=${WAREHOUSE_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${WAREHOUSE_TLS_ROOTCERT_FILE} \
  cli \
  peer channel join \
    -b nckchannel.block 

sleep 3
echo "install in the supplier organization"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="SupplierMSP" \
  -e CORE_PEER_ADDRESS=peer0.supplier.nck.com:9051  \
  -e CORE_PEER_MSPCONFIGPATH=${SUPPLIER_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${SUPPLIER_TLS_ROOTCERT_FILE} \
  cli \
  peer channel join \
  -b nckchannel.block 

sleep 3
echo "install in the issuer organization"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="IssuerMSP"  \
  -e CORE_PEER_ADDRESS=peer0.issuer.nck.com:10151  \
  -e CORE_PEER_MSPCONFIGPATH=${ISSUER_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${ISSUER_TLS_ROOTCERT_FILE} \
  cli \
  peer channel join \
  -b nckchannel.block 

#==================================================
#       Definition of anchor peers
#==================================================
sleep 3
echo "Definition of warehouse anchor peer"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="WarehouseMSP" \
  -e CORE_PEER_ADDRESS=peer0.warehouse.nck.com:7051 \
  -e CORE_PEER_MSPCONFIGPATH=${WAREHOUSE_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${WAREHOUSE_TLS_ROOTCERT_FILE} \
  cli \
  peer channel update \
    -o orderer.nck.com:7050 \
    -c $CHANNEL_NAME \
    -f ./channel-artifacts/WarehouseMSPanchors.tx \
    --tls --cafile $ORDERER_TLS_ROOTCERT_FILE 

echo "Definition of supplier anchor peer"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="SupplierMSP" \
  -e CORE_PEER_ADDRESS=peer0.supplier.nck.com:9051  \
  -e CORE_PEER_MSPCONFIGPATH=${SUPPLIER_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${SUPPLIER_TLS_ROOTCERT_FILE} \
  cli \
  peer channel update \
    -o orderer.nck.com:7050 \
    -c $CHANNEL_NAME \
    -f ./channel-artifacts/SupplierMSPanchors.tx \
    --tls --cafile $ORDERER_TLS_ROOTCERT_FILE 

echo "Definition of issuer anchor peer"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="IssuerMSP"  \
  -e CORE_PEER_ADDRESS=peer0.issuer.nck.com:10151  \
  -e CORE_PEER_MSPCONFIGPATH=${ISSUER_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${ISSUER_TLS_ROOTCERT_FILE} \
  cli \
  peer channel update \
  -o orderer.nck.com:7050 \
  -c $CHANNEL_NAME \
  -f ./channel-artifacts/IssuerMSPanchors.tx \
  --tls --cafile ${ORDERER_TLS_ROOTCERT_FILE} 
sleep 5

#---------------------------------------------------------------------------------------------------------
#                                       Chaincode creation
#---------------------------------------------------------------------------------------------------------

#==================================================
#       Install chaincode
#==================================================

echo "install chaincode in the warehouse peers"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="WarehouseMSP" \
  -e CORE_PEER_ADDRESS=peer0.warehouse.nck.com:7051 \
  -e CORE_PEER_MSPCONFIGPATH=${WAREHOUSE_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${WAREHOUSE_TLS_ROOTCERT_FILE} \
  cli \
  peer chaincode install \
  -n nckcc \
  -v 1.0 \
  -l node \
  -p /opt/gopath/src/github.com/contract

sleep 3
echo "install chaincode in the supplier peers"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="SupplierMSP" \
  -e CORE_PEER_ADDRESS=peer0.supplier.nck.com:9051  \
  -e CORE_PEER_MSPCONFIGPATH=${SUPPLIER_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${SUPPLIER_TLS_ROOTCERT_FILE} \
  cli \
  peer chaincode install \
   -n nckcc \
   -v 1.0 \
   -l node \
   -p /opt/gopath/src/github.com/contract

sleep 3
echo "install chaincode in the issuer peers"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="IssuerMSP"  \
  -e CORE_PEER_ADDRESS=peer0.issuer.nck.com:10151  \
  -e CORE_PEER_MSPCONFIGPATH=${ISSUER_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${ISSUER_TLS_ROOTCERT_FILE} \
  cli \
  peer chaincode install \
   -n nckcc \
   -v 1.0 \
   -l node \
   -p /opt/gopath/src/github.com/contract

#==================================================
#       Instantiate chaincode
#==================================================

echo "instantiate chaincode"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="WarehouseMSP" \
  -e CORE_PEER_MSPCONFIGPATH=${WAREHOUSE_MSPCONFIGPATH} \
  cli \
  peer chaincode instantiate \
    -o orderer.nck.com:7050 \
    -C nckchannel \
    -n nckcc \
    -l node \
    -v 1.0 \
    -c '{"Args":[]}' \
    -P "OR ('WarehouseMSP.peer','SupplierMSP.peer','WarehouseMSP.peer')" \
    --tls \
    --cafile ${ORDERER_TLS_ROOTCERT_FILE} \
    --peerAddresses peer0.warehouse.nck.com:7051 \
    --tlsRootCertFiles ${WAREHOUSE_TLS_ROOTCERT_FILE} 
sleep 60

#==================================================
#       invoke chaincode
#==================================================
echo "invode chaincode"
docker exec \
  -e CHANNEL_NAME=nckchannel \
  -e CORE_PEER_LOCALMSPID="WarehouseMSP" \
  -e CORE_PEER_ADDRESS=peer0.warehouse.nck.com:7051 \
  -e CORE_PEER_MSPCONFIGPATH=${WAREHOUSE_MSPCONFIGPATH} \
  -e CORE_PEER_TLS_ROOTCERT_FILE=${WAREHOUSE_TLS_ROOTCERT_FILE} \
  cli \
  peer chaincode invoke \
    -o orderer.nck.com:7050 \
    -C nckchannel \
    -n nckcc \
    -c '{"function":"initLedger","Args":[]}' \
    --waitForEvent \
    --tls \
    --cafile ${ORDERER_TLS_ROOTCERT_FILE} \
    --peerAddresses peer0.warehouse.nck.com:7051 \
    --peerAddresses peer0.supplier.nck.com:9051 \
    --peerAddresses peer0.issuer.nck.com:10151 \
    --tlsRootCertFiles ${WAREHOUSE_TLS_ROOTCERT_FILE} \
    --tlsRootCertFiles ${SUPPLIER_TLS_ROOTCERT_FILE} \
    --tlsRootCertFiles ${ISSUER_TLS_ROOTCERT_FILE}
sleep 2m

#---------------------------------------------------------------------------------------------------------
#                                       Application creation
#---------------------------------------------------------------------------------------------------------

cd ..
cd application/supplier

echo "This is an example of an instance of a batch transported through a supply chain."
echo "install necessary packages for supplier"
npm install

sleep 5
echo "create the wallet of Adam from Aurora suppliers"
node addToWallet.js

sleep 5
echo "To create a batch invoke createBatch.js "
node createBatch.js

sleep 5
echo "To accept the batch from the manufacturer invoke transportBatch.js"
node transportBatch.js

cd ..
cd warehouse
sleep 5
echo "install necessary packages for warehouse"
npm install

sleep 5
echo "create the wallet of Nick from Kongez warehouse"
node addToWallet.js

sleep 5
echo "To accept batch from the supplier"
node acceptBatch.js

cd ..
cd issuer
sleep 5
echo "install necessary packages for issuer"
npm install

sleep 5
echo "create the wallet of Susan from Nova issuer"
node addToWallet.js

sleep 5
echo "To accept batch from the warehouse"
node issueBatch.js

sleep 5
echo "To read the history of a batch"
node ReadBatch.js