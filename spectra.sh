#!/bin/bash
set -e

INSTALL_DIR="${HOME}/.spectra/app"
CONFIG_FILE="${HOME}/.spectra/config"
REPO_URL="git@github.com:byfusion/spectra.git"
DEV_MODE=false

# Parse arguments
for arg in "$@"; do
    case "${arg}" in
        --dev) DEV_MODE=true;;
    esac
done

if [ "${DEV_MODE}" = true ]; then
    echo "=== Spectra Installation (dev) ==="
else
    echo "=== Spectra Installation ==="
fi

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     PLATFORM=Linux;;
    Darwin*)    PLATFORM=Mac;;
    *)          echo "Unsupported OS: ${OS}"; exit 1;;
esac
echo "Detected platform: ${PLATFORM}"

# Check/Install UV
if ! command -v uv &> /dev/null; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.cargo/bin:${PATH}"
fi
echo "✓ uv installed"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "⚠️  Node.js not found. Please install Node.js 18+ from:"
    echo "   https://nodejs.org/"
    exit 1
fi
NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "${NODE_VERSION}" -lt 18 ]; then
    echo "⚠️  Node.js ${NODE_VERSION} is too old. Please upgrade to 18+."
    exit 1
fi
echo "✓ Node.js $(node --version)"

# Check ffmpeg (required)
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "❌ ffmpeg/ffprobe not found. Please install ffmpeg first:"
    if [ "${PLATFORM}" = "Mac" ]; then
        echo "   brew install ffmpeg"
    else
        echo "   sudo apt-get install ffmpeg"
    fi
    exit 1
fi
echo "✓ ffmpeg $(ffmpeg -version | head -n1 | cut -d' ' -f3)"


# Clone repository
if [ -d "${INSTALL_DIR}" ]; then
    echo "Spectra already installed at ${INSTALL_DIR}"
    read -p "Reinstall? (y/N): " -n 1 -r < /dev/tty
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "${INSTALL_DIR}"
    else
        exit 0
    fi
fi

if [ "${DEV_MODE}" = true ]; then
    echo "Installing Spectra (dev, latest commit)..."
    git clone --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
else
    # Fetch latest release tag via git (no API rate limits)
    echo "Fetching latest release version..."
    LATEST_TAG=$(git ls-remote --tags --sort=-v:refname "${REPO_URL}" "v*" | grep -v '\^{}' | head -n1 | sed 's/.*refs\/tags\///')
    if [ -z "${LATEST_TAG}" ]; then
        echo "❌ No release found. Please check https://github.com/byfusion/spectra/releases"
        exit 1
    fi
    echo "Installing Spectra ${LATEST_TAG}..."
    git clone --branch "${LATEST_TAG}" --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
fi

# Save install path
mkdir -p "$(dirname "${CONFIG_FILE}")"
echo "${INSTALL_DIR}" > "${CONFIG_FILE}"

# Install Python dependencies
echo "Installing Python dependencies..."
cd "${INSTALL_DIR}"
uv sync

# Build frontend
echo "Building frontend..."
cd "${INSTALL_DIR}/web"

# Use npm mirror for China
if [[ "${LANG}" == *"zh_CN"* ]] || [[ "${LC_ALL}" == *"zh_CN"* ]]; then
    echo "Detected Chinese environment, using npm mirror..."
    npm install --registry=https://registry.npmmirror.com
else
    npm install
fi

npm run build

# Install global command
echo "Installing global command..."
cd "${INSTALL_DIR}"
uv tool install -e .

# Configuration wizard
echo ""
echo "=== Configuration Wizard ==="
echo ""

# API Key (required)
while true; do
    read -p "Enter your API Key (required): " api_key < /dev/tty
    if [ -n "$api_key" ]; then
        break
    fi
    echo "⚠️  API Key is required!"
done

# API Host (optional)
read -p "API Host [yunwu.ai]: " api_host < /dev/tty
api_host=${api_host:-yunwu.ai}

# ComfyUI Host (optional)
read -p "ComfyUI Host [http://127.0.0.1:8188]: " comfyui_host < /dev/tty
comfyui_host=${comfyui_host:-http://127.0.0.1:8188}

# Generate .env file
echo "Generating configuration..."
cd "${INSTALL_DIR}"
cp .env.example .env
sed -i.bak "s/DEFAULT_API_KEY=.*/DEFAULT_API_KEY=${api_key}/" .env
sed -i.bak "s/YUNWU_HOST=.*/YUNWU_HOST=${api_host}/" .env
sed -i.bak "s|COMFYUI_HOST=.*|COMFYUI_HOST=${comfyui_host}|" .env
rm -f .env.bak
echo "✓ Configuration saved"

# Create workspace directory
mkdir -p "${HOME}/.spectra/workspace"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Quick start:"
echo "  spectra start"
echo ""
echo "Commands:"
echo "  spectra start          - Start server"
echo "  spectra config         - Edit configuration"
echo "  spectra update         - Update to latest version"
echo "  spectra info           - Show installation info"
echo "  spectra --help         - Show all commands"
echo ""





