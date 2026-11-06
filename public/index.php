<?php
declare(strict_types=1);
ini_set('session.use_strict_mode', '1');
session_set_cookie_params([
    'httponly' => true,
    'samesite' => 'Lax',
    'secure' => isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
]);
session_start();
require dirname(__DIR__) . '/src/bootstrap.php';

function escape(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
}

$_SESSION['csrf'] ??= bin2hex(random_bytes(24));
$error = '';
try {
    $db = database();
    $service = new BookingService($db);
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (!hash_equals($_SESSION['csrf'], (string) ($_POST['csrf'] ?? ''))) {
            throw new DomainException('Обновите страницу и повторите действие.');
        }
        if (($_POST['action'] ?? '') === 'cancel') {
            $service->cancel((int) ($_POST['booking_id'] ?? 0));
            $_SESSION['flash'] = 'Бронирование отменено. Время снова доступно.';
        } else {
            $id = $service->book(
                (int) ($_POST['student_id'] ?? 0), (int) ($_POST['machine_id'] ?? 0),
                str_replace('T', ' ', (string) ($_POST['start'] ?? '')) . ':00',
                str_replace('T', ' ', (string) ($_POST['end'] ?? '')) . ':00'
            );
            $_SESSION['flash'] = "Создано бронирование №{$id}.";
        }
        header('Location: /');
        exit;
    }
} catch (DomainException $exception) {
    $error = $exception->getMessage();
} catch (Throwable $exception) {
    error_log($exception->getMessage());
    $error = 'Не удалось выполнить операцию. Проверьте подключение и структуру базы данных.';
}
$students = $machines = $bookings = $notifications = [];
if (isset($db)) {
    try {
        $students = $db->query('SELECT * FROM students WHERE is_active = 1 ORDER BY full_name')->fetchAll();
        $machines = $db->query('SELECT * FROM washing_machines ORDER BY machine_code')->fetchAll();
        $bookings = $db->query('SELECT b.*, s.full_name, m.machine_code FROM bookings b JOIN students s USING (id_student) JOIN washing_machines m USING (id_machine) ORDER BY start_time DESC LIMIT 50')->fetchAll();
        $notifications = $db->query('SELECT n.*, s.full_name FROM notifications n JOIN students s USING (id_student) ORDER BY id_notification DESC LIMIT 8')->fetchAll();
    } catch (Throwable $exception) {
        $error = 'Подготовьте базу данных командой php bin/init-db.php --seed.';
    }
}
?>
<!doctype html>
<html lang="ru">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Очередь в прачечную | Общежитие №8</title>
<style>
:root{font:16px/1.5 system-ui;color:#17243b;background:#f2f5fa}body{max-width:1100px;margin:40px auto;padding:0 20px}h1{font-size:32px;margin-bottom:4px}h2{font-size:21px}header p{color:#586783}.layout{display:grid;grid-template-columns:330px 1fr;gap:24px}section{background:white;padding:24px;border:1px solid #dce3ee;border-radius:14px;margin:20px 0}label{display:block;margin:14px 0}input,select,button{font:inherit;padding:10px;border:1px solid #bdc9da;border-radius:7px}input,select{width:100%;box-sizing:border-box}button{background:#244da0;color:white;cursor:pointer}.cancel{background:white;color:#244da0;padding:5px 9px}.error{background:#fff0f0;padding:15px;color:#9f2222}.ok{background:#e9f7ee;padding:15px;color:#1e6037}table{width:100%;border-collapse:collapse}td,th{text-align:left;border-bottom:1px solid #e1e7f0;padding:10px 6px;font-size:14px}.muted{color:#68768c}.scroll{overflow:auto}@media(max-width:800px){.layout{display:block}body{margin:20px auto}}
</style>
<header><p>Общежитие №8 ИрГУПС</p><h1>Электронная очередь в прачечную</h1><p>Рабочее место оператора · Ежедневно с 08:00 до 22:00</p></header>
<?php if ($error): ?><p class="error" role="alert"><?= escape($error) ?></p><?php endif ?>
<?php if (isset($_SESSION['flash'])): ?><p class="ok" role="status"><?= escape($_SESSION['flash']) ?></p><?php unset($_SESSION['flash']); endif ?>
<main class="layout"><div><section><h2>Новая запись</h2><form method="post">
<input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>">
<label>Студент<select name="student_id" required><?php foreach ($students as $student): ?><option value="<?= escape($student['id_student']) ?>"><?= escape($student['full_name'] . ', комн. ' . $student['room_number']) ?></option><?php endforeach ?></select></label>
<label>Машина<select name="machine_id" required><?php foreach ($machines as $machine): ?><option value="<?= escape($machine['id_machine']) ?>" <?= $machine['is_available'] ? '' : 'disabled' ?>><?= escape($machine['machine_code'] . ' · ' . $machine['model'] . ($machine['is_available'] ? '' : ' · обслуживание')) ?></option><?php endforeach ?></select></label>
<label>Начало<input type="datetime-local" name="start" required></label>
<label>Окончание<input type="datetime-local" name="end" required></label><button>Забронировать</button>
</form></section><section><h2>Оборудование</h2><?php foreach ($machines as $machine): ?><p><?= escape($machine['machine_code']) ?> · <?= $machine['is_available'] ? 'Доступна' : 'На обслуживании' ?></p><?php endforeach ?></section></div>
<div><section><h2>Бронирования</h2><div class="scroll"><table><thead><tr><th>Студент</th><th>Машина</th><th>Время</th><th>Статус</th><th>Действие</th></tr></thead><tbody>
<?php foreach ($bookings as $booking): ?><tr><td><?= escape($booking['full_name']) ?></td><td><?= escape($booking['machine_code']) ?></td><td><?= escape($booking['start_time']) ?><br><?= escape($booking['end_time']) ?></td><td><?= $booking['status'] === 'active' ? 'Активна' : 'Отменена' ?></td><td><?php if ($booking['status'] === 'active'): ?><form method="post"><input type="hidden" name="csrf" value="<?= escape($_SESSION['csrf']) ?>"><input type="hidden" name="action" value="cancel"><input type="hidden" name="booking_id" value="<?= escape($booking['id_booking']) ?>"><button class="cancel">Отменить</button></form><?php endif ?></td></tr><?php endforeach ?>
</tbody></table></div><?php if (!$bookings): ?><p class="muted">Записей пока нет. Выберите машину и время.</p><?php endif ?></section>
<section><h2>Уведомления</h2><?php foreach ($notifications as $notification): ?><p><strong><?= escape($notification['full_name']) ?></strong><br><?= escape($notification['message']) ?></p><?php endforeach ?><?php if (!$notifications): ?><p class="muted">После записи или отмены здесь появится уведомление.</p><?php endif ?></section></div></main>
</html>
