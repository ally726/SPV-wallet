# Bitcoin SPV Wallet

A SPV wallet featuring BIP158 filters, AID, and Obligation Transaction.

## Prerequisites

  * **Go** 1.23+
  * **Flutter** 3.0+
  * **Bitcoin Core**

## Architecture
[Flutter App] <--> [Go Middleware] <--> [Bitcoin Core Node]

## Quick Start
1. **Setup Backend & Bitcoin Node**:
   See [Backend Documentation](backend/README.md) to start the Regtest node and API server.

2. **Run Wallet App**:
   See [Frontend Documentation](frontend/README.md) to launch the Flutter application.