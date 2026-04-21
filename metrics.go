package main

import (
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "blog_http_requests_total",
		Help: "Total number of HTTP requests",
	}, []string{"method", "path", "status"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "blog_http_request_duration_seconds",
		Help:    "HTTP request latency",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5},
	}, []string{"method", "path"})

	dbOpenConnections = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "blog_db_open_connections",
		Help: "Number of open DB connections",
	})

	dbInUseConnections = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "blog_db_in_use_connections",
		Help: "Number of DB connections in use",
	})

	dbWaitCount = promauto.NewCounter(prometheus.CounterOpts{
		Name: "blog_db_wait_total",
		Help: "Total times waited for a DB connection",
	})

	s3UploadTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "blog_s3_uploads_total",
		Help: "Total S3 upload presign requests",
	}, []string{"status"})

	activeSessions = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "blog_active_sessions",
		Help: "Estimated active user sessions (Redis keys)",
	})
)

// prometheusMiddleware records HTTP metrics for every request.
func prometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.FullPath()
		if path == "" {
			path = "unmatched"
		}

		start := time.Now()
		c.Next()

		status := strconv.Itoa(c.Writer.Status())
		duration := time.Since(start).Seconds()

		httpRequestsTotal.WithLabelValues(c.Request.Method, path, status).Inc()
		httpRequestDuration.WithLabelValues(c.Request.Method, path).Observe(duration)
	}
}

// collectDBStats pushes DB connection pool stats to gauges.
// Call this in a goroutine: go collectDBStats()
func collectDBStats() {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	var prevWait int64
	for range ticker.C {
		if db == nil {
			continue
		}
		stats := db.Stats()
		dbOpenConnections.Set(float64(stats.OpenConnections))
		dbInUseConnections.Set(float64(stats.InUse))

		if stats.WaitCount > prevWait {
			dbWaitCount.Add(float64(stats.WaitCount - prevWait))
		}
		prevWait = stats.WaitCount
	}
}
