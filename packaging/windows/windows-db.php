<?php
declare(strict_types=1);
$config = json_decode(file_get_contents(getenv('LAUNDRY_CONFIG')), true, 512, JSON_THROW_ON_ERROR);
$mode = $argv[1] ?? 'ping';
try {
    $db = new PDO('mysql:host=127.0.0.1;port=' . $config['dbPort'] . ';charset=utf8mb4', 'root', $config['rootPassword'], [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    if ($mode === 'shutdown') { $db->exec('SHUTDOWN'); exit; }
    if ($mode === 'prepare') {
        $db->exec('USE laundry_queue');
        $db->exec(file_get_contents(__DIR__ . '/app/database/schema.sql'));
        // Seeding is tracked transactionally and never repeats on a user's database.
        $db->exec('CREATE TABLE IF NOT EXISTS installation_metadata (name VARCHAR(80) PRIMARY KEY, value VARCHAR(80) NOT NULL) ENGINE=InnoDB');
        if (!$db->query("SELECT COUNT(*) FROM installation_metadata WHERE name='seeded'")->fetchColumn()) {
            $db->beginTransaction();
            if (!(int)$db->query('SELECT COUNT(*) FROM students')->fetchColumn() && !(int)$db->query('SELECT COUNT(*) FROM washing_machines')->fetchColumn()) {
                $db->exec(file_get_contents(__DIR__ . '/app/database/seed.sql'));
            }
            $db->exec("INSERT INTO installation_metadata VALUES ('seeded','1')");
            $db->commit();
        }
    }
    if ($mode === 'test-database') {
        $db->exec('CREATE DATABASE IF NOT EXISTS laundry_installer_test CHARACTER SET utf8mb4');
        $db->exec("GRANT ALL ON laundry_installer_test.* TO 'laundry_app'@'127.0.0.1'");
    }
    echo "OK\n";
} catch (Throwable $error) {
    if ($mode !== 'ping') { fwrite(STDERR, $error->getMessage() . "\n"); }
    exit(1);
}
