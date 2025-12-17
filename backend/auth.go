package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"sync"
	"time"

	log "github.com/sirupsen/logrus"
)

const (
	sessionCookieName = "openvpn_session"
	sessionMaxAge     = 24 * time.Hour
)

type Session struct {
	Token     string
	Username  string
	CreatedAt time.Time
	ExpiresAt time.Time
}

type SessionStore struct {
	sessions map[string]*Session
	mu       sync.RWMutex
}

var sessionStore = &SessionStore{
	sessions: make(map[string]*Session),
}

type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type LoginResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

type SessionResponse struct {
	Authenticated bool   `json:"authenticated"`
	Username      string `json:"username,omitempty"`
}

func generateSessionToken() string {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		log.Errorf("Failed to generate session token: %v", err)
		return ""
	}
	return hex.EncodeToString(bytes)
}

func (store *SessionStore) Create(username string) *Session {
	store.mu.Lock()
	defer store.mu.Unlock()

	token := generateSessionToken()
	session := &Session{
		Token:     token,
		Username:  username,
		CreatedAt: time.Now(),
		ExpiresAt: time.Now().Add(sessionMaxAge),
	}

	store.sessions[token] = session
	return session
}

func (store *SessionStore) Get(token string) *Session {
	store.mu.RLock()
	defer store.mu.RUnlock()

	session, exists := store.sessions[token]
	if !exists {
		return nil
	}

	if time.Now().After(session.ExpiresAt) {
		go store.Delete(token)
		return nil
	}

	return session
}

func (store *SessionStore) Delete(token string) {
	store.mu.Lock()
	defer store.mu.Unlock()
	delete(store.sessions, token)
}

func (store *SessionStore) Cleanup() {
	store.mu.Lock()
	defer store.mu.Unlock()

	now := time.Now()
	for token, session := range store.sessions {
		if now.After(session.ExpiresAt) {
			delete(store.sessions, token)
		}
	}
}

func loginHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(LoginResponse{Success: false, Message: "Invalid request"})
		return
	}

	if appConfig == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(LoginResponse{Success: false, Message: "Server not configured"})
		return
	}

	if req.Username != appConfig.Username || !checkPassword(appConfig.PasswordHash, req.Password) {
		log.Warnf("Failed login attempt for user: %s from IP: %s", req.Username, r.RemoteAddr)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(LoginResponse{Success: false, Message: "Invalid credentials"})
		return
	}

	session := sessionStore.Create(req.Username)
	log.Infof("User %s logged in from IP: %s", req.Username, r.RemoteAddr)

	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookieName,
		Value:    session.Token,
		Path:     "/",
		HttpOnly: true,
		Secure:   appConfig.HTTPSEnabled,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(sessionMaxAge.Seconds()),
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(LoginResponse{Success: true, Message: "Login successful"})
}

func logoutHandler(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie(sessionCookieName)
	if err == nil {
		sessionStore.Delete(cookie.Value)
	}

	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		MaxAge:   -1,
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(LoginResponse{Success: true, Message: "Logged out"})
}

func sessionHandler(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie(sessionCookieName)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(SessionResponse{Authenticated: false})
		return
	}

	session := sessionStore.Get(cookie.Value)
	if session == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(SessionResponse{Authenticated: false})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(SessionResponse{Authenticated: true, Username: session.Username})
}

func authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(sessionCookieName)
		if err != nil {
			http.Error(w, `{"error": "Unauthorized"}`, http.StatusUnauthorized)
			return
		}

		session := sessionStore.Get(cookie.Value)
		if session == nil {
			http.Error(w, `{"error": "Unauthorized"}`, http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
}

func startSessionCleanup() {
	ticker := time.NewTicker(1 * time.Hour)
	go func() {
		for range ticker.C {
			sessionStore.Cleanup()
		}
	}()
}
