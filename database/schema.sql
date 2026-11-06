CREATE TABLE IF NOT EXISTS students (
    id_student INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(100) NOT NULL,
    room_number VARCHAR(10) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS staff (
    id_staff INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(100) NOT NULL,
    position VARCHAR(50) NOT NULL,
    access_level ENUM('admin', 'manager', 'worker') NOT NULL DEFAULT 'worker'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS washing_machines (
    id_machine INT PRIMARY KEY AUTO_INCREMENT,
    machine_code VARCHAR(30) NOT NULL UNIQUE,
    model VARCHAR(80) NOT NULL,
    is_available BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS bookings (
    id_booking INT PRIMARY KEY AUTO_INCREMENT,
    id_student INT NOT NULL,
    id_machine INT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    status ENUM('active', 'cancelled') NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_booking_student FOREIGN KEY (id_student) REFERENCES students(id_student),
    CONSTRAINT fk_booking_machine FOREIGN KEY (id_machine) REFERENCES washing_machines(id_machine),
    CONSTRAINT chk_booking_interval CHECK (end_time > start_time),
    INDEX idx_machine_interval (id_machine, status, start_time, end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS notifications (
    id_notification INT PRIMARY KEY AUTO_INCREMENT,
    id_student INT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notification_student FOREIGN KEY (id_student) REFERENCES students(id_student)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
