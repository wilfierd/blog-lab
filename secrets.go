package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// loadSecretsFromAWS fetches a JSON secret from AWS Secrets Manager
// and sets its key-value pairs as environment variables.
func loadSecretsFromAWS(secretName string) {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-west-2"
	}

	cfg, err := config.LoadDefaultConfig(context.Background(), config.WithRegion(region))
	if err != nil {
		slog.Warn("failed to load AWS config for secrets", "err", err)
		return
	}

	svc := secretsmanager.NewFromConfig(cfg)
	result, err := svc.GetSecretValue(context.Background(), &secretsmanager.GetSecretValueInput{
		SecretId:     aws.String(secretName),
		VersionStage: aws.String("AWSCURRENT"),
	})
	if err != nil {
		slog.Warn("failed to fetch secret", "secret", secretName, "err", err)
		return
	}

	var secretMap map[string]string
	if err := json.Unmarshal([]byte(*result.SecretString), &secretMap); err != nil {
		slog.Warn("failed to parse secret JSON", "secret", secretName, "err", err)
		return
	}

	for k, v := range secretMap {
		os.Setenv(k, v)
	}
	slog.Info("secrets loaded", "secret", secretName)
}
