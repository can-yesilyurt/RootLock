#!/bin/bash
set -euo pipefail

# Build script for Secure Network Setup Tool

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Secure Network Setup Tool - Build Script${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if this is first-time setup
if ! grep -q "REPLACE_WITH_ENCRYPTED_PASSWORD_BASE64" SecureNetworkSetup.swift; then
    echo -e "${GREEN}✓ Credentials already embedded${NC}"
    BUILD_ONLY=true
else
    echo -e "${YELLOW}⚠ No credentials found. Running first-time setup...${NC}"
    BUILD_ONLY=false
fi

if [ "$BUILD_ONLY" = false ]; then
    # First-time setup
    echo
    echo -e "${YELLOW}Step 1: Generate Encrypted Credentials${NC}"
    echo -e "${YELLOW}────────────────────────────────────────${NC}"
    echo
    
    # Prompt for password
    read -sp "Enter your admin password (will be encrypted): " ADMIN_PASSWORD
    echo
    read -sp "Confirm password: " ADMIN_PASSWORD_CONFIRM
    echo
    
    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        echo -e "${RED}❌ Passwords don't match${NC}"
        exit 1
    fi
    
    echo
    echo -e "${BLUE}Generating encrypted credentials...${NC}"
    
    # Build the credential generator
    swiftc -parse-as-library -O EmbedCredentials.swift -o .embed_credentials_tmp
    
    # Generate credentials and capture output
    CRED_OUTPUT=$(./.embed_credentials_tmp "$ADMIN_PASSWORD")
    
    # Clean up
    rm .embed_credentials_tmp
    
    echo "$CRED_OUTPUT"
    echo
    
    # Extract the Base64 values
    SALT=$(echo "$CRED_OUTPUT" | grep "// KDF Salt" -A 1 | tail -n 1 | sed 's/let base64 = "\(.*\)"/\1/')
    ENCRYPTED=$(echo "$CRED_OUTPUT" | grep "// Encrypted Password" -A 1 | tail -n 1 | sed 's/let base64 = "\(.*\)"/\1/')
    SIGNATURE=$(echo "$CRED_OUTPUT" | grep "// Script Signature" -A 1 | tail -n 1 | sed 's/let base64 = "\(.*\)"/\1/')
    
    if [ -z "$SALT" ] || [ -z "$ENCRYPTED" ] || [ -z "$SIGNATURE" ]; then
        echo -e "${RED}❌ Failed to extract credentials${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Embedding credentials into source file...${NC}"
    
    # Create backup
    cp SecureNetworkSetup.swift SecureNetworkSetup.swift.bak
    
    # Replace placeholders using | as delimiter to avoid conflicts with / in base64
    sed -i '' "s|REPLACE_WITH_KDF_SALT_BASE64|$SALT|" SecureNetworkSetup.swift
    sed -i '' "s|REPLACE_WITH_ENCRYPTED_PASSWORD_BASE64|$ENCRYPTED|" SecureNetworkSetup.swift
    sed -i '' "s|REPLACE_WITH_SCRIPT_SIGNATURE_BASE64|$SIGNATURE|" SecureNetworkSetup.swift
    
    echo -e "${GREEN}✓ Credentials embedded${NC}"
    echo
fi

# Build the final binary
echo -e "${YELLOW}Step 2: Embed Script Content${NC}"
echo -e "${YELLOW}──────────────────────────────${NC}"
echo

# Check if Script.sh exists
if [ ! -f "Script.sh" ]; then
    echo -e "${RED}❌ Error: Script.sh not found${NC}"
    exit 1
fi

lineNumber=$(grep -n "B477084B-EBC5-4AB6-9A72-19A435D92834" SecureNetworkSetup.swift | cut -d ":" -f 1)
header=$(( $lineNumber - 1 ))
totalLine=$(wc -l ./SecureNetworkSetup.swift | cut -d "." -f 1 | tr -d " ")
footer=$(( $totalLine - lineNumber ))
headerText=$(cat SecureNetworkSetup.swift | head -$header)
footerText=$(cat SecureNetworkSetup.swift | tail -$footer)
scrptText=$(cat Script.sh)

echo -e "$headerText" > SecureNetworkSetup.swift
echo -e "$scrptText" >> SecureNetworkSetup.swift
echo "$footerText" >> SecureNetworkSetup.swift



# Build the final binary
echo -e "${YELLOW}Step 3: Build Secure Binary${NC}"
echo -e "${YELLOW}────────────────────────────${NC}"
echo


swiftc -parse-as-library -O SecureNetworkSetup.swift -o netsetup

# Clean up temp Swift file
if [ $? -eq 0 ]; then
    rm -f SecureNetworkSetup.swift.tmp
else
    echo -e "${RED}❌ Build failed. Temp file kept for debugging: SecureNetworkSetup.swift.tmp${NC}"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful${NC}"
    
    # Set secure permissions
    chmod 700 netsetup
    
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Setup Complete!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "Binary location: $(pwd)/netsetup"
    echo "Permissions: $(ls -l netsetup | awk '{print $1, $3, $4}')"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./netsetup"
    echo
    echo -e "${YELLOW}Security Notes:${NC}"
    echo "  • Password is encrypted with AES-256-GCM"
    echo "  • Binary is bound to this specific Mac (hardware UUID)"
    echo "  • Script signature prevents tampering"
    echo "  • Credentials are decrypted in memory only"
    echo
    echo -e "${RED}⚠ Important:${NC}"
    echo "  • Keep netsetup binary secure (already chmod 700)"
    echo "  • Do NOT commit to version control"
    echo "  • Backup is saved as: SecureNetworkSetup.swift.bak"
    echo
    
    # Verify it works
    echo -e "${BLUE}Testing binary...${NC}"
    echo
    ./netsetup
    
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
