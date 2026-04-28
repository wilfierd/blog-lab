package main

import (
	"database/sql"
	"log/slog"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

func listUsers(c *gin.Context) {
	rows, err := db.Query(`SELECT id, name, email, username, role, last_access FROM users ORDER BY id`)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type User struct {
		ID         int     `json:"id"`
		Name       string  `json:"name"`
		Email      string  `json:"email"`
		Username   *string `json:"username"`
		Role       string  `json:"role"`
		LastAccess *string `json:"last_access"`
	}
	var users []User
	for rows.Next() {
		var u User
		var t sql.NullTime
		rows.Scan(&u.ID, &u.Name, &u.Email, &u.Username, &u.Role, &t)
		if t.Valid {
			loc, _ := time.LoadLocation("Asia/Ho_Chi_Minh")
			s := t.Time.In(loc).Format("2006-01-02 15:04:05")
			u.LastAccess = &s
		}
		users = append(users, u)
	}
	if users == nil {
		users = []User{}
	}
	c.JSON(200, users)
}

func createUser(c *gin.Context) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Name     string `json:"name"`
		Email    string `json:"email"`
		Role     string `json:"role"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.Username == "" || body.Password == "" {
		c.JSON(400, gin.H{"error": "username and password required"})
		return
	}
	if body.Role == "" {
		body.Role = "user"
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	avatar := "https://ui-avatars.com/api/?name=" + body.Name
	var id int
	err := db.QueryRow(`INSERT INTO users (name, email, avatar, username, password_hash, role)
		VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
		body.Name, body.Email, avatar, body.Username, string(hash), body.Role,
	).Scan(&id)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	slog.Info("admin created user", "new_username", body.Username, "role", body.Role, "new_user_id", id, "ip", c.ClientIP())
	c.JSON(201, gin.H{"id": id, "message": "user created"})
}

func updateUser(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid id"})
		return
	}
	var body struct {
		Name     string `json:"name"`
		Email    string `json:"email"`
		Role     string `json:"role"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid request"})
		return
	}
	if body.Password != "" {
		hash, _ := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
		db.Exec(`UPDATE users SET password_hash=$1 WHERE id=$2`, string(hash), id)
	}
	_, err = db.Exec(`UPDATE users SET name=$1, email=$2, role=$3 WHERE id=$4`,
		body.Name, body.Email, body.Role, id)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	slog.Info("admin updated user", "user_id", id, "role", body.Role, "ip", c.ClientIP())
	c.JSON(200, gin.H{"message": "user updated"})
}

func deleteUser(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid id"})
		return
	}
	sess, _ := store.Get(c.Request, "session")
	if sess.Values["user_id"] == id {
		c.JSON(400, gin.H{"error": "cannot delete yourself"})
		return
	}
	db.Exec(`DELETE FROM posts WHERE user_id = $1`, id)
	db.Exec(`DELETE FROM users WHERE id = $1`, id)
	slog.Warn("admin deleted user", "deleted_user_id", id, "ip", c.ClientIP())
	c.JSON(200, gin.H{"message": "user deleted"})
}
