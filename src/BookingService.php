<?php
declare(strict_types=1);

final class BookingService
{
    public function __construct(private PDO $db) {}

    public function book(int $studentId, int $machineId, string $start, string $end): int
    {
        $from = $this->parseTime($start);
        $to = $this->parseTime($end);
        if ($from >= $to) {
            throw new DomainException('Окончание должно быть позже начала.');
        }
        if ($from->format('Y-m-d') !== $to->format('Y-m-d')
            || $from->format('H:i:s') < '08:00:00' || $to->format('H:i:s') > '22:00:00') {
            throw new DomainException('Прачечная работает ежедневно с 08:00 до 22:00.');
        }

        $this->db->beginTransaction();
        try {
            // Блокировка машины сериализует параллельные заявки на неё.
            $machine = $this->db->prepare('SELECT is_available FROM washing_machines WHERE id_machine = ? FOR UPDATE');
            $machine->execute([$machineId]);
            $available = $machine->fetchColumn();
            if ($available === false || !(bool) $available) {
                throw new DomainException('Машина недоступна или находится на обслуживании.');
            }
            $student = $this->db->prepare('SELECT is_active FROM students WHERE id_student = ?');
            $student->execute([$studentId]);
            if (!(bool) $student->fetchColumn()) {
                throw new DomainException('Студент не найден или не проживает в общежитии.');
            }
            // Интервалы полуоткрытые: 10:00–11:00 и 11:00–12:00 совместимы.
            $conflict = $this->db->prepare(
                "SELECT id_booking FROM bookings WHERE id_machine = ? AND status = 'active' AND start_time < ? AND end_time > ? LIMIT 1 FOR UPDATE"
            );
            $conflict->execute([$machineId, $end, $start]);
            if ($conflict->fetchColumn() !== false) {
                throw new DomainException('Выбранное время уже занято.');
            }
            $insert = $this->db->prepare('INSERT INTO bookings (id_student, id_machine, start_time, end_time) VALUES (?, ?, ?, ?)');
            $insert->execute([$studentId, $machineId, $start, $end]);
            $id = (int) $this->db->lastInsertId();
            $this->notify($studentId, "Бронирование №{$id} создано: {$start} - {$end}.");
            $this->db->commit();
            return $id;
        } catch (Throwable $error) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            throw $error;
        }
    }

    public function cancel(int $bookingId): void
    {
        $this->db->beginTransaction();
        try {
            $query = $this->db->prepare('SELECT id_student, status FROM bookings WHERE id_booking = ? FOR UPDATE');
            $query->execute([$bookingId]);
            $booking = $query->fetch();
            if (!$booking || $booking['status'] !== 'active') {
                throw new DomainException('Активное бронирование не найдено.');
            }
            $update = $this->db->prepare("UPDATE bookings SET status = 'cancelled' WHERE id_booking = ?");
            $update->execute([$bookingId]);
            $this->notify((int) $booking['id_student'], "Бронирование №{$bookingId} отменено.");
            $this->db->commit();
        } catch (Throwable $error) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            throw $error;
        }
    }

    private function parseTime(string $value): DateTimeImmutable
    {
        $date = DateTimeImmutable::createFromFormat('!Y-m-d H:i:s', $value);
        if (!$date || $date->format('Y-m-d H:i:s') !== $value) {
            throw new DomainException('Укажите корректные дату и время.');
        }
        return $date;
    }

    private function notify(int $studentId, string $message): void
    {
        $query = $this->db->prepare('INSERT INTO notifications (id_student, message) VALUES (?, ?)');
        $query->execute([$studentId, $message]);
    }
}
