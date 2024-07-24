#!/bin/bash
export PATH="/cygdrive/c/xampp/mysql/bin:$PATH"
source ~/.bashrc
# Fonction pour identifier la cause des erreurs dans un fichier XML
identify_error_cause() {
    FILE=$1
    ERROR_CAUSE="relancer la session"
    LINE_NUMBER=""

    # Check if XML file is well-formed
    if ! xmllint --noout "$FILE" 2>/dev/null; then
        ERROR_CAUSE="XML syntax error"
        LINE_NUMBER=$(xmllint --noout --stream "$FILE" 2>&1 | grep -o 'line [0-9]*' | head -1 | awk '{print $2}')
        echo "$ERROR_CAUSE at line $LINE_NUMBER"
        return
    fi

    # List of valid prefixes for WMI
    valid_prefixes="VF1|VF3|VF4|VF6|VF7|VF8|VF9|VFA|VP7|VJ1|VJ2|VN1|VNE|VNV|VNK|VR1|VR3|VR7|VSS|VSX|VS6|VS7|VSG|VSA|VSE|VWV"

    # XPath to extract WMI, VDS, and VIS elements
    WMI_elements=$(xmllint --xpath "//*[local-name()='WMI']/text()" "$FILE" 2>/dev/null)
    VDS_elements=$(xmllint --xpath "//*[local-name()='VDS']/text()" "$FILE" 2>/dev/null)
    VIS_elements=$(xmllint --xpath "//*[local-name()='VIS']/text()" "$FILE" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        ERROR_CAUSE="XML parsing error"
        echo "$ERROR_CAUSE"
        return
    fi

    line_number=1
    IFS=$'\n' # Set internal field separator to handle spaces in elements
    for wmi in $WMI_elements; do
        if ! echo "$wmi" | grep -qE "^(${valid_prefixes})"; then
            ERROR_CAUSE="Invalid WMI: $wmi at line $line_number"
            echo "$ERROR_CAUSE"
            return
        fi
        line_number=$((line_number + 1))
    done
    
    for vds in $VDS_elements; do
        if ! echo "$vds" | grep -qE "^[A-Za-z0-9]{6}$"; then
            ERROR_CAUSE="Invalid VDS: $vds at line $line_number"
            echo "$ERROR_CAUSE"
            return
        fi
        line_number=$((line_number + 1))
    done
    
    for vis in $VIS_elements; do
        if ! echo "$vis" | grep -qE "^[A-Za-z0-9]{8}$"; then
            ERROR_CAUSE="Invalid VIS: $vis at line $line_number"
            echo "$ERROR_CAUSE"
            return
        fi
        line_number=$((line_number + 1))
    done

    echo "$ERROR_CAUSE"
}
# Insert results into PSASM database
DB_HOST='localhost'
DB_PORT='3306'
DB_USER='root'
DB_PASS='password123'
DB_NAME='psasm'
TABLE_NAME='incident'
# Fonction pour trouver les fichiers en attente dans un répertoire spécifié
find_pending_files() {
    DIRECTORY="$1"
    cd "$DIRECTORY" || exit 1
    
    # Vérifiez si les variables d'environnement pour la base de données sont définies
    if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ]; then
        echo "Erreur : Les variables d'environnement pour la base de données ne sont pas toutes définies."
        return 1
    fi
    
    # Récupère la liste des fichiers en attente 
    files=$(find . -type f -size +0 -print)
    if [ -z "$files" ]; then
        echo "Aucun fichier en attente trouvé."
        return 0
    fi
    
    file_count=0
    CURRENT_DATE=$(date +%Y-%m-%d' '%H:%M:%S) # Prend la date actuelle
    
    for file in $files; do
        echo "Processing file: $file"
        
        # Identifie la cause de l'erreur pour le fichier
        error_cause=$(identify_error_cause "$file")
        
        # Si une erreur est identifiée autre que "relancer la session", génère une commande SQL
        if [ "$error_cause" != "relancer la session" ]; then
            echo "File $file error cause: $error_cause"
            
            # Génère la commande SQL pour insérer les données dans la base de données
            JOB=$(basename "$0" .sh)
            SQL_CMD="INSERT INTO incident (job, date, directory, error_cause, file,traited) VALUES ('$JOB', '$CURRENT_DATE', '$DIRECTORY', '$error_cause', '$file',0);"
            echo "SQL command: $SQL_CMD"
            file_count=$((file_count + 1))
            
            # Exécute la commande SQL et vérifie si elle réussit
            if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "$SQL_CMD"; then
                echo "Erreur lors de l'exécution de la commande SQL pour le fichier $file"
            fi
        else
            echo "File $file: No errors found."
        fi
    done
    
    return $file_count
}


# Répertoires à surveiller
DIRECTORIES=(
    '/cygdrive/c/Users/AdMin/Desktop/batch/users/cft00/envoi'
    '/cygdrive/c/Users/AdMin/Desktop/batch/users/rtr00/recept'
)

# Début du processus de vérification des fichiers en attente
echo "---------------------------------------------"
echo "Starting file verification process..."
echo "---------------------------------------------"

# Parcourt chaque répertoire pour trouver les fichiers en attente
for DIRECTORY in "${DIRECTORIES[@]}"; do
    find_pending_files "$DIRECTORY"
	RC=$((RC + $?))
done

# Exemple de logique pour déterminer si une alerte doit être envoyée
# Remplacer par votre propre logique pour envoyer des alertes si nécessaire

ALERT_MESSAGE="There are $RC pending files in the monitored directories as of $(date +%Y%m%d_%H%M%S)."

#!/bin/bash

# Chemin vers Notifu (adapté à votre configuration)
NOTIFU_PATH="/cygdrive/c/Users/AdMin/Downloads/notifu-1.7.1/notifu.exe"

# Exemple d'utilisation de Notifu pour afficher une notification
$NOTIFU_PATH /p "Incident detected" /t error /m "$ALERT_MESSAGE" 


echo "---------------------------------------------"
echo "Script execution completed."
echo "---------------------------------------------"
