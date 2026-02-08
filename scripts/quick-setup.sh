#!/bin/bash

# Quick Start: Mock PostgreSQL Testing - 30 Second Setup
# This script automates the 30-second setup for running tests

echo "🚀 Starting VPRO Quick Setup..."
echo ""

# Check if Docker is running, start if needed
echo "🐳 Checking Docker..."
if ! docker info > /dev/null 2>&1; then
    echo "   Starting Docker Desktop..."
    open -a Docker
    echo "   Waiting for Docker to be ready (30 seconds)..."
    for i in {1..30}; do
        if docker info > /dev/null 2>&1; then
            echo "   ✓ Docker is ready"
            break
        fi
        sleep 1
    done
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker failed to start. Please start Docker Desktop manually."
        exit 1
    fi
else
    echo "   ✓ Docker is already running"
fi
echo ""

# 1. Start PostgreSQL container
echo "1️⃣  Starting PostgreSQL container..."
docker-compose up -d
echo ""


# 3. Run tests
echo "3️⃣  Running tests..."
Rscript -e "testthat::test_dir('tests/testthat')"
echo ""

# 4. Stop database when done
echo "4️⃣  Stopping database..."
docker-compose down
echo ""

echo "✅ Setup complete!"
