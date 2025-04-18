#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
API_URL="https://tkinstall.emodev.link/api"

show_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

show_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

show_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

validate_token() {
    local token=$1
    show_message "Validando token de instalación..."
    
    response=$(curl -s -H "x-api-token: $token" "$API_URL/validate")
    
    if echo "$response" | grep -q "valid\":true"; then
        customer_name=$(echo "$response" | grep -o '"customer":"[^"]*' | sed 's/"customer":"//')
        show_success "Token válido. Bienvenido, $customer_name"
        return 0
    else
        error_msg=$(echo "$response" | grep -o '"error":"[^"]*' | sed 's/"error":"//')
        show_error "Token inválido: $error_msg"
        return 1
    fi
}

download_installer() {
    local token=$1
    show_message "Descargando script de instalación..."
    
    response=$(curl -s -w "%{http_code}" -H "x-api-token: $token" "$API_URL/file/installer.sh")
    http_code=$(tail -n1 <<< "$response")
    content=$(sed '$ d' <<< "$response")
    
    if [ "$http_code" -ne 200 ]; then
        show_error "Error al descargar el script de instalación (Código $http_code)"
        return 1
    fi
    
    echo "$content" > "./installer.sh"
    chmod +x "./installer.sh"
    
    if [ $? -eq 0 ]; then
        show_success "Script de instalación descargado correctamente"
        return 0
    else
        show_error "Error al guardar el script de instalación"
        return 1
    fi
}

cleanup() {
    show_message "Limpiando archivos temporales..."
    
    # Eliminar el script de instalación
    if [ -f "./installer.sh" ]; then
        rm -f "./installer.sh"
        show_warning "Script de instalación eliminado"
    fi
    
    # Eliminar cualquier archivo de stack descargado
    if [ -d "/home/docker" ]; then
        find /home/docker -name "*-stack.yml" -type f -delete
        find /home/docker -name "*-deploy.yml" -type f -delete
        show_warning "Archivos de configuración de stack eliminados"
    fi
}

# Capturar señales de terminación para asegurarnos de hacer limpieza
trap cleanup SIGINT SIGTERM

if [ "$EUID" -ne 0 ]; then
    show_error "Este script debe ejecutarse como root"
    exit 1
fi

# Mostrar encabezado
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}   Instalador Automático de Herramientas Docker    ${NC}"
echo -e "${GREEN}==================================================${NC}\n"

read -p "Ingrese su token de instalación: " API_TOKEN
if [ -z "$API_TOKEN" ]; then
    show_error "El token no puede estar vacío"
    exit 1
fi

if ! validate_token "$API_TOKEN"; then
    show_error "No se puede continuar con la instalación. Token inválido."
    exit 1
fi

if ! download_installer "$API_TOKEN"; then
    show_error "No se pudo descargar el script de instalación."
    exit 1
fi

show_message "Iniciando la instalación..."

# Ejecutar el instalador
./installer.sh --token "$API_TOKEN"
INSTALL_RESULT=$?

# Verificar si la instalación fue exitosa
if [ $INSTALL_RESULT -eq 0 ]; then
    show_success "Instalación completada exitosamente"
    
    # Limpieza controlada en caso de éxito
    cleanup
    
    echo -e "\n${GREEN}==================================================${NC}"
    echo -e "${GREEN}          Instalación finalizada                   ${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo -e "Los servicios han sido instalados correctamente."
    exit 0
else
    show_error "La instalación ha fallado. Revise los logs para más información."
    
    # Limpieza agresiva en caso de fallo
    show_message "Limpiando archivos de instalación debido al fallo..."
    cleanup
    
    # Eliminar cualquier archivo o directorio adicional que se haya creado y no sea necesario mantener
    if [ -d "/home/docker" ]; then
        find /home/docker -type f -name ".env.*" -delete
        find /home/docker -type d -empty -delete 2>/dev/null
        show_warning "Se han eliminado archivos de configuración adicionales"
    fi
    
    echo -e "\n${RED}==================================================${NC}"
    echo -e "${RED}          Instalación fallida                      ${NC}"
    echo -e "${RED}==================================================${NC}"
    echo -e "Deberá volver a ejecutar el script de instalación."
    exit 1
fi
