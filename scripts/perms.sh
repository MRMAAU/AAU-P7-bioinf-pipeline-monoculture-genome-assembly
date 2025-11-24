# Manual permission fix
PROJECT_ROOT="/projects/students/Bio-25-BT-7-2/P7"

# Set group ownership
chgrp -R bio_server_users@bio.aau.dk "${PROJECT_ROOT}/shared_conda_envs"
chgrp -R bio_server_users@bio.aau.dk "${PROJECT_ROOT}/shared_resources"

# Set permissions (read, write, execute for group)
chmod -R g+rwX "${PROJECT_ROOT}/shared_conda_envs"
chmod -R g+rwX "${PROJECT_ROOT}/shared_resources"

# Set setgid bit (new files inherit group)
find "${PROJECT_ROOT}/shared_conda_envs" -type d -exec chmod g+s {} \;
find "${PROJECT_ROOT}/shared_resources" -type d -exec chmod g+s {} \;

# Verify
ls -la "${PROJECT_ROOT}/shared_conda_envs"
# Should show: drwxrws--- ... bio_server_users@bio.aau.d