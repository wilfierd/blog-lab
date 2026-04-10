package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/oauth2"
)

func setSession(c *gin.Context, userID int, name, avatar, role string) {
	sess, _ := store.Get(c.Request, "session")
	sess.Values["user_id"] = userID
	sess.Values["name"] = name
	sess.Values["avatar"] = avatar
	sess.Values["role"] = role
	sess.Save(c.Request, c.Writer)
}

func handleLogin(c *gin.Context) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid request"})
		return
	}
	var userID int
	var name, avatar, hash, role string
	err := db.QueryRow(`SELECT id, name, avatar, password_hash, role FROM users WHERE username = $1`, body.Username).
		Scan(&userID, &name, &avatar, &hash, &role)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(body.Password)) != nil {
		c.JSON(401, gin.H{"error": "invalid username or password"})
		return
	}
	setSession(c, userID, name, avatar, role)
	updateLastAccess(userID)
	c.JSON(200, gin.H{"role": role, "name": name})
}

func handleDevLogin(c *gin.Context) {
	var userID int
	var name, avatar, role string
	err := db.QueryRow(`SELECT id, name, avatar, role FROM users WHERE username = 'dev'`).
		Scan(&userID, &name, &avatar, &role)
	if err != nil {
		c.JSON(500, gin.H{"error": "dev user not found"})
		return
	}
	setSession(c, userID, name, avatar, role)
	updateLastAccess(userID)
	c.Redirect(http.StatusTemporaryRedirect, "http://localhost:3000/blog.html")
}

func handleGoogleLogin(c *gin.Context) {
	url := oauthConfig.AuthCodeURL("state", oauth2.AccessTypeOnline)
	c.Redirect(http.StatusTemporaryRedirect, url)
}

func handleGoogleCallback(c *gin.Context) {
	code := c.Query("code")
	token, err := oauthConfig.Exchange(context.Background(), code)
	if err != nil {
		c.JSON(400, gin.H{"error": "token exchange failed"})
		return
	}
	client := oauthConfig.Client(context.Background(), token)
	resp, err := client.Get("https://www.googleapis.com/oauth2/v2/userinfo")
	if err != nil {
		c.JSON(400, gin.H{"error": "failed to get user info"})
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var info struct {
		ID      string `json:"id"`
		Name    string `json:"name"`
		Email   string `json:"email"`
		Picture string `json:"picture"`
	}
	json.Unmarshal(body, &info)

	var userID int
	var role string
	err = db.QueryRow(`
		INSERT INTO users (google_id, name, email, avatar, role)
		VALUES ($1,$2,$3,$4,'user')
		ON CONFLICT (google_id) DO UPDATE SET name=$2, email=$3, avatar=$4
		RETURNING id, role`, info.ID, info.Name, info.Email, info.Picture,
	).Scan(&userID, &role)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	setSession(c, userID, info.Name, info.Picture, role)
	updateLastAccess(userID)
	c.Redirect(http.StatusTemporaryRedirect, "http://localhost:3000/blog.html")
}

func handleLogout(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	sess.Options.MaxAge = -1
	sess.Save(c.Request, c.Writer)
	c.Redirect(http.StatusTemporaryRedirect, "http://localhost:3000/index.html")
}

func handleMe(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID, ok := sess.Values["user_id"]
	if !ok {
		c.JSON(401, gin.H{"error": "not logged in"})
		return
	}
	c.JSON(200, gin.H{
		"id":     userID,
		"name":   sess.Values["name"],
		"avatar": sess.Values["avatar"],
		"role":   sess.Values["role"],
	})
}

func getMyProfile(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID := sess.Values["user_id"]

	var name, email, avatar, role string
	var username *string
	err := db.QueryRow(`SELECT name, email, avatar, role, username FROM users WHERE id = $1`, userID).
		Scan(&name, &email, &avatar, &role, &username)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, gin.H{
		"id": userID, "name": name, "email": email,
		"avatar": avatar, "role": role, "username": username,
	})
}

func updateMyProfile(c *gin.Context) {
	sess, _ := store.Get(c.Request, "session")
	userID := sess.Values["user_id"]

	var body struct {
		Name     string `json:"name"`
		Avatar   string `json:"avatar"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid request"})
		return
	}
	if body.Password != "" {
		hash, _ := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
		db.Exec(`UPDATE users SET password_hash=$1 WHERE id=$2`, string(hash), userID)
	}
	if body.Name != "" || body.Avatar != "" {
		db.Exec(`UPDATE users SET
			name = CASE WHEN $1 != '' THEN $1 ELSE name END,
			avatar = CASE WHEN $2 != '' THEN $2 ELSE avatar END
			WHERE id = $3`, body.Name, body.Avatar, userID)
	}
	// Refresh session with new name/avatar
	if body.Name != "" {
		sess.Values["name"] = body.Name
	}
	if body.Avatar != "" {
		sess.Values["avatar"] = body.Avatar
	}
	sess.Save(c.Request, c.Writer)
	c.JSON(200, gin.H{"message": "profile updated"})
}
