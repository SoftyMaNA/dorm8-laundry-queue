<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/bootstrap.php';

// Защита от случайного запуска проверок на рабочей базе.
if (!str_ends_with(getenv('DB_DATABASE') ?: '', '_test')) {
    fwrite(STDERR, "Укажите отдельную DB_DATABASE с суффиксом _test.\n");
    exit(2);
}
$db = database();
$db->exec(file_get_contents(dirname(__DIR__) . '/database/schema.sql'));

function check(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

function scalar(PDO $db, string $sql, array $params): mixed
{
    $query = $db->prepare($sql);
    $query->execute($params);
    return $query->fetchColumn();
}

function mustReject(callable $operation, string $expected): void
{
    try {
        $operation();
    } catch (DomainException $error) {
        check($error->getMessage() === $expected, 'Отклонено по другой причине: ' . $error->getMessage());
        return;
    }
    throw new RuntimeException('Ожидался отказ, но операция выполнена.');
}

$tests = [
    'Свободное время успешно бронируется' => function (PDO $db, BookingService $service, int $student, array $machines): void {
        $id = $service->book($student, $machines[0], '2030-01-15 10:00:00', '2030-01-15 11:00:00');
        check($id > 0, 'Не выдан номер бронирования.');
        check(scalar($db, 'SELECT status FROM bookings WHERE id_booking = ?', [$id]) === 'active', 'Запись не сохранена активной.');
        check((int) scalar($db, 'SELECT COUNT(*) FROM notifications WHERE id_student = ?', [$student]) === 1, 'Нет уведомления о создании.');
    },
    'Пересечение отклоняется, соседнее время разрешено' => function (PDO $db, BookingService $service, int $student, array $machines): void {
        $service->book($student, $machines[0], '2030-01-15 10:00:00', '2030-01-15 11:00:00');
        // Проверяем частичное пересечение, полное совпадение и охватывающий интервал.
        foreach ([['10:30:00', '11:30:00'], ['10:00:00', '11:00:00'], ['09:00:00', '12:00:00']] as [$start, $end]) {
            mustReject(fn() => $service->book($student, $machines[0], "2030-01-15 {$start}", "2030-01-15 {$end}"), 'Выбранное время уже занято.');
        }
        check((int) scalar($db, 'SELECT COUNT(*) FROM bookings WHERE id_machine = ?', [$machines[0]]) === 1, 'После отказа осталась лишняя запись.');
        $service->book($student, $machines[0], '2030-01-15 11:00:00', '2030-01-15 12:00:00');
        $service->book($student, $machines[1], '2030-01-15 10:00:00', '2030-01-15 11:00:00');
        check((int) scalar($db, 'SELECT COUNT(*) FROM bookings WHERE id_student = ?', [$student]) === 3, 'Соседний интервал или другая машина ошибочно заблокированы.');
    },
    'Машина на обслуживании недоступна' => function (PDO $db, BookingService $service, int $student, array $machines): void {
        $db->prepare('UPDATE washing_machines SET is_available = 0 WHERE id_machine = ?')->execute([$machines[0]]);
        mustReject(fn() => $service->book($student, $machines[0], '2030-01-15 10:00:00', '2030-01-15 11:00:00'), 'Машина недоступна или находится на обслуживании.');
        check((int) scalar($db, 'SELECT COUNT(*) FROM bookings WHERE id_machine = ?', [$machines[0]]) === 0, 'Создана запись на недоступную машину.');
        check((int) scalar($db, 'SELECT COUNT(*) FROM notifications WHERE id_student = ?', [$student]) === 0, 'При отказе отправлено уведомление о создании.');
    },
    'Отмена освобождает время и сохраняет историю' => function (PDO $db, BookingService $service, int $student, array $machines): void {
        $old = $service->book($student, $machines[0], '2030-01-15 10:00:00', '2030-01-15 11:00:00');
        $service->cancel($old);
        check(scalar($db, 'SELECT status FROM bookings WHERE id_booking = ?', [$old]) === 'cancelled', 'История отмены не сохранена.');
        $new = $service->book($student, $machines[0], '2030-01-15 10:00:00', '2030-01-15 11:00:00');
        check($new !== $old, 'Повторная запись должна получить новый номер.');
        check((int) scalar($db, "SELECT COUNT(*) FROM bookings WHERE id_machine = ? AND status = 'active'", [$machines[0]]) === 1, 'Неверное число активных записей.');
        check((int) scalar($db, 'SELECT COUNT(*) FROM notifications WHERE id_student = ?', [$student]) === 3, 'Не сохранены уведомления о двух записях и отмене.');
    },
];

$case = isset($argv[1]) ? filter_var($argv[1], FILTER_VALIDATE_INT) : null;
if (isset($argv[1]) && ($case === false || $case < 1 || $case > 4)) {
    fwrite(STDERR, "Использование: php tests/run.php [1|2|3|4]\n");
    exit(2);
}
$results = [];
$failures = 0;
$number = 0;
foreach ($tests as $name => $test) {
    $number++;
    if ($case !== null && $case !== $number) {
        continue;
    }
    $student = null;
    $machines = [];
    $error = '';
    $started = microtime(true);
    try {
        $db->exec("INSERT INTO students (full_name, room_number) VALUES ('Проверка бронирования', 'TEST')");
        $student = (int) $db->lastInsertId();
        $prefix = 'test_' . bin2hex(random_bytes(5));
        foreach ([1, 2] as $index) {
            $db->prepare("INSERT INTO washing_machines (machine_code, model) VALUES (?, 'TEST')")->execute(["{$prefix}_{$index}"]);
            $machines[] = (int) $db->lastInsertId();
        }
        $test($db, new BookingService($db), $student, $machines);
        echo "PASS {$number}: {$name}\n";
    } catch (Throwable $exception) {
        $error = $exception->getMessage();
        $failures++;
        echo "FAIL {$number}: {$name}: {$error}\n";
    } finally {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ($student !== null) {
            $db->prepare('DELETE FROM bookings WHERE id_student = ?')->execute([$student]);
            $db->prepare('DELETE FROM notifications WHERE id_student = ?')->execute([$student]);
            $db->prepare('DELETE FROM students WHERE id_student = ?')->execute([$student]);
        }
        foreach ($machines as $machine) {
            $db->prepare('DELETE FROM washing_machines WHERE id_machine = ?')->execute([$machine]);
        }
    }
    $results[] = [$name, $error, microtime(true) - $started];
}
$xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
$xml .= '<testsuite name="Laundry booking" tests="' . count($results) . '" failures="' . $failures . '">';
foreach ($results as [$name, $error, $seconds]) {
    $xml .= '<testcase name="' . htmlspecialchars($name, ENT_XML1, 'UTF-8') . '" time="' . $seconds . '">';
    if ($error !== '') {
        $xml .= '<failure message="' . htmlspecialchars($error, ENT_XML1, 'UTF-8') . '"/>';
    }
    $xml .= '</testcase>';
}
$xml .= '</testsuite>';
if (!is_dir(dirname(__DIR__) . '/var')) {
    mkdir(dirname(__DIR__) . '/var', 0777, true);
}
file_put_contents(dirname(__DIR__) . '/var/results-' . ($case ?? 'all') . '.xml', $xml);
echo 'Итого: ' . count($results) . ', ошибок: ' . $failures . ".\n";
exit($failures === 0 ? 0 : 1);
