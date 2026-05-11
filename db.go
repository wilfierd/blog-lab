package main

import (
	"log/slog"

	"golang.org/x/crypto/bcrypt"
)

func migrate() {
	db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		google_id TEXT UNIQUE,
		name TEXT,
		email TEXT,
		avatar TEXT,
		username TEXT UNIQUE,
		password_hash TEXT,
		role TEXT NOT NULL DEFAULT 'user',
		last_access TIMESTAMP
	)`)
	db.Exec(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_access TIMESTAMP`)
	db.Exec(`CREATE TABLE IF NOT EXISTS posts (
		id SERIAL PRIMARY KEY,
		user_id INT REFERENCES users(id),
		title TEXT NOT NULL,
		content TEXT NOT NULL,
		status TEXT NOT NULL DEFAULT 'published',
		image_url TEXT,
		created_at TIMESTAMP DEFAULT NOW(),
		updated_at TIMESTAMP DEFAULT NOW()
	)`)
	db.Exec(`ALTER TABLE posts ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published'`)
	db.Exec(`ALTER TABLE posts ADD COLUMN IF NOT EXISTS image_url TEXT`)
	db.Exec(`ALTER TABLE posts ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW()`)
	seed()
}

func seed() {
	type seedUser struct {
		username, password, name, role, googleID string
	}
	users := []seedUser{
		{"admin", "admin123", "Admin User", "admin", "seed-admin"},
		{"user", "user123", "Regular User", "user", "seed-user"},
		{"dev", "dev123", "Dev User", "dev", "seed-dev"},
	}
	for _, u := range users {
		var count int
		db.QueryRow(`SELECT COUNT(*) FROM users WHERE username = $1`, u.username).Scan(&count)
		if count > 0 {
			continue
		}
		avatar := "https://ui-avatars.com/api/?name=" + u.name
		hashed, err := bcrypt.GenerateFromPassword([]byte(u.password), bcrypt.DefaultCost)
		if err != nil {
			slog.Error("seed: failed to hash password", "username", u.username, "err", err)
			continue
		}
		var userID int
		db.QueryRow(`INSERT INTO users (google_id, name, email, avatar, username, password_hash, role)
			VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
			u.googleID, u.name, u.username+"@local.com",
			avatar, u.username, string(hashed), u.role,
		).Scan(&userID)
		if u.role == "dev" {
			db.Exec(`INSERT INTO posts (user_id, title, content) VALUES
				($1, 'Hello World', 'This is the first seeded post.'),
				($1, 'Getting Started', 'Welcome to the local blog app!')`, userID)
		}
	}
}

func updateLastAccess(userID int) {
	db.Exec(`UPDATE users SET last_access = NOW() WHERE id = $1`, userID)
}
