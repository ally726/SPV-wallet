// Package contract provides smart contract interaction functionality
package contract

import (
	"encoding/json"
	"fmt"

	"spv-backend/internal/rpc"
)

// Service handles smart contract interactions
type Service struct {
	rpcClient       *rpc.Client
	contractAddress string
}

// NewService creates a new contract service
func NewService(rpcClient *rpc.Client, contractAddress string) *Service {
	return &Service{
		rpcClient:       rpcClient,
		contractAddress: contractAddress,
	}
}

// CallContract calls a contract method with the given parameters
func (s *Service) CallContract(method string, params []string) (json.RawMessage, error) {
	// Convert string params to interface{} for RPC call
	rpcParams := make([]interface{}, len(params))
	for i, p := range params {
		rpcParams[i] = p
	}

	result, err := s.rpcClient.CallContract(s.contractAddress, method, rpcParams...)
	if err != nil {
		return nil, fmt.Errorf("failed to call contract: %w", err)
	}

	return result, nil
}

// DumpContractMessage queries contract data
func (s *Service) DumpContractMessage(method string, params []string) (json.RawMessage, error) {
	// Convert string params to interface{} for RPC call
	rpcParams := make([]interface{}, len(params))
	for i, p := range params {
		rpcParams[i] = p
	}

	result, err := s.rpcClient.DumpContractMessage(s.contractAddress, method, rpcParams...)
	if err != nil {
		return nil, fmt.Errorf("failed to query contract: %w", err)
	}

	return result, nil
}
