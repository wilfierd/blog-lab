package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func healthCheck(c *gin.Context) {
	dbStatus := "connected"
	if err := db.Ping(); err != nil {
		dbStatus = "error: " + err.Error()
	}
	c.JSON(200, gin.H{
		"status": "ok",
		"db":     dbStatus,
	})
}

type Post struct {
	ID        int     `json:"id"`
	Title     string  `json:"title"`
	Content   string  `json:"content"`
	Status    string  `json:"status"`
	ImageURL  *string `json:"cover_image_url"`
	CreatedAt string  `json:"created_at"`
	UpdatedAt string  `json:"updated_at"`
	Author    string  `json:"author"`
	Avatar    string  `json:"avatar"`
	UserID    int     `json:"author_id"`
}

var vn, _ = time.LoadLocation("Asia/Ho_Chi_Minh")

func scanPost(rows interface {
	Scan(...any) error
}) (Post, error) {
	var p Post
	var ct, ut time.Time
	err := rows.Scan(&p.ID, &p.Title, &p.Content, &p.Status, &p.ImageURL,
		&ct, &ut, &p.Author, &p.Avatar, &p.UserID)
	p.CreatedAt = ct.In(vn).Format("2006-01-02 15:04")
	p.UpdatedAt = ut.In(vn).Format("2006-01-02 15:04")
	return p, err
}

func getPosts(c *gin.Context) {
	rows, err := db.Query(`
		SELECT p.id, p.title, p.content, p.status, p.image_url,
		       p.created_at, p.updated_at, u.name, u.avatar, p.user_id
		FROM posts p JOIN users u ON p.user_id = u.id
		WHERE p.status = 'published'
		ORDER BY p.created_at DESC`)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var posts []Post
	for rows.Next() {
		p, err := scanPost(rows)
		if err == nil {
			posts = append(posts, p)
		}
	}
	if posts == nil {
		posts = []Post{}
	}
	c.JSON(200, posts)
}

func getMyDrafts(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID := sess.Values["user_id"]
	rows, err := db.Query(`
		SELECT p.id, p.title, p.content, p.status, p.image_url,
		       p.created_at, p.updated_at, u.name, u.avatar, p.user_id
		FROM posts p JOIN users u ON p.user_id = u.id
		WHERE p.user_id = $1 AND p.status = 'draft'
		ORDER BY p.updated_at DESC`, userID)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()
	var posts []Post
	for rows.Next() {
		p, err := scanPost(rows)
		if err == nil {
			posts = append(posts, p)
		}
	}
	if posts == nil {
		posts = []Post{}
	}
	c.JSON(200, posts)
}

func createPost(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID := sess.Values["user_id"]
	var body struct {
		Title    string `json:"title"`
		Content  string `json:"content"`
		Status   string `json:"status"`
		ImageURL string `json:"cover_image_url"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.Title == "" || body.Content == "" {
		c.JSON(400, gin.H{"error": "title and content required"})
		return
	}
	if body.Status != "draft" {
		body.Status = "published"
	}
	var id int
	err := db.QueryRow(`INSERT INTO posts (user_id, title, content, status, image_url)
		VALUES ($1,$2,$3,$4,NULLIF($5,'')) RETURNING id`,
		userID, body.Title, body.Content, body.Status, body.ImageURL,
	).Scan(&id)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	c.JSON(201, gin.H{"id": id, "message": "post created", "status": body.Status})
}

func updatePost(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID := sess.Values["user_id"]
	role, _ := sess.Values["role"].(string)

	postID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid id"})
		return
	}

	// Only owner or admin/dev can edit
	var ownerID int
	db.QueryRow(`SELECT user_id FROM posts WHERE id = $1`, postID).Scan(&ownerID)
	if ownerID != userID && role != "admin" && role != "dev" {
		c.JSON(403, gin.H{"error": "forbidden"})
		return
	}

	var body struct {
		Title    string `json:"title"`
		Content  string `json:"content"`
		Status   string `json:"status"`
		ImageURL string `json:"cover_image_url"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid request"})
		return
	}
	if body.Status != "draft" && body.Status != "published" {
		body.Status = "published"
	}
	_, err = db.Exec(`UPDATE posts SET title=$1, content=$2, status=$3,
		image_url=NULLIF($4,''), updated_at=NOW() WHERE id=$5`,
		body.Title, body.Content, body.Status, body.ImageURL, postID)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, gin.H{"message": "post updated"})
}

func deletePost(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID := sess.Values["user_id"]
	role, _ := sess.Values["role"].(string)

	postID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid id"})
		return
	}

	var ownerID int
	db.QueryRow(`SELECT user_id FROM posts WHERE id = $1`, postID).Scan(&ownerID)
	if ownerID != userID && role != "admin" && role != "dev" {
		c.JSON(403, gin.H{"error": "forbidden"})
		return
	}

	db.Exec(`DELETE FROM posts WHERE id = $1`, postID)
	c.JSON(200, gin.H{"message": "post deleted"})
}

func getenvStr(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func getenvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
	}
	return defaultVal
}

func sanitizeFilename(name string) string {
	name = filepath.Base(name)
	name = strings.ReplaceAll(name, " ", "_")
	name = strings.ReplaceAll(name, "..", "")
	return name
}

func buildObjectKey(prefix string, userID int, filename string) string {
	id := uuid.NewString()
	filename = sanitizeFilename(filename)
	prefix = strings.TrimSpace(prefix)
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	return fmt.Sprintf("%s%s-%s", prefix, id, filename)
}

func createS3PresignClient(ctx context.Context, region string) (*s3.PresignClient, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, err
	}
	s3c := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
			o.UsePathStyle = true // required for MinIO
		}
	})
	return s3.NewPresignClient(s3c), nil
}

func handlePresignUpload(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID, ok := sess.Values["user_id"].(int)
	if !ok {
		c.JSON(401, gin.H{"error": "unauthorized"})
		return
	}

	var req struct {
		Filename    string `json:"filename"`
		ContentType string `json:"contentType"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "invalid request body"})
		return
	}

	if req.Filename == "" || req.ContentType == "" {
		c.JSON(400, gin.H{"error": "filename and contentType are required"})
		return
	}

	allowedMimes := map[string]bool{
		"image/jpeg": true,
		"image/png":  true,
		"image/gif":  true,
		"image/webp": true,
	}
	if !allowedMimes[req.ContentType] {
		c.JSON(400, gin.H{"error": "unsupported content type"})
		return
	}

	region := getenvStr("AWS_REGION", "")
	bucket := getenvStr("AWS_BUCKET_NAME", "")
	prefix := getenvStr("AWS_S3_PREFIX", "uploads/")
	expireSec := getenvInt("PRESIGN_EXPIRE_SECONDS", 120)

	if bucket == "" || region == "" {
		s3UploadTotal.WithLabelValues("error").Inc()
		c.JSON(500, gin.H{"error": "AWS configuration missing"})
		return
	}

	key := buildObjectKey(prefix, userID, req.Filename)

	presignClient, err := createS3PresignClient(c.Request.Context(), region)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to init aws config: " + err.Error()})
		return
	}

	out, err := presignClient.PresignPutObject(c.Request.Context(), &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(key),
		ContentType: aws.String(req.ContentType),
	}, s3.WithPresignExpires(time.Duration(expireSec)*time.Second))
	if err != nil {
		s3UploadTotal.WithLabelValues("error").Inc()
		c.JSON(500, gin.H{"error": "failed to presign put object: " + err.Error()})
		return
	}

	s3UploadTotal.WithLabelValues("ok").Inc()
	c.JSON(200, gin.H{
		"uploadUrl": out.URL,
		"key":       key,
	})
}

func handlePresignGet(c *gin.Context) {
	key := c.Query("key")
	if strings.TrimSpace(key) == "" {
		c.JSON(400, gin.H{"error": "key is required"})
		return
	}

	region := getenvStr("AWS_REGION", "")
	bucket := getenvStr("AWS_BUCKET_NAME", "")
	expireSec := getenvInt("PRESIGN_EXPIRE_SECONDS", 3600) // 1 hour

	if bucket == "" || region == "" {
		c.JSON(500, gin.H{"error": "AWS configuration missing"})
		return
	}

	presignClient, err := createS3PresignClient(c.Request.Context(), region)
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to init aws config: " + err.Error()})
		return
	}

	out, err := presignClient.PresignGetObject(c.Request.Context(), &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(time.Duration(expireSec)*time.Second))
	if err != nil {
		c.JSON(500, gin.H{"error": "failed to presign get object: " + err.Error()})
		return
	}

	c.JSON(200, gin.H{"url": out.URL})
}

var _ = http.StatusOK
