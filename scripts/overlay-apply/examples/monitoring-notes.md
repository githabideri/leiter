# The monitoring topology

The stack runs on @@PRIMARY_HOST@@ at the @@SITE_PRIMARY@@ site.
The offsite copy is on @@BACKUP_HOST@@ at @@SITE_OFFSITE@@,
reached over @@TUNNEL_NAME@@.

The scrape config reads from @@DB_URL@@.
The dashboard map variable is @@SITE_MAP@@.
