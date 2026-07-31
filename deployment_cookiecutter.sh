#!/usr/bin/env bash
set -Eeuo pipefail
# default python binary used to install QLever if requested
PYTHON_BIN="${PYTHON_BIN:-python}"

# Temporary working directory for Cookiecutter
OUT="tmp"
SETTINGS="${SETTINGS:-omero-ontop-config}"
BASE_DIR="omero-ontop-mappings"

# 1) Ensure tmp exists  and remove any old content
if [[ -d "$OUT" ]]; then
  rm -rf "$OUT"
fi
mkdir -p "$OUT"

###############################################################################
# Optional: update OBDA mapping in an existing deployment
###############################################################################

echo "🔧 Ontop deployment helper"

while true; do
  read -r -p "Do you want to update the OBDA mapping of an existing deployment? [no]/yes: " UPDATE_OBDA
  UPDATE_OBDA=${UPDATE_OBDA:-no}
  UPDATE_OBDA_LC=$(echo "$UPDATE_OBDA" | tr '[:upper:]' '[:lower:]')

  case "$UPDATE_OBDA_LC" in
    yes|y)
      read -r -p "Existing deployment prefix/folder name: " DEPLOY_DIR
      DEPLOY_DIR="${DEPLOY_DIR%/}"

      if [[ -z "$DEPLOY_DIR" ]]; then
        echo "ERROR: Deployment folder cannot be empty." >&2
        exit 1
      fi

      if [[ ! -d "$DEPLOY_DIR" ]]; then
        echo "ERROR: Deployment folder '$DEPLOY_DIR' does not exist." >&2
        exit 1
      fi

      PREFIX="$(basename "$DEPLOY_DIR")"
      DEST_OBDA="${DEPLOY_DIR}/${PREFIX}.obda"

      if [[ ! -f "$DEST_OBDA" ]]; then
        echo "ERROR: Cannot find deployed OBDA file: $DEST_OBDA" >&2
        exit 1
      fi

      SITE_URI=$(grep -E "^${PREFIX}:[[:space:]]+" "$DEST_OBDA" | head -n 1 | awk '{print $2}')
      if [[ -z "${SITE_URI:-}" ]]; then
        echo " ERROR: Could not extract site_uri from $DEST_OBDA" >&2
        echo "   Expected a prefix line like:" >&2
        echo "   ${PREFIX}:   https://example.org/site/" >&2
        exit 1
      fi

      SITE=$(echo "$SITE_URI" | sed -e 's/[\/,#]$//')

      PUBLICCOND=$(grep -Eo 'where child[[:space:]]*([=<>!]+)[[:space:]]*[0-9]+' "$DEST_OBDA" \
        | head -n 1 \
        | sed -E 's/.*child[[:space:]]*//; s/[[:space:]]//g')

      if [[ -z "${PUBLICCOND:-}" ]]; then
        echo " ERROR: Could not extract publiccond from $DEST_OBDA" >&2
        echo "   Expected a SQL fragment like:" >&2
        echo "   where child=2" >&2
        echo "   or:" >&2
        echo "   where child>=0" >&2
        exit 1
      fi

      echo ""
      echo "The update will use these detected values:"
      echo "   deployment : $DEPLOY_DIR"
      echo "   prefix     : $PREFIX"
      echo "   site_uri   : $SITE_URI"
      echo "   publiccond : $PUBLICCOND"
      echo ""

      while true; do
        read -r -p "Continue with OBDA update? [yes]/no: " CONFIRM_UPDATE
        CONFIRM_UPDATE=${CONFIRM_UPDATE:-yes}
        CONFIRM_UPDATE_LC=$(echo "$CONFIRM_UPDATE" | tr '[:upper:]' '[:lower:]')

        case "$CONFIRM_UPDATE_LC" in
          yes|y)
            break
            ;;
          no|n)
            echo "Update cancelled."
            exit 0
            ;;
          *)
            echo "Please answer 'yes' or 'no' (or press Enter for 'yes')."
            ;;
        esac
      done

      echo ""
      echo " Preparing OBDA template from latest repository mapping ..."

      if [[ -f "prepare_obda_template.py" ]]; then
        if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
          "$PYTHON_BIN" prepare_obda_template.py
        else
          echo " ERROR: Python interpreter '$PYTHON_BIN' not found."
          exit 1
        fi
      else
        echo " ERROR: prepare_obda_template.py not found."
        exit 1
      fi

      CC_ARGS=(
        "templates"
        -o "$OUT"
        --no-input
        deploy_name="$SETTINGS"
        jdbc_user="dummy"
        jdbc_password="dummy"
        db_host="localhost"
        prefix="$PREFIX"
        site_uri="$SITE_URI"
        site="$SITE"
        publiccond="$PUBLICCOND"
      )

      echo ""
      echo "  Regenerating OBDA with Cookiecutter ..."
      cookiecutter "${CC_ARGS[@]}"

      GEN_DIR=""
      for d in "$OUT"/*; do
        if [[ -d "$d" ]]; then
          GEN_DIR="$d"
          break
        fi
      done

      if [[ -z "$GEN_DIR" ]]; then
        echo " ERROR: No generated directory found in '$OUT'" >&2
        exit 1
      fi

      SRC_OBDA="$GEN_DIR/omero-ontop-mappings.obda"

      if [[ ! -f "$SRC_OBDA" ]]; then
        echo " ERROR: Generated OBDA file not found at $SRC_OBDA" >&2
        exit 1
      fi

      #########################################################################
      # Update OBDA mapping
      #########################################################################

      BACKUP_OBDA="${DEST_OBDA}.backup.$(date +%Y%m%d-%H%M%S)"
      cp -v "$DEST_OBDA" "$BACKUP_OBDA"
      cp -v "$SRC_OBDA" "$DEST_OBDA"

      echo ""
      echo " Existing deployment OBDA updated:"
      echo "   $DEST_OBDA"
      echo ""
      echo "Backup created:"
      echo "   $BACKUP_OBDA"

      #########################################################################
      # Optionally update ontology (.ttl)
      #########################################################################

      SRC_TTL="${BASE_DIR}/omero-ontop-mappings.ttl"
      DEST_TTL="${DEPLOY_DIR}/${PREFIX}.ttl"

      if [[ -f "$SRC_TTL" && -f "$DEST_TTL" ]]; then

        while true; do
          read -r -p "Also update ontology file (.ttl)? [yes]/no: " UPDATE_TTL
          UPDATE_TTL=${UPDATE_TTL:-yes}
          UPDATE_TTL_LC=$(echo "$UPDATE_TTL" | tr '[:upper:]' '[:lower:]')

          case "$UPDATE_TTL_LC" in
            yes|y)
              BACKUP_TTL="${DEST_TTL}.backup.$(date +%Y%m%d-%H%M%S)"
              cp -v "$DEST_TTL" "$BACKUP_TTL"
              cp -v "$SRC_TTL" "$DEST_TTL"

              echo ""
              echo " Existing deployment ontology updated:"
              echo "   $DEST_TTL"
              echo ""
              echo "Backup created:"
              echo "   $BACKUP_TTL"
              break
              ;;

            no|n)
              echo "Skipping ontology update."
              break
              ;;

            *)
              echo "Please answer 'yes' or 'no' (or press Enter for 'yes')."
              ;;
          esac
        done

      else
        echo ""
        echo " Ontology update skipped."
        echo "   Source or destination ontology file not found."
      fi

      echo ""
      echo "Next steps:"
      echo "  cd $DEPLOY_DIR"
      echo "  ./${PREFIX}-ontop-materialize.sh"
      echo ""
      echo "If using QLever, reindex after materializing."
      exit 0
      ;;
    no|n)
      break
      ;;
    *)
      echo "Please answer 'yes' or 'no' (or press Enter for 'no')."
      ;;
  esac
done

echo " Ontop deployment configuration"

# --- Ask user for values
echo "Please enter database username (postgres user), password, and its URL, e.g.: localhost or host.example.com"
read -r -p "Postgres user: " JDBC_USER
while [[ -z "$JDBC_USER" ]]; do
  echo "user cannot be empty."
  read -r -p "Postgres user: " JDBC_USER
done

read -r -s -p "DB password: " JDBC_PASS
echo
while [[ -z "$JDBC_PASS" ]]; do
  echo "DB password cannot be empty."
  read -r -s -p "DB password: " JDBC_PASS
  echo
done

read -r -p "DB host [localhost]: " DB_HOST
DB_HOST=${DB_HOST:-localhost}
echo ""
echo "Enter PREFIX: RDF prefix for site instance, e.g. \"iob\"."
read -r -p "prefix [ex]: " PREFIX
PREFIX=${PREFIX:-ex}
echo "Enter URI: URI of site instance including trailing slash or #, e.g. \"https://institute.of.bioimaging.com/\"."
read -r -p "site_uri [https://example.org/]: " SITE_URI
SITE_URI=${SITE_URI:-https://example.org/}
SITE=$(echo "$SITE_URI" | sed -e 's/[\/,#]$//')
echo ""
echo "Setting public data mapping:"
echo "  - YES  → Only data of the public user is mapped (enter that user's OMERO ID)."
echo "  - NO   → Enter SQL Condition on user_id that must evaluate to true to map object (e.g. \"=2\" or \">=0\")."
# Ask if only public data is mapped
while true; do
  read -r -p "Only public data will be mapped to RDF? [yes]/no: " PUBLIC_ONLY
  PUBLIC_ONLY=${PUBLIC_ONLY:-yes}
  PUBLIC_ONLY_LC=$(echo "$PUBLIC_ONLY" | tr '[:upper:]' '[:lower:]')

  case "$PUBLIC_ONLY_LC" in
    yes|y)
      # Public-only mode: ask for OMERO ID of public user
      while true; do
        read -r -p "Enter ID of the public OMERO user. ID = " PUBLIC_USER_ID
        if [[ "$PUBLIC_USER_ID" =~ ^[0-9]+$ ]]; then
          PUBLICCOND="=$PUBLIC_USER_ID"
          break
        else
          echo "❗ Please enter a valid integer OMERO user ID (e.g. 2)."
        fi
      done
      break
      ;;
    no|n)
      # Custom SQL condition
      read -r -p "Enter SQL condition on user_id (e.g. \"=2\", \">=0\") [>=0]: " PUBLICCOND
      PUBLICCOND=${PUBLICCOND:->=0}
      break
      ;;
    *)
      echo "Please answer 'yes' or 'no' (or press Enter for 'yes')."
      ;;
  esac
done

###############################################################################
# QLever SPARQL endpoint questions (both asked here, before Cookiecutter)
###############################################################################

CREATE_QLEVER_ENDPOINT="no"
INSTALL_QLEVER="no"

echo ""
echo "QLever SPARQL endpoint setup:"
while true; do
  read -r -p "Do you want to create a QLever SPARQL endpoint serving the materialized RDF? [no]/yes: " ENABLE_QLEVER
  ENABLE_QLEVER=${ENABLE_QLEVER:-no}
  ENABLE_QLEVER_LC=$(echo "$ENABLE_QLEVER" | tr '[:upper:]' '[:lower:]')

  case "$ENABLE_QLEVER_LC" in
    yes|y)
      CREATE_QLEVER_ENDPOINT="yes"
      break
      ;;
    no|n)
      CREATE_QLEVER_ENDPOINT="no"
      break
      ;;
    *)
      echo "Please answer 'yes' or 'no' (or press Enter for 'no')."
      ;;
  esac
done

if [[ "$CREATE_QLEVER_ENDPOINT" == "yes" ]]; then
  QLEVER_DIR_PREVIEW="${PREFIX}/qlever"
  while true; do
    read -r -p "Do you want to install QLever? [no]/yes: " INSTALL_QLEVER_ANSWER
    INSTALL_QLEVER_ANSWER=${INSTALL_QLEVER_ANSWER:-no}
    INSTALL_QLEVER_LC=$(echo "$INSTALL_QLEVER_ANSWER" | tr '[:upper:]' '[:lower:]')

    case "$INSTALL_QLEVER_LC" in
      yes|y)
        INSTALL_QLEVER="yes"
        break
        ;;
      no|n)
        INSTALL_QLEVER="no"
        break
        ;;
      *)
        echo "Please answer 'yes' or 'no' (or press Enter for 'no')."
        ;;
    esac
  done
fi
## Use most recent mapping file to create template for cookiecutter
echo ""
echo "🔄 Preparing OBDA template for Cookiecutter ..."

if [[ -f "prepare_obda_template.py" ]]; then
  if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    "$PYTHON_BIN" prepare_obda_template.py
  else
    echo "❌ ERROR: Python interpreter '$PYTHON_BIN' not found."
    echo "   Set PYTHON_BIN before running this script, e.g.:"
    echo "   PYTHON_BIN=python3 ./deployment_cookiecutter.sh"
    exit 1
  fi
else
  echo "⚠️ WARNING: prepare_obda_template.py not found — OBDA template not updated."
fi

# 2) Build cookiecutter args
CC_ARGS=(
  "templates"
  -o "$OUT"
  --no-input
  deploy_name="$SETTINGS"
  jdbc_user="$JDBC_USER"
  jdbc_password="$JDBC_PASS"
  db_host="$DB_HOST"
  prefix="$PREFIX"
  site_uri="$SITE_URI"
  site="$SITE"
  publiccond="$PUBLICCOND"
)
echo ""
echo "⚙️  Running Cookiecutter ..."
cookiecutter "${CC_ARGS[@]}"

# 3) Find the generated project directory inside $OUT
GEN_DIR=""
for d in "$OUT"/*; do
  if [[ -d "$d" ]]; then
    GEN_DIR="$d"
    break
  fi
done

if [[ -z "$GEN_DIR" ]]; then
  echo "❌ ERROR: No generated directory found in '$OUT'" >&2
  exit 1
fi

SRC_PROP="$GEN_DIR/omero-ontop-mappings.properties"
SRC_OBDA="$GEN_DIR/omero-ontop-mappings.obda"
SRC_ENV="$GEN_DIR/deploy.env"

if [[ ! -f "$SRC_PROP" ]]; then
  echo "❌ ERROR: Generated properties file not found at $SRC_PROP" >&2
  exit 1
fi

if [[ ! -f "$SRC_OBDA" ]]; then
  echo "❌ ERROR: Generated OBDA file not found at $SRC_OBDA" >&2
  exit 1
fi

if [[ ! -f "$SRC_ENV" ]]; then
  echo "❌ ERROR: deploy.env not found at $SRC_ENV" >&2
  exit 1
fi

# 4) Load PREFIX, SITE_URI, PUBLICCOND from deploy.env

. "$SRC_ENV"

if [[ -z "$PREFIX" ]]; then
  echo "❌ ERROR: PREFIX is empty after sourcing deploy.env" >&2
  exit 1
fi

echo "📁 Creating deployment folder '$PREFIX'..."
mkdir -p "$PREFIX"

###############################################################################
# QLever folder + optional venv-local install
###############################################################################
if [[ "$CREATE_QLEVER_ENDPOINT" == "yes" ]]; then
  QLEVER_DIR="${PREFIX}/qlever"
  INSTALL_LOG="$QLEVER_DIR/qlever_install.log"

  echo "📁 Creating QLever subdirectory: $QLEVER_DIR"
  mkdir -p "$QLEVER_DIR"

  if [[ "$INSTALL_QLEVER" == "yes" ]]; then
    echo "⬇️ Installing QLever into current virtual environment."
    if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
      if "$PYTHON_BIN" -m pip install qlever --quiet >"$INSTALL_LOG" 2>&1; then ## use quiet flag. Report only if error occurs
        echo "   QLever installed successfully. (Details in $INSTALL_LOG)"
      else
        echo "⚠️ QLever installation failed. Showing log:"
        echo "------------------------------------------------------------"
        cat "$INSTALL_LOG"
        echo "------------------------------------------------------------"
      fi
    else
      echo "⚠️ '${PYTHON_BIN}' command not found. Please ensure your virtual environment is activated"
      echo "   or set PYTHON_BIN to the correct interpreter before running this script."
    fi
  else
    echo "Skipping QLever installation. Directory '$QLEVER_DIR' is ready for manual setup."
  fi
fi

# 5) Copy / rename files into deployment folder

# Properties from Cookiecutter (already escaped & chmodded by hook)
install -m 600 "$SRC_PROP" "${PREFIX}/${PREFIX}.properties"

# TTL from base dir, renamed
if [[ -f "$BASE_DIR/omero-ontop-mappings.ttl" ]]; then
  cp -v "$BASE_DIR/omero-ontop-mappings.ttl" "${PREFIX}/${PREFIX}.ttl"
fi

# Catalog + portal
if [[ -f "$BASE_DIR/catalog-v001.xml" ]]; then
  cp -v "$BASE_DIR/catalog-v001.xml" "${PREFIX}/."
fi

if [[ -f "$BASE_DIR/portal.toml" ]]; then
  cp -v "$BASE_DIR/portal.toml" "${PREFIX}/."
fi

# OBDA from Cookiecutter, renamed
cp -v "$SRC_OBDA" "${PREFIX}/${PREFIX}.obda"

# Deployment values, useful for future update operations
cp -v "$SRC_ENV" "${PREFIX}/deploy.env"

# Ontop launch script
if [[ -f "$BASE_DIR/omero-ontop.sh" ]]; then
  sed "s/omero-ontop-mappings/${PREFIX}/g" "$BASE_DIR/omero-ontop.sh" > "${PREFIX}/${PREFIX}-ontop-endpoint.sh"
  chmod +x "${PREFIX}/${PREFIX}-ontop-endpoint.sh"
fi

# 6) Print confirmation (no password)
DEST_PROP="${PREFIX}/${PREFIX}.properties"

jdbc_user_final=$(grep -E '^jdbc\.user=' "$DEST_PROP" | sed 's/^jdbc\.user=//')
jdbc_url=$(grep -E '^jdbc\.url=' "$DEST_PROP" | sed 's/^jdbc\.url=//; s/\\:/:/g')
db_host_final=$(echo "$jdbc_url" | sed 's#^jdbc:postgresql://##; s/:5432.*$//')


echo ""
echo " Deployment folder created: $PREFIX/"

echo ""
echo "   Postgres user : $jdbc_user_final"
echo "   db_host   : $db_host_final"
echo "   jdbc.url  : $jdbc_url"
echo "   prefix    : $PREFIX"
echo "   site_uri  : $SITE_URI"
echo "   publiccond: $PUBLICCOND"
if [[ "$CREATE_QLEVER_ENDPOINT" == "yes" ]]; then
  if [[ "$INSTALL_QLEVER" == "yes" ]]; then
    echo "   qlever    : directory '$PREFIX/qlever' created, '${PYTHON_BIN} -m pip install qlever' attempted"
  else
    echo "   qlever    : directory '$PREFIX/qlever' created (QLever not installed by script)"
  fi
fi
echo ""
echo "To start ontop endpoint:"
echo "  cd $PREFIX"
echo "  ./${PREFIX}-ontop-endpoint.sh"
echo ""

################################################################################
# 7) Create materialization script in same directory as deployment folder
################################################################################

MAT_DIR=${PREFIX}
MAT_SCRIPT="${MAT_DIR}/${PREFIX}-ontop-materialize.sh"

cat > "$MAT_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

# Materialize VKG

# Directory of this script (materialize/)
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
# Project root = parent of materialize/
BASE_DIR="\$(cd "\$SCRIPT_DIR/.." && pwd)"

# Path to ONTOP CLI binary (adjust if needed)
ONTOPBIN="\$BASE_DIR/ontop-cli/ontop"

# Deployment folder name injected by cookiecutter
DEPLOY_DIR="\$BASE_DIR/${PREFIX}"

MAPPING="\$DEPLOY_DIR/${PREFIX}.obda"
ONTOLOGY="\$DEPLOY_DIR/${PREFIX}.ttl"
PROPERTIES="\$DEPLOY_DIR/${PREFIX}.properties"

OUTPUT="\$SCRIPT_DIR/materialized_data.ttl"

date
"\$ONTOPBIN" materialize \\
  --mapping "\$MAPPING" \\
  --ontology "\$ONTOLOGY" \\
  --properties "\$PROPERTIES" \\
  --format turtle \\
  --output "\$OUTPUT"
date
EOF

chmod +x "$MAT_SCRIPT"

echo ""
echo " Materialization script created:"
echo "   $MAT_SCRIPT"
echo ""
###############################################################################
# QLever: Copy qlever scripts
###############################################################################
if [[ "$CREATE_QLEVER_ENDPOINT" == "yes" ]]; then

  QLEVER_SRC="./qlever"
  QLEVER_DST="${PREFIX}/qlever"

  if [[ ! -d "$QLEVER_SRC" ]]; then
    echo "⚠️ WARNING: qLever folder not found at $QLEVER_SRC"
  else
    echo "📁 Copying QLever scripts..."
    mkdir -p "$QLEVER_DST"
    cp -a "$QLEVER_SRC"/. "$QLEVER_DST"/ #portable for Mac and linux. Avoids extra unnecessary subdirectory on ubuntu
    chmod +x "$QLEVER_DST/"*.sh 2>/dev/null || true
  fi

  echo ""
  echo " QLever setup information"
  echo ""
  echo "To use the QLever SPARQL endpoint, follow these steps:"
  echo ""
  echo "1️⃣ Change into the QLever directory:"
  echo "   cd ${PREFIX}/qlever"
  echo ""
  echo "2️⃣ Index the materialized RDF data:"
  echo "   ./reindex_ome_data.sh"
  echo ""
  echo "  This will create the QLever index files inside:"
  echo "    ${PREFIX}/qlever/index_output/"
  echo ""
  echo "3️⃣ Start the QLever server:"
  echo "   ./start_qlever.sh"
  echo ""
  echo "4️⃣ Start the QLever Web UI:"
  echo "   ./launch_qlever-ui-mpiebkg.sh"
  echo ""
fi