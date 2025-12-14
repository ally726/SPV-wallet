// Package api provides REST API handlers
package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"spv-backend/config"
	"spv-backend/internal/contract"
	"spv-backend/internal/filter"
	"spv-backend/internal/rpc"

	"github.com/gin-gonic/gin"
)

// Handler manages API handlers
type Handler struct {
	rpcClient       *rpc.Client
	filterService   *filter.Service
	contractService *contract.Service
	config          *config.Config // Global configuration
}

// NewHandler creates a new API handler
func NewHandler(rpcClient *rpc.Client, filterService *filter.Service, contractService *contract.Service, cfg *config.Config) *Handler {
	return &Handler{
		rpcClient:       rpcClient,
		filterService:   filterService,
		contractService: contractService,
		config:          cfg,
	}
}

// fetchHeadersSequentially fetches multiple block headers in order
// Simple and reliable - fetches headers one by one
func (h *Handler) fetchHeadersSequentially(startHeight int64, count int) []map[string]interface{} {
	var headers []map[string]interface{}
	
	// Get current blockchain height to avoid out-of-range errors
	blockCount, err := h.rpcClient.GetBlockCount()
	if err != nil {
		log.Printf("Error getting block count: %v", err)
		return headers
	}
	
	// Adjust count if it exceeds available blocks
	maxAvailable := blockCount - startHeight + 1
	if int64(count) > maxAvailable {
		count = int(maxAvailable)
		log.Printf("Adjusted count to %d (blockchain height: %d, start: %d)", 
			count, blockCount, startHeight)
	}
	
	// Fetch headers sequentially
	for i := 0; i < count; i++ {
		height := startHeight + int64(i)
		
		// Get block hash at height
		blockHash, err := h.rpcClient.GetBlockHash(height)
		if err != nil {
			log.Printf("Error getting block hash at height %d: %v", height, err)
			break // Stop on first error
		}
		
		// Get block header
		headerData, err := h.rpcClient.GetBlockHeader(blockHash, true)
		if err != nil {
			log.Printf("Error getting block header at height %d: %v", height, err)
			break // Stop on first error
		}
		
		// Parse header
		var header map[string]interface{}
		if err := json.Unmarshal(headerData, &header); err != nil {
			log.Printf("Error parsing header at height %d: %v", height, err)
			break // Stop on first error
		}
		
		headers = append(headers, header)
	}
	
	return headers
}

// GetBlockchainInfo handles GET /blockchaininfo
func (h *Handler) GetBlockchainInfo(c *gin.Context) {
	result, err := h.rpcClient.GetBlockchainInfo()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var info map[string]interface{}
	if err := json.Unmarshal(result, &info); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse blockchain info"})
		return
	}

	c.JSON(http.StatusOK, info)
}

// GetHeaders handles GET /headers
func (h *Handler) GetHeaders(c *gin.Context) {
	startHash := c.Query("start_hash")
	countStr := c.DefaultQuery("count", "10")

	count, err := strconv.Atoi(countStr)
	if err != nil || count <= 0 || count > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid count parameter (1-2000)"})
		return
	}

	// Get starting block header
	var startHeight int64
	if startHash == "" {
		// Start from tip
		bestHash, err := h.rpcClient.GetBestBlockHash()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		startHash = bestHash
	}

	// Get start block header to find height
	headerData, err := h.rpcClient.GetBlockHeader(startHash, true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var header map[string]interface{}
	if err := json.Unmarshal(headerData, &header); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse header"})
		return
	}

	startHeight = int64(header["height"].(float64))

	// Fetch headers sequentially (simple and reliable)
	headers := h.fetchHeadersSequentially(startHeight, count)

	c.JSON(http.StatusOK, gin.H{
		"headers":      headers,
		"start_height": startHeight,
		"count":        len(headers),
	})
}

// GetBlock handles GET /block/:hash
func (h *Handler) GetBlock(c *gin.Context) {
	blockHash := c.Param("hash")
	if blockHash == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "block hash is required"})
		return
	}

	blockData, err := h.rpcClient.GetBlock(blockHash, 2) // verbosity=2 for full details
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var block map[string]interface{}
	if err := json.Unmarshal(blockData, &block); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to parse block"})
		return
	}

	c.JSON(http.StatusOK, block)
}

// BroadcastRequest represents a transaction broadcast request
type BroadcastRequest struct {
	RawTx string `json:"raw_tx" binding:"required"`
}

// BroadcastTx handles POST /broadcast
func (h *Handler) BroadcastTx(c *gin.Context) {
	var req BroadcastRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}


	txid, err := h.rpcClient.SendRawTransaction(req.RawTx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"txid": txid})
}

// HealthCheck handles GET /health
func (h *Handler) HealthCheck(c *gin.Context) {
	// Try to get block count to verify RPC connection
	_, err := h.rpcClient.GetBlockCount()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status": "healthy",
	})
}

// UTXOScanRequest represents a UTXO scan request
type UTXOScanRequest struct {
	Addresses   []string `json:"addresses" binding:"required"`
	StartHeight *int64   `json:"start_height" binding:"required"`
	EndHeight   *int64   `json:"end_height" binding:"required"`
}

// ScanUTXOs handles POST /utxos/scan
// Uses the global SPV_MODE configuration to determine scan method
func (h *Handler) ScanUTXOs(c *gin.Context) {
	var req UTXOScanRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(req.Addresses) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "at least one address is required"})
		return
	}

	if req.StartHeight == nil || req.EndHeight == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "start_height and end_height are required"})
		return
	}

	// Use global SPV_MODE configuration
	mode := "direct"
	if h.config.SPVMode {
		mode = "spv"
	}

	log.Printf("[UTXO Scan] Using mode: %s (from config), Addresses: %d, Range: %d-%d", 
		mode, len(req.Addresses), *req.StartHeight, *req.EndHeight)

	result, err := h.filterService.ScanUTXOsHybrid(req.Addresses, *req.StartHeight, *req.EndHeight, mode)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Log statistics
	if result.Statistics != nil {
		log.Printf("[UTXO Scan] Stats: mode=%s, filtered=%d, scanned=%d, hit_rate=%.2f%%, time=%dms",
			result.Statistics.Mode,
			result.Statistics.BlocksFiltered,
			result.Statistics.BlocksScanned,
			result.Statistics.FilterHitRate*100,
			result.Statistics.ScanTimeMs)
	}

	c.JSON(http.StatusOK, result)
}

// CallContractRequest represents a contract call request
type CallContractRequest struct {
	Method string   `json:"method" binding:"required"`
	Params []string `json:"params"`
}

// CallContract handles POST /contract/call
// Calls a smart contract method via RPC
func (h *Handler) CallContract(c *gin.Context) {
	var req CallContractRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Method == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "method name is required"})
		return
	}

	if req.Params == nil {
		req.Params = []string{}
	}

	result, err := h.contractService.CallContract(req.Method, req.Params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Parse result as JSON and return
	var resultData interface{}
	if err := json.Unmarshal(result, &resultData); err != nil {
		// If not JSON, return as string
		c.JSON(http.StatusOK, gin.H{"result": string(result)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"result": resultData})
}

// QueryContractRequest represents a contract query request
type QueryContractRequest struct {
	Method string   `json:"method" binding:"required"`
	Params []string `json:"params"`
}

// QueryContract handles POST /contract/query
// Queries smart contract data via RPC dumpcontractmessage
func (h *Handler) QueryContract(c *gin.Context) {
	var req QueryContractRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Method == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "method name is required"})
		return
	}

	if req.Params == nil {
		req.Params = []string{}
	}

	result, err := h.contractService.DumpContractMessage(req.Method, req.Params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Parse result as JSON and return
	var resultData interface{}
	if err := json.Unmarshal(result, &resultData); err != nil {
		// If not JSON, return as string
		c.JSON(http.StatusOK, gin.H{"result": string(result)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"result": resultData})
}

// otrequest

// SendOTRequest handles POST /ot/send
// Broadcasts the fully signed raw transaction received from the Flutter wallet.
func (h *Handler) SendOTRequest(c *gin.Context) {
	// 1. Define input structure
	var req struct {
		FromAID string `json:"from_aid" binding:"required"`
		ToAID   string `json:"to_aid" binding:"required"`
		Amount  int64  `json:"amount" binding:"required"`
		RawTx   string `json:"raw_tx" binding:"required"`
	}

	// 2. Bind JSON input
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error(), "success": false})
		return
	}

	// 3. Call C++ RPC to broadcast transaction
	txid, err := h.rpcClient.SendRawTransaction(req.RawTx)
	if err != nil {

		log.Println("!!! [DEBUG] SendOTRequest: error: h.rpcClient.SendRawTransaction failed:", err)

		c.JSON(http.StatusOK, gin.H{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	// 4. Return success result
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"txid":    txid,
	})
}

func (h *Handler) HandleRpcProxy(c *gin.Context) {
	// directly proxy the request body to the C++ RPC server
	result, rpcErr, err := h.rpcClient.ProxyRPC(c.Request.Body)
	if err != nil {
		// This is a network or Go internal error
		log.Println("!!! [DEBUG] HandleRpcProxy: transport error:", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"result": nil,
			"error":  gin.H{"code": -500, "message": err.Error()},
		})
		return
	}
	if rpcErr != nil {
		// This is an error returned by the C++ node (e.g. "Invalid params")
		log.Println("!!! [DEBUG] HandleRpcProxy: C++ RPC error:", rpcErr.Message)
		c.JSON(http.StatusOK, gin.H{ // C++ errors should still return 200 OK, but with an error object
			"result": nil,
			"error":  rpcErr,
		})
		return
	}

	// success, return the "result" object from C++
	log.Println("--- [DEBUG] HandleRpcProxy: C++ RPC success")
	c.JSON(http.StatusOK, gin.H{
		"result": result,
		"error":  nil,
	})
}
