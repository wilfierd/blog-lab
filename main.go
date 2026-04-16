package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/sessions"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

var (
	db          *sql.DB
	rdb         *redis.Client
	store       *sessions.CookieStore
	oauthConfig *oauth2.Config
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("Note: .env file not found, relying on system environment variables or AWS Secrets Manager")
	}

	// Fetch secrets from AWS Secrets Manager if a secret name is provided
	if secretName := os.Getenv("AWS_SECRET_NAME"); secretName != "" {
		loadSecretsFromAWS(secretName)
	}

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
		os.Getenv("DB_HOST"), os.Getenv("DB_PORT"),
		os.Getenv("DB_USER"), os.Getenv("DB_PASSWORD"), os.Getenv("DB_NAME"),
	)
	var err error
	db, err = sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	migrate()
	os.MkdirAll("./uploads", 0755)

	rdb = redis.NewClient(&redis.Options{Addr: os.Getenv("REDIS_ADDR")})
	defer rdb.Close()

	store = sessions.NewCookieStore([]byte(os.Getenv("SESSION_SECRET")))
	store.Options = &sessions.Options{
		Path:     "/",
		MaxAge:   86400,
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode, // Same-origin nên Lax là đủ
		Secure:   false,                // ALB→EC2 vẫn là HTTP
	}

	redirectURL := os.Getenv("GOOGLE_REDIRECT_URL")
	if redirectURL == "" {
		log.Fatal("GOOGLE_REDIRECT_URL environment variable is required")
	}

	oauthConfig = &oauth2.Config{
		ClientID:     os.Getenv("GOOGLE_CLIENT_ID"),
		ClientSecret: os.Getenv("GOOGLE_CLIENT_SECRET"),
		RedirectURL:  redirectURL,
		Scopes:       []string{"openid", "email", "profile"},
		Endpoint:     google.Endpoint,
	}

	r := gin.Default()
	r.MaxMultipartMemory = 8 << 20 // 8MB
	r.Use(corsMiddleware())

	// Auth
	r.GET("/auth/google", handleGoogleLogin)
	r.GET("/auth/google/callback", handleGoogleCallback)
	r.GET("/auth/logout", handleLogout)
	r.GET("/auth/me", handleMe)
	r.GET("/auth/dev-login", handleDevLogin)
	r.POST("/auth/login", handleLogin)

	// Blog
	r.GET("/api/posts", getPosts)
	r.POST("/api/posts", authRequired, createPost)
	r.GET("/api/posts/drafts", authRequired, getMyDrafts)
	r.PUT("/api/posts/:id", authRequired, updatePost)
	r.DELETE("/api/posts/:id", authRequired, deletePost)

	// Upload & Files (S3 Presigned)
	r.POST("/api/upload/presign", authRequired, handlePresignUpload)
	r.GET("/api/files/presign-get", authRequired, handlePresignGet)
	r.Static("/uploads", "./uploads") // Keep for backward compatibility if needed
	r.Static("/frontend", "./frontend") // Serve frontend files from EC2 directly

	// Account settings
	r.GET("/api/me", authRequired, getMyProfile)
	r.PUT("/api/me", authRequired, updateMyProfile)

	// Admin
	admin := r.Group("/api/admin", adminRequired)
	admin.GET("/users", listUsers)
	admin.POST("/users", createUser)
	admin.PUT("/users/:id", updateUser)
	admin.DELETE("/users/:id", deleteUser)

	// Health
	r.GET("/api/health", healthCheck)

	log.Println("Backend running on http://localhost:8080")
	r.Run(":8080")
}
