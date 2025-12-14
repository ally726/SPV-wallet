// Package rpc provides Bitcoin Core RPC client functionality
package rpc

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client represents a Bitcoin Core RPC client
type Client struct {
	host     string
	port     string
	user     string
	password string
	client   *http.Client
}

// RPCRequest represents a JSON-RPC request
type RPCRequest struct {
	Jsonrpc string        `json:"jsonrpc"`
	Method  string        `json:"method"`
	Params  []interface{} `json:"params"`
	ID      int           `json:"id"`
}

// RPCResponse represents a JSON-RPC response
type RPCResponse struct {
	Result json.RawMessage `json:"result"`
	Error  *RPCError       `json:"error"`
	ID     int             `json:"id"`
}

// RPCError represents a JSON-RPC error
type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// NewClient creates a new Bitcoin Core RPC client
func NewClient(host, port, user, password string) *Client {
	return &Client{
		host:     host,
		port:     port,
		user:     user,
		password: password,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// Call makes a JSON-RPC call to Bitcoin Core
func (c *Client) Call(method string, params ...interface{}) (json.RawMessage, error) {
	// Prepare request
	reqBody := RPCRequest{
		Jsonrpc: "1.0",
		Method:  method,
		Params:  params,
		ID:      1,
	}

	reqBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP request
	url := fmt.Sprintf("http://%s:%s", c.host, c.port)
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(c.user, c.password)
	req.Header.Set("Content-Type", "application/json")

	// Execute request
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse response
	var rpcResp RPCResponse
	if err := json.Unmarshal(respBytes, &rpcResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	// Check for RPC error
	if rpcResp.Error != nil {
		return nil, fmt.Errorf("RPC error %d: %s", rpcResp.Error.Code, rpcResp.Error.Message)
	}

	return rpcResp.Result, nil
}

// GetBlockchainInfo returns blockchain information
func (c *Client) GetBlockchainInfo() (json.RawMessage, error) {
	return c.Call("getblockchaininfo")
}

// GetBlockHash returns the block hash at the given height
func (c *Client) GetBlockHash(height int64) (string, error) {
	result, err := c.Call("getblockhash", height)
	if err != nil {
		return "", err
	}

	var hash string
	if err := json.Unmarshal(result, &hash); err != nil {
		return "", fmt.Errorf("failed to unmarshal block hash: %w", err)
	}

	return hash, nil
}

// GetBlockHeader returns the block header for the given hash
func (c *Client) GetBlockHeader(hash string, verbose bool) (json.RawMessage, error) {
	return c.Call("getblockheader", hash, verbose)
}

// GetBlock returns the block for the given hash
func (c *Client) GetBlock(hash string, verbosity int) (json.RawMessage, error) {
	return c.Call("getblock", hash, verbosity)
}

// GetBlockFilter returns the BIP157 block filter for the given hash
func (c *Client) GetBlockFilter(blockHash string, filterType string) (json.RawMessage, error) {
	return c.Call("getblockfilter", blockHash, filterType)
}

// SendRawTransaction broadcasts a raw transaction
func (c *Client) SendRawTransaction(hexTx string) (string, error) {
	result, err := c.Call("sendrawtransaction", hexTx)
	if err != nil {
		return "", err
	}

	var txid string
	if err := json.Unmarshal(result, &txid); err != nil {
		return "", fmt.Errorf("failed to unmarshal txid: %w", err)
	}

	return txid, nil
}

// GetRawTransaction returns the raw transaction
func (c *Client) GetRawTransaction(txid string, verbose bool) (json.RawMessage, error) {
	return c.Call("getrawtransaction", txid, verbose)
}

// GetTxOut returns details about an unspent transaction output
func (c *Client) GetTxOut(txid string, vout int, includeMempool bool) (json.RawMessage, error) {
	return c.Call("gettxout", txid, vout, includeMempool)
}

// GetBestBlockHash returns the hash of the best (tip) block
func (c *Client) GetBestBlockHash() (string, error) {
	result, err := c.Call("getbestblockhash")
	if err != nil {
		return "", err
	}

	var hash string
	if err := json.Unmarshal(result, &hash); err != nil {
		return "", fmt.Errorf("failed to unmarshal best block hash: %w", err)
	}

	return hash, nil
}

// GetBlockCount returns the number of blocks in the blockchain
func (c *Client) GetBlockCount() (int64, error) {
	result, err := c.Call("getblockcount")
	if err != nil {
		return 0, err
	}

	var count int64
	if err := json.Unmarshal(result, &count); err != nil {
		return 0, fmt.Errorf("failed to unmarshal block count: %w", err)
	}

	return count, nil
}

// BatchCall makes multiple JSON-RPC calls in a single HTTP request
// This significantly reduces network overhead when fetching multiple items
func (c *Client) BatchCall(requests []RPCRequest) ([]RPCResponse, error) {
	// Prepare batch request
	reqBytes, err := json.Marshal(requests)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal batch request: %w", err)
	}

	// Create HTTP request
	url := fmt.Sprintf("http://%s:%s", c.host, c.port)
	req, err := http.NewRequest("POST", url, bytes.NewReader(reqBytes))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(c.user, c.password)
	req.Header.Set("Content-Type", "application/json")

	// Execute request
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse batch response
	var rpcResponses []RPCResponse
	if err := json.Unmarshal(respBytes, &rpcResponses); err != nil {
		return nil, fmt.Errorf("failed to unmarshal batch response: %w", err)
	}

	return rpcResponses, nil
}

// CallContract calls a smart contract method
func (c *Client) CallContract(contractAddress, method string, params ...interface{}) (json.RawMessage, error) {
	// Build parameters array: [contractAddress, method, ...params]
	rpcParams := make([]interface{}, 0, 2+len(params))
	rpcParams = append(rpcParams, contractAddress, method)
	rpcParams = append(rpcParams, params...)

	return c.Call("callcontract", rpcParams...)
}

// DumpContractMessage queries smart contract data
func (c *Client) DumpContractMessage(contractAddress, method string, params ...interface{}) (json.RawMessage, error) {
	// Build parameters array: [contractAddress, method, ...params]
	rpcParams := make([]interface{}, 0, 2+len(params))
	rpcParams = append(rpcParams, contractAddress, method)
	rpcParams = append(rpcParams, params...)

	return c.Call("dumpcontractmessage", rpcParams...)
}

//otrequest

// ValidateOTRequest calls the custom 'validateotrequest' RPC.
// This RPC validates OT Request parameters and returns the OP_RETURN data string.
func (c *Client) ValidateOTRequest(fromAID string, toAID string, amount int64) (json.RawMessage, error) {
	// The Bitcoin Core RPC is: validateotrequest "from_aid" "to_aid" amount
	// The amount parameter in C++ is CAmount (satoshis), which matches int64 here.

	// Arguments for the RPC call
	params := []interface{}{fromAID, toAID, amount}

	// Call the custom RPC
	// Expected result: {"valid": true, "data": "OT_REQUEST|...", "timestamp": 123456789}
	result, err := c.Call("validateotrequest", params...)
	if err != nil {
		return nil, fmt.Errorf("failed to call validateotrequest: %w", err)
	}

	return result, nil
}

func (c *Client) ProxyRPC(requestBody io.ReadCloser) (json.RawMessage, *RPCError, error) {
	url := fmt.Sprintf("http://%s:%s", c.host, c.port)
	req, err := http.NewRequest("POST", url, requestBody)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.SetBasicAuth(c.user, c.password)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read response: %w", err)
	}



	var rpcResp RPCResponse
	if err := json.Unmarshal(respBytes, &rpcResp); err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if rpcResp.Error != nil {
		return nil, rpcResp.Error, nil // 傳回 C++ 的 RPC 錯誤，而不是 Go 的 error
	}

	return rpcResp.Result, nil, nil
}

// func (c *Client) BroadcastRawTxCustom(hexTx string) (string, error) {
// 	result, err := c.Call("broadcastrawtx_custom", hexTx)
// 	if err != nil {
// 		return "", err
// 	}

// 	var txid string
// 	if err := json.Unmarshal(result, &txid); err != nil {
// 		return "", fmt.Errorf("failed to unmarshal txid from broadcastrawtx_custom: %w", err)
// 	}

// 	return txid, nil
// }
