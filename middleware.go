package main

import "github.com/gin-gonic/gin"

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")
		if origin != "" {
			c.Header("Access-Control-Allow-Origin", origin)
		} else {
			c.Header("Access-Control-Allow-Origin", "*")
		}
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Header("Access-Control-Allow-Credentials", "true")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}

func authRequired(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	if _, ok := sess.Values["user_id"]; !ok {
		c.AbortWithStatusJSON(401, gin.H{"error": "unauthorized"})
		return
	}
	c.Next()
}

func adminRequired(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	role, _ := sess.Values["role"].(string)
	if role != "admin" && role != "dev" {
		c.AbortWithStatusJSON(403, gin.H{"error": "forbidden"})
		return
	}
	c.Next()
}
