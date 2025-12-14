// Package main is the entry point for the SPV backend server
package main

import (
	"fmt"
	"log"

	"spv-backend/config"
	"spv-backend/internal/api"
	"spv-backend/internal/contract"
	"spv-backend/internal/filter"
	"spv-backend/internal/rpc"

	"github.com/btcsuite/btcd/chaincfg"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	log.Printf("Starting SPV Backend Server...")
	log.Printf("Network: %s", cfg.Network)
	log.Printf("RPC: %s:%s", cfg.RPCHost, cfg.RPCPort)
	log.Printf("Server: %s:%s", cfg.ServerHost, cfg.ServerPort)

	// Get chain parameters based on network
	var chainParams *chaincfg.Params
	switch cfg.Network {
	case "mainnet":
		chainParams = &chaincfg.MainNetParams
	case "testnet", "testnet3":
		chainParams = &chaincfg.TestNet3Params
	case "regtest":
		chainParams = &chaincfg.RegressionNetParams
	case "signet":
		chainParams = &chaincfg.SigNetParams
	default:
		log.Fatalf("Unknown network: %s", cfg.Network)
	}

	// Initialize RPC client
	rpcClient := rpc.NewClient(cfg.RPCHost, cfg.RPCPort, cfg.RPCUser, cfg.RPCPassword)

	// Test RPC connection
	blockCount, err := rpcClient.GetBlockCount()
	if err != nil {
		log.Fatalf("Failed to connect to Bitcoin Core RPC: %v", err)
	}
	log.Printf("Connected to Bitcoin Core - Block height: %d", blockCount)

	// Initialize services
	filterService := filter.NewService(rpcClient, chainParams)
	contractService := contract.NewService(rpcClient, cfg.ContractAddress)

	// Log SPV mode configuration
	spvModeStr := "disabled (direct scan)"
	if cfg.SPVMode {
		spvModeStr = "enabled (BIP158 filters)"
	}
	log.Printf("SPV Mode: %s", spvModeStr)

	// Initialize API handler with configuration (without merkle service)
	handler := api.NewHandler(rpcClient, filterService, contractService, cfg)

	// Setup router
	router := api.SetupRouter(handler)

	// Start server
	addr := fmt.Sprintf("%s:%s", cfg.ServerHost, cfg.ServerPort)
	log.Printf("Server listening on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
