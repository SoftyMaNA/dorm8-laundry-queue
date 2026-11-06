<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/bootstrap.php';

$db = database();
$db->exec(file_get_contents(dirname(__DIR__) . '/database/schema.sql'));
if (in_array('--seed', $argv, true)) {
    if ((int) $db->query('SELECT COUNT(*) FROM washing_machines')->fetchColumn() !== 0
        || (int) $db->query('SELECT COUNT(*) FROM students')->fetchColumn() !== 0
        || (int) $db->query('SELECT COUNT(*) FROM staff')->fetchColumn() !== 0) {
        throw new RuntimeException('Начальные данные добавляются только в пустые справочники.');
    }
    $db->exec(file_get_contents(dirname(__DIR__) . '/database/seed.sql'));
}
echo "Структура базы данных подготовлена.\n";
