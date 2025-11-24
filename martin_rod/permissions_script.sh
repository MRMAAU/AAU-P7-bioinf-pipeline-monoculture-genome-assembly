folder="/projects/students/Bio-25-BT-7-2/"

# create the folder if it doesn't exist already


# set group ownership
chown -R :bio_server_users@bio.aau.dk "$folder"

# If there are already files with weak permissions, correct them with:
chmod -R o-x "$folder"

# Ensure group can edit files/folders:
find "$folder" -type f -exec chmod 664 {} \;
find "$folder" -type d -exec chmod 775 {} \;

# set the setGID sticky bit to ensure new files and folders inherit group ownership
chmod 2775 "$folder"