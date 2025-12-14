// Package config provides configuration management
package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

// Config holds the application configuration
type Config struct {
	// Server configuration
	ServerHost string
	ServerPort string

	// Bitcoin RPC configuration
	RPCHost     string
	RPCPort     string
	RPCUser     string
	RPCPassword string

	// Network (mainnet, testnet, regtest)
	Network string

	// Contract configuration
	ContractAddress string

	// UTXO scan configuration
	SPVMode bool // true = use BIP158 filters, false = direct scan
}

// Load loads configuration from environment variables
func Load() (*Config, error) {
	// Try to load .env file (optional)
	_ = godotenv.Load()

	config := &Config{
		ServerHost:      getEnv("SERVER_HOST", "0.0.0.0"),
		ServerPort:      getEnv("SERVER_PORT", "3000"),
		RPCHost:         getEnv("RPC_HOST", "127.0.0.1"),
		RPCPort:         getEnv("RPC_PORT", "18443"),
		RPCUser:         getEnv("RPC_USER", "test"),
		RPCPassword:     getEnv("RPC_PASSWORD", "test"),
		Network:         getEnv("NETWORK", "regtest"),
		ContractAddress: getEnv("CONTRACT_ADDRESS", "5c26651e9c97db61d8b5ca31f34d4ebae8498b12c3213797036657b176fe2583"),
		SPVMode:         getBoolEnv("SPV_MODE", false),
	}

	// Validate required fields
	if config.RPCUser == "" || config.RPCPassword == "" {
		return nil, fmt.Errorf("RPC_USER and RPC_PASSWORD are required")
	}

	return config, nil
}

// getEnv gets an environment variable with a default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getBoolEnv gets a boolean environment variable with a default value
func getBoolEnv(key string, defaultValue bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	// Parse common boolean representations
	switch value {
	case "true", "True", "TRUE", "1", "yes", "Yes", "YES":
		return true
	case "false", "False", "FALSE", "0", "no", "No", "NO":
		return false
	default:
		return defaultValue
	}
}
