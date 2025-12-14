// Package api provides REST API routing
package api

import (
	"github.com/gin-gonic/gin"
)

// SetupRouter configures the API routes
func SetupRouter(handler *Handler) *gin.Engine {
	router := gin.Default()

	// Add CORS middleware
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	})

	// Health check
	router.GET("/health", handler.HealthCheck)

	// Blockchain info
	router.GET("/blockchaininfo", handler.GetBlockchainInfo)

	// Headers
	router.GET("/headers", handler.GetHeaders)

	// Blocks
	router.GET("/block/:hash", handler.GetBlock)

	// Transactions
	router.POST("/broadcast", handler.BroadcastTx)

	// UTXO scanning - automatically uses SPV mode (BIP158 filters) or direct scan based on SPV_MODE config
	router.POST("/utxos/scan", handler.ScanUTXOs)

	// Smart contract interactions
	router.POST("/contract/call", handler.CallContract)
	router.POST("/contract/query", handler.QueryContract)

	// OT Request APIs
	router.POST("/ot/build_sighashes", handler.HandleRpcProxy)
	router.POST("/ot/broadcast_signed", handler.HandleRpcProxy)
	router.POST("/ot/list_requests", handler.HandleRpcProxy)
	router.POST("/ot/get_request_cycles", handler.HandleRpcProxy)

	// A2U (Address to UTXO) APIs
	router.POST("/ot/build_a2u_sighashes", handler.HandleRpcProxy)
	router.POST("/ot/broadcast_a2u", handler.HandleRpcProxy)

	// OT Proof APIs
	router.POST("/ot/build_proof_sighashes", handler.HandleRpcProxy)
	router.POST("/ot/broadcast_proof_signed", handler.HandleRpcProxy)

	// OT Scanner APIs
	router.POST("/ot/list_cycles", handler.HandleRpcProxy)

	return router
}
