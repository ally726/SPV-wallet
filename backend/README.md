# Backend Setup

## 1\. **Start Bitcoin Core**

Edit your `bitcoin.conf` file and ensure it includes the following configuration:

```ini
server=1
daemon=1
regtest=1
rpcuser=test
rpcpassword=test

[regtest]
rpcport=18443
rpcallowip=0.0.0.0/0

fallbackfee=0.0001 # Bitcoin v29.1
txindex=1 # Bitcoin v29.1

# Enable SPV support (BIP158)
blockfilterindex=1 # Bitcoin v29.1
peerblockfilters=1 # Bitcoin v29.1
```

Start Bitcoin Core:

```bash
bitcoind -regtest -daemon
```

## 2\. **Configure Environment**

Create a `.env` file in the `backend/` directory:

```ini
RPC_HOST=127.0.0.1
RPC_PORT=18443
RPC_USER=test
RPC_PASSWORD=test
NETWORK=regtest
SPV_MODE=true # true=BIP158 Filters, false=Direct Scan
```

## 3\. **Install Dependencies**

Download the necessary Go modules (Go will read the `go.mod` file and download required packages):

```bash
go mod tidy
```

## 4\. **Run Server**

Start the backend server:

```bash
go run cmd/server/main.go
# OR using Makefile:
# make run
```
