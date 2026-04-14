package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// LoadSecretsFromAWS fetches a JSON secret from AWS Secrets Manager
// and sets its key-value pairs as environment variables.
func loadSecretsFromAWS(secretName string) {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-west-2" // Default fallback
	}

	cfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	if err != nil {
		log.Printf("Warning: Failed to load AWS config for secrets: %v", err)
		return
	}

	svc := secretsmanager.NewFromConfig(cfg)
	input := &secretsmanager.GetSecretValueInput{
		SecretId:     aws.String(secretName),
		VersionStage: aws.String("AWSCURRENT"),
	}

	result, err := svc.GetSecretValue(context.Background(), input)
	if err != nil {
		log.Printf("Warning: Failed to fetch secret '%s': %v", secretName, err)
		return
	}

	var secretMap map[string]string
	if err := json.Unmarshal([]byte(*result.SecretString), &secretMap); err != nil {
		log.Printf("Warning: Failed to parse secret JSON: %v", err)
		return
	}

	for k, v := range secretMap {
		os.Setenv(k, v)
	}
	log.Printf("Successfully loaded secrets from AWS Secrets Manager: %s", secretName)
}
