package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io/ioutil"
	"os"
	"path/filepath"

	log "github.com/sirupsen/logrus"
	"golang.org/x/crypto/bcrypt"
)

const (
	configDir  = "/etc/openvpn-ui"
	configFile = "config.json"
)

type AppConfig struct {
	Username      string `json:"username"`
	PasswordHash  string `json:"password_hash"`
	SessionSecret string `json:"session_secret"`
	WebPort       int    `json:"web_port"`
	Domain        string `json:"domain"`
	HTTPSEnabled  bool   `json:"https_enabled"`
}

var appConfig *AppConfig

func getConfigPath() string {
	return filepath.Join(configDir, configFile)
}

func loadConfig() (*AppConfig, error) {
	configPath := getConfigPath()

	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return nil, err
	}

	data, err := ioutil.ReadFile(configPath)
	if err != nil {
		return nil, err
	}

	config := &AppConfig{}
	if err := json.Unmarshal(data, config); err != nil {
		return nil, err
	}

	return config, nil
}

func saveConfig(config *AppConfig) error {
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}

	return ioutil.WriteFile(getConfigPath(), data, 0600)
}

func initConfig() *AppConfig {
	config, err := loadConfig()
	if err != nil {
		log.Infof("Config not found, will use environment variables")
		config = &AppConfig{}
	}

	// Override from environment variables if set
	if username := os.Getenv("ADMIN_USERNAME"); username != "" {
		config.Username = username
	}

	if password := os.Getenv("ADMIN_PASSWORD"); password != "" {
		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err != nil {
			log.Errorf("Failed to hash password: %v", err)
		} else {
			config.PasswordHash = string(hash)
		}
	}

	if config.SessionSecret == "" {
		config.SessionSecret = generateRandomString(32)
	}

	if domain := os.Getenv("DOMAIN"); domain != "" {
		config.Domain = domain
		config.HTTPSEnabled = true
	}

	appConfig = config
	return config
}

func generateRandomString(length int) string {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		log.Errorf("Failed to generate random string: %v", err)
		return "default-secret-change-me"
	}
	return hex.EncodeToString(bytes)[:length]
}

func hashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func checkPassword(hash, password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}
