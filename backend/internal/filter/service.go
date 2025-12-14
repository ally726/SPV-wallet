// Package filter provides BIP158 Compact Block Filter functionality
package filter

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	"spv-backend/internal/rpc"

	"github.com/btcsuite/btcd/btcutil"
	"github.com/btcsuite/btcd/btcutil/gcs"
	"github.com/btcsuite/btcd/btcutil/gcs/builder"
	"github.com/btcsuite/btcd/chaincfg"
	"github.com/btcsuite/btcd/chaincfg/chainhash"
	"github.com/btcsuite/btcd/txscript"
)

// Service handles filter-related operations
type Service struct {
	rpcClient  *rpc.Client
	chainParams *chaincfg.Params
}

// MatchedBlock represents a block that matched the filter
type MatchedBlock struct {
	Height int64  `json:"height"`
	Hash   string `json:"hash"`
}

// FilterMatchResult represents the result of a filter match operation
type FilterMatchResult struct {
	MatchedBlocks  []MatchedBlock `json:"matched_blocks"`
	TotalScanned   int            `json:"total_scanned"`
	TotalMatched   int            `json:"total_matched"`
	AddressesCount int            `json:"addresses_count"`
}

// NewService creates a new filter service
func NewService(rpcClient *rpc.Client, chainParams *chaincfg.Params) *Service {
	return &Service{
		rpcClient:  rpcClient,
		chainParams: chainParams,
	}
}

// GetFilterForBlock retrieves the BIP158 filter for a given block hash
func (s *Service) GetFilterForBlock(blockHash string) (string, string, error) {
	// Get block filter from Bitcoin Core
	result, err := s.rpcClient.GetBlockFilter(blockHash, "basic")
	if err != nil {
		return "", "", fmt.Errorf("failed to get block filter: %w", err)
	}

	var filterData struct {
		Filter string `json:"filter"`
		Header string `json:"header"`
	}
	if err := json.Unmarshal(result, &filterData); err != nil {
		return "", "", fmt.Errorf("failed to unmarshal filter data: %w", err)
	}

	return filterData.Filter, filterData.Header, nil
}

// AddressToScriptPubKey converts a Bitcoin address to scriptPubKey
func (s *Service) AddressToScriptPubKey(address string) ([]byte, error) {
	addr, err := btcutil.DecodeAddress(address, s.chainParams)
	if err != nil {
		return nil, fmt.Errorf("failed to decode address: %w", err)
	}

	script, err := txscript.PayToAddrScript(addr)
	if err != nil {
		return nil, fmt.Errorf("failed to create script: %w", err)
	}

	return script, nil
}

// MatchAddressInFilter checks if an address matches a GCS filter
func (s *Service) MatchAddressInFilter(address string, filterHex string, blockHash string) (bool, error) {
	// Convert address to scriptPubKey
	scriptPubKey, err := s.AddressToScriptPubKey(address)
	if err != nil {
		return false, err
	}

	// Decode filter hex
	filterBytes, err := hex.DecodeString(filterHex)
	if err != nil {
		return false, fmt.Errorf("failed to decode filter hex: %w", err)
	}

	// Parse block hash for filter key
	hash, err := chainhash.NewHashFromStr(blockHash)
	if err != nil {
		return false, fmt.Errorf("failed to parse block hash: %w", err)
	}

	// Derive key from block hash (BIP158)
	key := builder.DeriveKey(hash)

	// Reconstruct filter from bytes
	filter, err := gcs.FromNBytes(builder.DefaultP, builder.DefaultM, filterBytes)
	if err != nil {
		return false, fmt.Errorf("failed to reconstruct filter: %w", err)
	}

	// Check if scriptPubKey matches
	match, err := filter.Match(key, scriptPubKey)
	if err != nil {
		return false, fmt.Errorf("failed to match filter: %w", err)
	}

	return match, nil
}

// MatchAnyAddressInFilter checks if any of the addresses match a GCS filter
func (s *Service) MatchAnyAddressInFilter(addresses []string, filterHex string, blockHash string) (bool, error) {
	// Convert addresses to scriptPubKeys
	var scripts [][]byte
	for _, addr := range addresses {
		script, err := s.AddressToScriptPubKey(addr)
		if err != nil {
			return false, fmt.Errorf("failed to convert address %s: %w", addr, err)
		}
		scripts = append(scripts, script)
	}

	// Decode filter hex
	filterBytes, err := hex.DecodeString(filterHex)
	if err != nil {
		return false, fmt.Errorf("failed to decode filter hex: %w", err)
	}

	// Parse block hash for filter key
	hash, err := chainhash.NewHashFromStr(blockHash)
	if err != nil {
		return false, fmt.Errorf("failed to parse block hash: %w", err)
	}

	// Derive key from block hash (BIP158)
	key := builder.DeriveKey(hash)

	// Reconstruct filter from bytes
	filter, err := gcs.FromNBytes(builder.DefaultP, builder.DefaultM, filterBytes)
	if err != nil {
		return false, fmt.Errorf("failed to reconstruct filter: %w", err)
	}

	// Check if any scriptPubKey matches
	match, err := filter.MatchAny(key, scripts)
	if err != nil {
		return false, fmt.Errorf("failed to match filter: %w", err)
	}

	return match, nil
}

// ScanBlockRange scans a range of blocks for addresses
func (s *Service) ScanBlockRange(addresses []string, startHeight, endHeight int64) (*FilterMatchResult, error) {
	if startHeight > endHeight {
		return nil, fmt.Errorf("start height must be less than or equal to end height")
	}

	// Limit scan range to prevent abuse
	maxScanRange := int64(2000)
	if endHeight-startHeight > maxScanRange {
		return nil, fmt.Errorf("scan range too large, max %d blocks", maxScanRange)
	}

	var matchedBlocks []MatchedBlock
	totalScanned := 0

	for height := startHeight; height <= endHeight; height++ {
		// Get block hash
		blockHash, err := s.rpcClient.GetBlockHash(height)
		if err != nil {
			return nil, fmt.Errorf("failed to get block hash at height %d: %w", height, err)
		}

		// Get filter
		filterHex, _, err := s.GetFilterForBlock(blockHash)
		if err != nil {
			return nil, fmt.Errorf("failed to get filter for block %s: %w", blockHash, err)
		}

		// Check if any address matches
		matched, err := s.MatchAnyAddressInFilter(addresses, filterHex, blockHash)
		if err != nil {
			return nil, fmt.Errorf("failed to match addresses in block %s: %w", blockHash, err)
		}

		totalScanned++

		if matched {
			matchedBlocks = append(matchedBlocks, MatchedBlock{
				Height: height,
				Hash:   blockHash,
			})
		}
	}

	return &FilterMatchResult{
		MatchedBlocks:  matchedBlocks,
		TotalScanned:   totalScanned,
		TotalMatched:   len(matchedBlocks),
		AddressesCount: len(addresses),
	}, nil
}

// BuildFilterFromBlock builds a BIP158 filter from block data
// This is useful for verification or custom filter generation
func (s *Service) BuildFilterFromBlock(blockHash string) (*gcs.Filter, error) {
	// Get full block data
	blockData, err := s.rpcClient.GetBlock(blockHash, 2) // verbosity=2 for full tx details
	if err != nil {
		return nil, fmt.Errorf("failed to get block: %w", err)
	}

	var block struct {
		Hash string `json:"hash"`
		Tx   []struct {
			Txid string `json:"txid"`
			Vin  []struct {
				Txid      string `json:"txid"`
				Vout      int    `json:"vout"`
				Coinbase  string `json:"coinbase,omitempty"`
				ScriptSig struct {
					Hex string `json:"hex"`
				} `json:"scriptSig"`
			} `json:"vin"`
			Vout []struct {
				Value        float64 `json:"value"`
				N            int     `json:"n"`
				ScriptPubKey struct {
					Hex  string `json:"hex"`
					Type string `json:"type"`
				} `json:"scriptPubKey"`
			} `json:"vout"`
		} `json:"tx"`
	}

	if err := json.Unmarshal(blockData, &block); err != nil {
		return nil, fmt.Errorf("failed to unmarshal block: %w", err)
	}

	// Parse block hash
	hash, err := chainhash.NewHashFromStr(blockHash)
	if err != nil {
		return nil, fmt.Errorf("failed to parse block hash: %w", err)
	}

	// Build filter using btcd's builder
	filterBuilder := builder.WithKeyHash(hash)

	// Add all output scripts
	for _, tx := range block.Tx {
		for _, vout := range tx.Vout {
			if vout.ScriptPubKey.Hex == "" {
				continue
			}
			scriptBytes, err := hex.DecodeString(vout.ScriptPubKey.Hex)
			if err != nil {
				continue
			}
			// Skip OP_RETURN outputs
			if len(scriptBytes) > 0 && scriptBytes[0] == txscript.OP_RETURN {
				continue
			}
			filterBuilder.AddEntry(scriptBytes)
		}
	}

	// Add previous output scripts (inputs)
	// Note: This requires fetching previous transactions
	// For simplicity, we're using the RPC method which already provides filters

	return filterBuilder.Build()
}

// UTXO represents an unspent transaction output
type UTXO struct {
	TxID         string  `json:"txid"`
	Vout         int     `json:"vout"`
	Address      string  `json:"address"`
	Amount       float64 `json:"amount"`        // BTC amount
	Satoshis     int64   `json:"satoshis"`      // Satoshi amount
	ScriptPubKey string  `json:"script_pubkey"` // Hex encoded
	Height       int64   `json:"height"`
	BlockHash    string  `json:"block_hash"`
	Confirmations int64  `json:"confirmations"`
}

// UTXOScanResult represents the result of a UTXO scan operation
type UTXOScanResult struct {
	UTXOs         []UTXO         `json:"utxos"`
	TotalUTXOs    int            `json:"total_utxos"`
	TotalAmount   float64        `json:"total_amount"`   // Total BTC
	TotalSatoshis int64          `json:"total_satoshis"` // Total Satoshis
	BlocksScanned int            `json:"blocks_scanned"`
	AddressCount  int            `json:"address_count"`
	Statistics    *ScanStatistics `json:"statistics,omitempty"` // Optional scan statistics
}

// ScanStatistics provides detailed statistics about the scan operation
type ScanStatistics struct {
	Mode            string  `json:"mode"`              // "spv" or "direct"
	BlocksFiltered  int     `json:"blocks_filtered"`   // Total blocks checked with filters
	BlocksScanned   int     `json:"blocks_scanned"`    // Blocks actually scanned for UTXOs
	FilterHitRate   float64 `json:"filter_hit_rate"`   // Ratio of matched blocks
	ScanTimeMs      int64   `json:"scan_time_ms"`      // Total scan time in milliseconds
	FilterTimeMs    int64   `json:"filter_time_ms"`    // Time spent on filter matching
	BlockScanTimeMs int64   `json:"block_scan_time_ms"` // Time spent scanning blocks
}

// ScanBlocksForUTXOs scans blocks directly for UTXOs without using filters
// This method fetches full block data and parses all transactions
func (s *Service) ScanBlocksForUTXOs(addresses []string, startHeight, endHeight int64) (*UTXOScanResult, error) {
	if startHeight > endHeight {
		return nil, fmt.Errorf("start height must be less than or equal to end height")
	}

	// Limit scan range to prevent abuse
	maxScanRange := int64(2000)
	if endHeight-startHeight > maxScanRange {
		return nil, fmt.Errorf("scan range too large, max %d blocks", maxScanRange)
	}

	// Convert addresses to scriptPubKey map for faster lookup
	addressScripts := make(map[string]string) // scriptPubKeyHex -> address
	for _, addr := range addresses {
		script, err := s.AddressToScriptPubKey(addr)
		if err != nil {
			return nil, fmt.Errorf("failed to convert address %s: %w", addr, err)
		}
		scriptHex := hex.EncodeToString(script)
		addressScripts[scriptHex] = addr
	}

	var utxos []UTXO
	totalAmount := 0.0
	totalSatoshis := int64(0)
	blocksScanned := 0

	// Track spent outputs to filter them out
	spentOutputs := make(map[string]bool) // "txid:vout" -> true

	for height := startHeight; height <= endHeight; height++ {
		// Get block hash
		blockHash, err := s.rpcClient.GetBlockHash(height)
		if err != nil {
			return nil, fmt.Errorf("failed to get block hash at height %d: %w", height, err)
		}

		// Get full block data with transactions
		blockData, err := s.rpcClient.GetBlock(blockHash, 2) // verbosity=2 for full tx details
		if err != nil {
			return nil, fmt.Errorf("failed to get block %s: %w", blockHash, err)
		}

		var block struct {
			Hash          string `json:"hash"`
			Height        int64  `json:"height"`
			Confirmations int64  `json:"confirmations"`
			Tx            []struct {
				Txid string `json:"txid"`
				Vin  []struct {
					Txid string `json:"txid"`
					Vout int    `json:"vout"`
				} `json:"vin"`
				Vout []struct {
					Value        float64 `json:"value"`
					N            int     `json:"n"`
					ScriptPubKey struct {
						Hex     string   `json:"hex"`
						Type    string   `json:"type"`
						Address string   `json:"address,omitempty"` // Bitcoin Core provides this
						Addresses []string `json:"addresses,omitempty"` // Older format
					} `json:"scriptPubKey"`
				} `json:"vout"`
			} `json:"tx"`
		}

		if err := json.Unmarshal(blockData, &block); err != nil {
			return nil, fmt.Errorf("failed to unmarshal block %s: %w", blockHash, err)
		}

		blocksScanned++

		// First pass: mark all spent outputs in this block
		for _, tx := range block.Tx {
			for _, vin := range tx.Vin {
				if vin.Txid != "" { // Skip coinbase
					spentKey := fmt.Sprintf("%s:%d", vin.Txid, vin.Vout)
					spentOutputs[spentKey] = true
				}
			}
		}

		// Second pass: collect UTXOs for our addresses
		for _, tx := range block.Tx {
			for _, vout := range tx.Vout {
				// Check if this output's scriptPubKey matches any of our addresses
				if targetAddr, exists := addressScripts[vout.ScriptPubKey.Hex]; exists {
					// Check if this output is already spent in later blocks we've scanned
					outputKey := fmt.Sprintf("%s:%d", tx.Txid, vout.N)
					if spentOutputs[outputKey] {
						continue // Skip spent outputs
					}

					// Calculate satoshis
					satoshis := int64(vout.Value * 100000000)

					utxo := UTXO{
						TxID:          tx.Txid,
						Vout:          vout.N,
						Address:       targetAddr,
						Amount:        vout.Value,
						Satoshis:      satoshis,
						ScriptPubKey:  vout.ScriptPubKey.Hex,
						Height:        block.Height,
						BlockHash:     block.Hash,
						Confirmations: block.Confirmations,
					}

					utxos = append(utxos, utxo)
					totalAmount += vout.Value
					totalSatoshis += satoshis
				}
			}
		}
	}

	// Final pass: verify UTXOs are still unspent using gettxout
	verifiedUTXOs := []UTXO{}
	verifiedAmount := 0.0
	verifiedSatoshis := int64(0)

	for _, utxo := range utxos {
		// Check if UTXO is still unspent
		txOutData, err := s.rpcClient.GetTxOut(utxo.TxID, utxo.Vout, true)
		if err != nil {
			// Error checking, skip this UTXO
			continue
		}

		// If GetTxOut returns null, the output is spent
		if string(txOutData) == "null" || len(txOutData) == 0 {
			continue
		}

		verifiedUTXOs = append(verifiedUTXOs, utxo)
		verifiedAmount += utxo.Amount
		verifiedSatoshis += utxo.Satoshis
	}

	return &UTXOScanResult{
		UTXOs:         verifiedUTXOs,
		TotalUTXOs:    len(verifiedUTXOs),
		TotalAmount:   verifiedAmount,
		TotalSatoshis: verifiedSatoshis,
		BlocksScanned: blocksScanned,
		AddressCount:  len(addresses),
	}, nil
}

// ScanUTXOsHybrid performs UTXO scanning with mode selection
// Supports two modes: "spv" (filter-based) and "direct" (full scan)
func (s *Service) ScanUTXOsHybrid(addresses []string, startHeight, endHeight int64, mode string) (*UTXOScanResult, error) {
	if startHeight > endHeight {
		return nil, fmt.Errorf("start height must be less than or equal to end height")
	}

	// Limit scan range to prevent abuse
	maxScanRange := int64(2000)
	if endHeight-startHeight > maxScanRange {
		return nil, fmt.Errorf("scan range too large, max %d blocks", maxScanRange)
	}

	// Normalize mode
	if mode != "spv" && mode != "direct" {
		mode = "direct" // Default to direct mode
	}

	startTime := getCurrentTimeMs()

	if mode == "spv" {
		// SPV mode: Use filters to pre-screen blocks
		return s.scanWithFilters(addresses, startHeight, endHeight, startTime)
	}

	// Direct mode: Scan all blocks
	result, err := s.ScanBlocksForUTXOs(addresses, startHeight, endHeight)
	if err != nil {
		return nil, err
	}

	// Add statistics
	endTime := getCurrentTimeMs()
	result.Statistics = &ScanStatistics{
		Mode:            "direct",
		BlocksFiltered:  0,
		BlocksScanned:   result.BlocksScanned,
		FilterHitRate:   0,
		ScanTimeMs:      endTime - startTime,
		FilterTimeMs:    0,
		BlockScanTimeMs: endTime - startTime,
	}

	return result, nil
}

// scanWithFilters implements SPV mode scanning
// Step 1: Use BIP158 filters to identify blocks that might contain our addresses
// Step 2: Only scan the matched blocks for actual UTXOs
func (s *Service) scanWithFilters(addresses []string, startHeight, endHeight int64, startTime int64) (*UTXOScanResult, error) {
	filterStartTime := getCurrentTimeMs()

	// Step 1: Filter blocks
	var matchedBlocks []MatchedBlock
	totalFiltered := 0

	for height := startHeight; height <= endHeight; height++ {
		// Get block hash
		blockHash, err := s.rpcClient.GetBlockHash(height)
		if err != nil {
			return nil, fmt.Errorf("failed to get block hash at height %d: %w", height, err)
		}

		// Get filter
		filterHex, _, err := s.GetFilterForBlock(blockHash)
		if err != nil {
			return nil, fmt.Errorf("failed to get filter for block %s: %w", blockHash, err)
		}

		// Check if any address matches
		matched, err := s.MatchAnyAddressInFilter(addresses, filterHex, blockHash)
		if err != nil {
			return nil, fmt.Errorf("failed to match addresses in block %s: %w", blockHash, err)
		}

		totalFiltered++

		if matched {
			matchedBlocks = append(matchedBlocks, MatchedBlock{
				Height: height,
				Hash:   blockHash,
			})
		}
	}

	filterEndTime := getCurrentTimeMs()
	filterTimeMs := filterEndTime - filterStartTime

	// Step 2: Scan only matched blocks for UTXOs
	blockScanStartTime := getCurrentTimeMs()

	var utxos []UTXO
	totalAmount := 0.0
	totalSatoshis := int64(0)
	blocksScanned := 0

	// Convert addresses to scriptPubKey map for faster lookup
	addressScripts := make(map[string]string)
	for _, addr := range addresses {
		script, err := s.AddressToScriptPubKey(addr)
		if err != nil {
			return nil, fmt.Errorf("failed to convert address %s: %w", addr, err)
		}
		scriptHex := hex.EncodeToString(script)
		addressScripts[scriptHex] = addr
	}

	// Track spent outputs
	spentOutputs := make(map[string]bool)

	// Scan only matched blocks
	for _, matchedBlock := range matchedBlocks {
		blockHash := matchedBlock.Hash

		// Get full block data
		blockData, err := s.rpcClient.GetBlock(blockHash, 2)
		if err != nil {
			return nil, fmt.Errorf("failed to get block %s: %w", blockHash, err)
		}

		var block struct {
			Hash          string `json:"hash"`
			Height        int64  `json:"height"`
			Confirmations int64  `json:"confirmations"`
			Tx            []struct {
				Txid string `json:"txid"`
				Vin  []struct {
					Txid string `json:"txid"`
					Vout int    `json:"vout"`
				} `json:"vin"`
				Vout []struct {
					Value        float64 `json:"value"`
					N            int     `json:"n"`
					ScriptPubKey struct {
						Hex  string `json:"hex"`
						Type string `json:"type"`
					} `json:"scriptPubKey"`
				} `json:"vout"`
			} `json:"tx"`
		}

		if err := json.Unmarshal(blockData, &block); err != nil {
			return nil, fmt.Errorf("failed to unmarshal block %s: %w", blockHash, err)
		}

		blocksScanned++

		// Mark spent outputs
		for _, tx := range block.Tx {
			for _, vin := range tx.Vin {
				if vin.Txid != "" {
					spentKey := fmt.Sprintf("%s:%d", vin.Txid, vin.Vout)
					spentOutputs[spentKey] = true
				}
			}
		}

		// Collect UTXOs
		for _, tx := range block.Tx {
			for _, vout := range tx.Vout {
				if targetAddr, exists := addressScripts[vout.ScriptPubKey.Hex]; exists {
					outputKey := fmt.Sprintf("%s:%d", tx.Txid, vout.N)
					if spentOutputs[outputKey] {
						continue
					}

					satoshis := int64(vout.Value * 100000000)

					utxo := UTXO{
						TxID:          tx.Txid,
						Vout:          vout.N,
						Address:       targetAddr,
						Amount:        vout.Value,
						Satoshis:      satoshis,
						ScriptPubKey:  vout.ScriptPubKey.Hex,
						Height:        block.Height,
						BlockHash:     block.Hash,
						Confirmations: block.Confirmations,
					}

					utxos = append(utxos, utxo)
					totalAmount += vout.Value
					totalSatoshis += satoshis
				}
			}
		}
	}

	// Verify UTXOs are still unspent
	verifiedUTXOs := []UTXO{}
	verifiedAmount := 0.0
	verifiedSatoshis := int64(0)

	for _, utxo := range utxos {
		txOutData, err := s.rpcClient.GetTxOut(utxo.TxID, utxo.Vout, true)
		if err != nil {
			continue
		}

		if string(txOutData) == "null" || len(txOutData) == 0 {
			continue
		}

		verifiedUTXOs = append(verifiedUTXOs, utxo)
		verifiedAmount += utxo.Amount
		verifiedSatoshis += utxo.Satoshis
	}

	blockScanEndTime := getCurrentTimeMs()
	blockScanTimeMs := blockScanEndTime - blockScanStartTime

	// Calculate statistics
	endTime := getCurrentTimeMs()
	filterHitRate := 0.0
	if totalFiltered > 0 {
		filterHitRate = float64(len(matchedBlocks)) / float64(totalFiltered)
	}

	return &UTXOScanResult{
		UTXOs:         verifiedUTXOs,
		TotalUTXOs:    len(verifiedUTXOs),
		TotalAmount:   verifiedAmount,
		TotalSatoshis: verifiedSatoshis,
		BlocksScanned: blocksScanned,
		AddressCount:  len(addresses),
		Statistics: &ScanStatistics{
			Mode:            "spv",
			BlocksFiltered:  totalFiltered,
			BlocksScanned:   blocksScanned,
			FilterHitRate:   filterHitRate,
			ScanTimeMs:      endTime - startTime,
			FilterTimeMs:    filterTimeMs,
			BlockScanTimeMs: blockScanTimeMs,
		},
	}, nil
}

// getCurrentTimeMs returns current time in milliseconds
func getCurrentTimeMs() int64 {
	return time.Now().UnixNano() / 1e6
}
