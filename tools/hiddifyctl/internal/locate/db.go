package locate

import (
	"database/sql"
	"fmt"
	"net/url"

	_ "modernc.org/sqlite"
)

// ActiveProfile reads the single active profile (id + name) from the app's
// drift sqlite database. drift stores the boolean `active` column as 0/1.
// Profile names may be percent-encoded by the app, so they are decoded for
// display.
func ActiveProfile(dbPath string) (id, name string, err error) {
	if dbPath == "" {
		return "", "", fmt.Errorf("no db path (pass --db-path)")
	}
	db, err := sql.Open("sqlite", dbPath+"?_pragma=busy_timeout(3000)")
	if err != nil {
		return "", "", err
	}
	defer db.Close()

	row := db.QueryRow("SELECT id, name FROM profile_entries WHERE active = 1 LIMIT 1")
	if err := row.Scan(&id, &name); err != nil {
		return "", "", fmt.Errorf("read active profile from %s: %w", dbPath, err)
	}
	if decoded, derr := url.PathUnescape(name); derr == nil {
		name = decoded
	}
	return id, name, nil
}
