package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func healthCheck(c *gin.Context) {
	dbStatus := "connected"
	if err := db.Ping(); err != nil {
		dbStatus = "error: " + err.Error()
	}
	redisStatus := "connected"
	if err := rdb.Ping(context.Background()).Err(); err != nil {
		redisStatus = "error: " + err.Error()
	}
	c.JSON(200, gin.H{"status": "ok", "db": dbStatus, "redis": redisStatus})
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
	ctx := context.Background()
	cached, err := rdb.Get(ctx, "posts").Result()
	if err == nil {
		c.Header("Content-Type", "application/json")
		c.String(200, cached)
		return
	}
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
	data, _ := json.Marshal(posts)
	rdb.Set(ctx, "posts", string(data), 60*time.Second)
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
	if body.Status == "published" {
		rdb.Del(context.Background(), "posts")
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
	rdb.Del(context.Background(), "posts")
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
	rdb.Del(context.Background(), "posts")
	c.JSON(200, gin.H{"message": "post deleted"})
}

func uploadImage(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(400, gin.H{"error": "no image provided"})
		return
	}
	ext := filepath.Ext(file.Filename)
	filename := fmt.Sprintf("%d%s", time.Now().UnixNano(), ext)
	dst := "./uploads/" + filename
	if err := c.SaveUploadedFile(file, dst); err != nil {
		c.JSON(500, gin.H{"error": "failed to save file"})
		return
	}
	url := fmt.Sprintf("http://localhost:8080/uploads/%s", filename)
	c.JSON(200, gin.H{"url": url})
}

// suppress unused import warning
var _ = redis.Nil
var _ = http.StatusOK
