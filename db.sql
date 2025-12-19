CREATE DATABASE clinic_appointment_system;

USE clinic_appointment_system;
CREATE TABLE Roles(
    role_id INT AUTO_INCREMENT PRIMARY KEY,
    role_name VARCHAR(20) NOT NULL UNIQUE
);

INSERT INTO Roles(role_name) VALUES
('patient'),
('doctor'),
('secretary'),
('admin');

CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role_id INT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES Roles(role_id)
);

CREATE TABLE Patients (
    patient_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    phone VARCHAR(20),
    CONSTRAINT fk_patients_user FOREIGN KEY (user_id) REFERENCES Users(user_id)
);

CREATE TABLE Doctors (
    doctor_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    expertise VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT fk_doctors_user FOREIGN KEY (user_id) REFERENCES Users(user_id)
);

CREATE TABLE Doctor_Working_Hours (
    working_hour_id INT AUTO_INCREMENT PRIMARY KEY,
    doctor_id INT NOT NULL,
    day_of_week ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun') NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    CONSTRAINT fk_workinghours_doctor FOREIGN KEY (doctor_id) REFERENCES Doctors(doctor_id),
    CONSTRAINT chk_working_hours CHECK (start_time < end_time)
);
-- Each doctor can only have one working period in a day.
ALTER TABLE Doctor_Working_Hours
ADD CONSTRAINT uq_doctor_day UNIQUE (doctor_id, day_of_week);

-- 2.part

CREATE TABLE Appointment_Status (
    status_id INT AUTO_INCREMENT PRIMARY KEY,
    status_name VARCHAR(20) NOT NULL UNIQUE
);

INSERT INTO Appointment_Status (status_name) VALUES
('scheduled'),
('cancelled'),
('completed');

CREATE TABLE Time_Slots (
    slot_id INT AUTO_INCREMENT PRIMARY KEY,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    CONSTRAINT chk_time_slot CHECK (start_time < end_time)
);

INSERT INTO Time_Slots (start_time, end_time) VALUES
('09:00:00','09:30:00'),
('09:30:00','10:00:00'),
('10:00:00','10:30:00');


CREATE TABLE Appointments (
    appointment_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    slot_id INT NOT NULL,
    appointment_date DATE NOT NULL,
    status_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_appointment_patient FOREIGN KEY (patient_id)
        REFERENCES Patients(patient_id),

    CONSTRAINT fk_appointment_doctor FOREIGN KEY (doctor_id)
        REFERENCES Doctors(doctor_id),

    CONSTRAINT fk_appointment_slot FOREIGN KEY (slot_id)
        REFERENCES Time_Slots(slot_id),

    CONSTRAINT fk_appointment_status FOREIGN KEY (status_id)
        REFERENCES Appointment_Status(status_id),

    -- CONFLICT PREVENTION (FR5): No two appointments for the same doctor at the same time
    CONSTRAINT uq_doctor_date_slot
		UNIQUE (doctor_id, appointment_date, slot_id),
        
   -- CONFLICT PREVENTION: No two appointments for the same patient at the same time
	CONSTRAINT uq_patient_date_slot
        UNIQUE (patient_id, appointment_date, slot_id)
);

CREATE TABLE Appointment_Actions (
    action_id INT AUTO_INCREMENT PRIMARY KEY,
    appointment_id INT NOT NULL,
    action_type ENUM('created','cancelled','updated') NOT NULL,
    performed_by_user_id INT NOT NULL,
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_action_appointment
        FOREIGN KEY (appointment_id) REFERENCES Appointments(appointment_id),

    CONSTRAINT fk_action_user
        FOREIGN KEY (performed_by_user_id) REFERENCES Users(user_id)
);

DELIMITER $$
-- LOGIN PROCEDURE (FR2, UC2)
DROP PROCEDURE IF EXISTS sp_create_appointment $$

CREATE PROCEDURE sp_create_appointment(
    IN p_patient_id INT,
    IN p_doctor_id INT,
    IN p_slot_id INT,
    IN p_date DATE,
    IN p_user_id INT
)
BEGIN
    IF p_date < CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Appointment date cannot be in the past';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Doctors
        WHERE doctor_id = p_doctor_id
          AND is_active = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Doctor is not active';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Patients p
        JOIN Users u ON p.user_id = u.user_id
        WHERE p.patient_id = p_patient_id
          AND u.is_active = TRUE
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Patient is not active';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Doctor_Working_Hours dwh
        JOIN Time_Slots ts ON ts.slot_id = p_slot_id
        WHERE dwh.doctor_id = p_doctor_id
          AND dwh.day_of_week = LEFT(DAYNAME(p_date), 3)
          AND ts.start_time >= dwh.start_time
          AND ts.end_time   <= dwh.end_time
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Appointment outside doctor working hours';
    END IF;

    INSERT INTO Appointments
        (patient_id, doctor_id, slot_id, appointment_date, status_id)
    VALUES
        (
            p_patient_id,
            p_doctor_id,
            p_slot_id,
            p_date,
            (SELECT status_id
             FROM Appointment_Status
             WHERE status_name = 'scheduled'
             LIMIT 1)
        );

    INSERT INTO Appointment_Actions
        (appointment_id, action_type, performed_by_user_id)
    VALUES
        (LAST_INSERT_ID(), 'created', p_user_id);

    SELECT LAST_INSERT_ID() AS appointment_id;
END $$
DELIMITER ;

CREATE INDEX idx_appt_doctor_date
ON Appointments (doctor_id, appointment_date);

CREATE INDEX idx_appt_patient_date
ON Appointments (patient_id, appointment_date);

ALTER TABLE Users 
ADD COLUMN first_name VARCHAR(50) NOT NULL,
ADD COLUMN last_name VARCHAR(50) NOT NULL;

ALTER TABLE Patients 
DROP COLUMN first_name,
DROP COLUMN last_name;

DELIMITER $$
DROP PROCEDURE IF EXISTS sp_login_user $$
CREATE PROCEDURE sp_login_user(
    IN p_email VARCHAR(100),
    IN p_password_hash VARCHAR(255) 
)
BEGIN
    SELECT 
        u.user_id,
        u.role_id,
        r.role_name,
        u.first_name,
        u.last_name
    FROM Users u
    JOIN Roles r ON u.role_id = r.role_id
    WHERE u.email = p_email
      AND u.password = p_password_hash 
      AND u.is_active = TRUE;

END $$
DELIMITER ;

DELIMITER $$
-- PATIENT REGISTRATION PROCEDURE (FR1, UC1)
DROP PROCEDURE IF EXISTS sp_register_patient $$
CREATE PROCEDURE sp_register_patient(
    IN p_email VARCHAR(100),
    IN p_password_hash VARCHAR(255), 
    IN p_first_name VARCHAR(50),
    IN p_last_name VARCHAR(50),
    IN p_phone VARCHAR(20)
)
BEGIN
    DECLARE v_patient_role_id INT;
    DECLARE v_user_id INT;

    SELECT role_id INTO v_patient_role_id FROM Roles WHERE role_name = 'patient';

    INSERT INTO Users (email, password, role_id, first_name, last_name)
    VALUES (p_email, p_password_hash, v_patient_role_id, p_first_name, p_last_name);

    SET v_user_id = LAST_INSERT_ID();

    INSERT INTO Patients (user_id, phone)
    VALUES (v_user_id, p_phone);

    SELECT v_user_id AS user_id, LAST_INSERT_ID() AS patient_id;
END $$
DELIMITER ;

DELIMITER $$
-- USER MANAGEMENT PROCEDURE (FR10, UC12, NFR2)
DROP PROCEDURE IF EXISTS sp_manage_user $$
CREATE PROCEDURE sp_manage_user(
    IN p_admin_user_id INT,
    IN p_email VARCHAR(100),
    IN p_password_hash VARCHAR(255),
    IN p_first_name VARCHAR(50),
    IN p_last_name VARCHAR(50),
    IN p_role_name VARCHAR(20),
    IN p_expertise VARCHAR(100)
)
BEGIN
    DECLARE v_role_id INT;
    DECLARE v_user_id INT;
    
    IF (SELECT role_name FROM Users u JOIN Roles r ON u.role_id = r.role_id WHERE u.user_id = p_admin_user_id) != 'admin' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only administrators can manage users.';
    END IF;

    SELECT role_id INTO v_role_id FROM Roles WHERE role_name = p_role_name;

    IF v_role_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid role name.';
    END IF;

    INSERT INTO Users (email, password, role_id, first_name, last_name)
    VALUES (p_email, p_password_hash, v_role_id, p_first_name, p_last_name);

    SET v_user_id = LAST_INSERT_ID();

    IF p_role_name = 'doctor' THEN
        IF p_expertise IS NULL OR p_expertise = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Expertise is required for doctors.';
        END IF;
        INSERT INTO Doctors (user_id, expertise)
        VALUES (v_user_id, p_expertise);
    END IF;

    SELECT v_user_id AS user_id;
END $$
DELIMITER ;

DELIMITER $$
-- GET DOCTOR LIST (FR3, UC3)
DROP PROCEDURE IF EXISTS sp_get_doctor_list $$
CREATE PROCEDURE sp_get_doctor_list()
BEGIN
    SELECT
        d.doctor_id,
        u.first_name,
        u.last_name,
        d.expertise
    FROM Doctors d
    JOIN Users u ON d.user_id = u.user_id
    WHERE d.is_active = TRUE
      AND u.is_active = TRUE
    ORDER BY u.last_name, u.first_name;
END $$
DELIMITER ;

DELIMITER $$
-- GET AVAILABLE SLOTS (FR4, UC4)
DROP PROCEDURE IF EXISTS sp_get_available_slots $$
CREATE PROCEDURE sp_get_available_slots(
    IN p_doctor_id INT,
    IN p_date DATE
)
BEGIN
    DECLARE v_day_of_week VARCHAR(3);
    SET v_day_of_week = LEFT(DAYNAME(p_date), 3);

    WITH DoctorWorkingHours AS (
        SELECT start_time AS working_start, end_time AS working_end
        FROM Doctor_Working_Hours
        WHERE doctor_id = p_doctor_id
          AND day_of_week = v_day_of_week
    )
    
    SELECT 
        ts.slot_id,
        ts.start_time,
        ts.end_time
    FROM Time_Slots ts
    JOIN DoctorWorkingHours dwh ON ts.start_time >= dwh.working_start AND ts.end_time <= dwh.working_end
    LEFT JOIN Appointments a ON 
        a.doctor_id = p_doctor_id 
        AND a.appointment_date = p_date 
        AND a.slot_id = ts.slot_id
        AND (SELECT status_name FROM Appointment_Status WHERE status_id = a.status_id) = 'scheduled'
    WHERE a.appointment_id IS NULL 
    ORDER BY ts.start_time;
END $$
DELIMITER ;

DELIMITER $$
-- GET PATIENT APPOINTMENTS (FR6, UC6)
DROP PROCEDURE IF EXISTS sp_get_patient_appointments $$
CREATE PROCEDURE sp_get_patient_appointments(
    IN p_patient_id INT
)
BEGIN
    SELECT
        a.appointment_id,
        a.appointment_date,
        ts.start_time,
        ts.end_time,
        CONCAT(u_doc.first_name, ' ', u_doc.last_name) AS doctor_name,
        d.expertise,
        s.status_name
    FROM Appointments a
    JOIN Doctors d ON a.doctor_id = d.doctor_id
    JOIN Users u_doc ON d.user_id = u_doc.user_id
    JOIN Time_Slots ts ON a.slot_id = ts.slot_id
    JOIN Appointment_Status s ON a.status_id = s.status_id
    WHERE a.patient_id = p_patient_id
    ORDER BY a.appointment_date DESC, ts.start_time DESC;
END $$
DELIMITER ;

DELIMITER $$
-- GET DOCTOR SCHEDULE (FR8, UC9)
DROP PROCEDURE IF EXISTS sp_get_doctor_schedule $$
CREATE PROCEDURE sp_get_doctor_schedule(
    IN p_doctor_id INT,
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    SELECT
        a.appointment_id,
        a.appointment_date,
        ts.start_time,
        ts.end_time,
        CONCAT(u_pat.first_name, ' ', u_pat.last_name) AS patient_name,
        s.status_name
    FROM Appointments a
    JOIN Patients p ON a.patient_id = p.patient_id
    JOIN Users u_pat ON p.user_id = u_pat.user_id
    JOIN Time_Slots ts ON a.slot_id = ts.slot_id
    JOIN Appointment_Status s ON a.status_id = s.status_id
    WHERE a.doctor_id = p_doctor_id
      AND a.appointment_date BETWEEN p_start_date AND p_end_date
    ORDER BY a.appointment_date, ts.start_time;
END $$
DELIMITER ;

DELIMITER $$
DROP PROCEDURE IF EXISTS sp_cancel_appointment $$
CREATE PROCEDURE sp_cancel_appointment(
    IN p_appointment_id INT,
    IN p_user_id INT
)
BEGIN
    DECLARE v_appointment_patient_user_id INT;
    DECLARE v_user_role_name VARCHAR(20);

    SELECT 
        p.user_id INTO v_appointment_patient_user_id
    FROM Appointments a
    JOIN Patients p ON a.patient_id = p.patient_id
    WHERE a.appointment_id = p_appointment_id;

    SELECT r.role_name INTO v_user_role_name
    FROM Users u
    JOIN Roles r ON u.role_id = r.role_id
    WHERE u.user_id = p_user_id;

    IF NOT (
        v_appointment_patient_user_id = p_user_id
        OR v_user_role_name IN ('secretary', 'admin')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Unauthorized to cancel this appointment.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM Appointments a
        JOIN Appointment_Status s ON a.status_id = s.status_id
        WHERE a.appointment_id = p_appointment_id
          AND s.status_name = 'cancelled'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Appointment already cancelled';
    END IF;

    UPDATE Appointments
    SET status_id = (
        SELECT status_id
        FROM Appointment_Status
        WHERE status_name = 'cancelled'
        LIMIT 1
    )
    WHERE appointment_id = p_appointment_id;

    INSERT INTO Appointment_Actions
        (appointment_id, action_type, performed_by_user_id)
    VALUES
        (p_appointment_id, 'cancelled', p_user_id);
END $$
DELIMITER ;

DELIMITER $$
-- UPDATE APPOINTMENT PROCEDURE (FR7, FR11, UC7, NFR2)
DROP PROCEDURE IF EXISTS sp_update_appointment $$
CREATE PROCEDURE sp_update_appointment(
    IN p_appointment_id INT,
    IN p_new_date DATE,
    IN p_new_slot_id INT,
    IN p_user_id INT
)
BEGIN
    DECLARE v_appointment_patient_user_id INT;
    DECLARE v_doctor_id INT;
    DECLARE v_user_role_name VARCHAR(20);

    SELECT a.doctor_id, p.user_id INTO v_doctor_id, v_appointment_patient_user_id
    FROM Appointments a
    JOIN Patients p ON a.patient_id = p.patient_id
    WHERE a.appointment_id = p_appointment_id;

    SELECT r.role_name INTO v_user_role_name
    FROM Users u
    JOIN Roles r ON u.role_id = r.role_id
    WHERE u.user_id = p_user_id;

    IF NOT (
        v_appointment_patient_user_id = p_user_id
        OR v_user_role_name IN ('secretary', 'admin')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Unauthorized to update this appointment.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM Doctor_Working_Hours dwh
        JOIN Time_Slots ts ON ts.slot_id = p_new_slot_id
        WHERE dwh.doctor_id = v_doctor_id
          AND dwh.day_of_week = LEFT(DAYNAME(p_new_date), 3)
          AND ts.start_time >= dwh.start_time
          AND ts.end_time   <= dwh.end_time
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Updated time is outside doctor working hours.';
    END IF;

    UPDATE Appointments
    SET appointment_date = p_new_date,
        slot_id = p_new_slot_id
    WHERE appointment_id = p_appointment_id;

    INSERT INTO Appointment_Actions
        (appointment_id, action_type, performed_by_user_id)
    VALUES
        (p_appointment_id, 'updated', p_user_id);

    SELECT p_appointment_id AS appointment_id;
END $$
DELIMITER ;

DELIMITER $$
-- GET ADMIN STATISTICS (FR14, FR20, NFR2)
DROP PROCEDURE IF EXISTS sp_get_admin_stats $$
CREATE PROCEDURE sp_get_admin_stats(
    IN p_admin_user_id INT,
    IN p_start_date DATE,
    IN p_end_date DATE
)
BEGIN
    -- Admin Control (NFR2)
    IF (SELECT role_name FROM Users u JOIN Roles r ON u.role_id = r.role_id WHERE u.user_id = p_admin_user_id) != 'admin' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only administrators can view system statistics.';
    END IF;
    
    SELECT 
        (SELECT COUNT(*) FROM Users) AS total_users,
        (SELECT COUNT(*) FROM Doctors) AS total_doctors,
        (SELECT COUNT(*) FROM Patients) AS total_patients,
        
        SUM(CASE WHEN s.status_name = 'scheduled' THEN 1 ELSE 0 END) AS total_scheduled_appointments,
        SUM(CASE WHEN s.status_name = 'cancelled' THEN 1 ELSE 0 END) AS total_cancelled_appointments,
        COUNT(a.appointment_id) AS total_appointments_in_range
    FROM Appointments a
    JOIN Appointment_Status s ON a.status_id = s.status_id
    WHERE a.appointment_date BETWEEN p_start_date AND p_end_date;
END $$
DELIMITER ;

DELIMITER $$
-- UPDATE DOCTOR AVAILABILITY (FR9, UC10, NFR2)
DROP PROCEDURE IF EXISTS sp_update_doctor_availability $$
CREATE PROCEDURE sp_update_doctor_availability(
    IN p_doctor_user_id INT, 
    IN p_target_doctor_id INT, 
    IN p_day_of_week ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun'),
    IN p_start_time TIME,
    IN p_end_time TIME
)
BEGIN
    DECLARE v_user_role_name VARCHAR(20);

    SELECT r.role_name INTO v_user_role_name
    FROM Users u JOIN Roles r ON u.role_id = r.role_id WHERE u.user_id = p_doctor_user_id;

   -- Authorization Control (NFR2, FR9)
    IF v_user_role_name NOT IN ('doctor', 'secretary', 'admin') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unauthorized to update doctor availability.';
    END IF;

    IF v_user_role_name = 'doctor' AND (SELECT doctor_id FROM Doctors WHERE user_id = p_doctor_user_id) != p_target_doctor_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctors can only update their own availability.';
    END IF;
    
    INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time)
    VALUES (p_target_doctor_id, p_day_of_week, p_start_time, p_end_time)
    ON DUPLICATE KEY UPDATE 
        start_time = p_start_time,
        end_time = p_end_time;
END $$
DELIMITER ;

INSERT INTO Users (email, password, role_id, first_name, last_name)
VALUES (
    'admin@clinic.com','admin_hash',
    (SELECT role_id FROM Roles WHERE role_name='admin'),'System','Admin'
);

-- Secretary
INSERT INTO Users (email, password, role_id, first_name, last_name)
VALUES (
    'secretary@clinic.com','secretary_hash',
    (SELECT role_id FROM Roles WHERE role_name='secretary'),'Clinic','Secretary'
);

-- Doctor 1
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'dr.smith@clinic.com', 'doctor_hash',
       (SELECT role_id FROM Roles WHERE role_name='doctor'),
       'John', 'Smith'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='dr.smith@clinic.com');

INSERT INTO Doctors (user_id, expertise)
SELECT user_id, 'Cardiology'
FROM Users WHERE email='dr.smith@clinic.com'
AND NOT EXISTS (SELECT 1 FROM Doctors WHERE user_id = Users.user_id);

-- Doctor 2
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'dr.brown@clinic.com', 'doctor_hash',
       (SELECT role_id FROM Roles WHERE role_name='doctor'),
       'Emily', 'Brown'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='dr.brown@clinic.com');

INSERT INTO Doctors (user_id, expertise)
SELECT user_id, 'Dermatology'
FROM Users WHERE email='dr.brown@clinic.com'
AND NOT EXISTS (SELECT 1 FROM Doctors WHERE user_id = Users.user_id);

-- Doctor 3
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'dr.jones@clinic.com', 'doctor_hash',
       (SELECT role_id FROM Roles WHERE role_name='doctor'),
       'Michael', 'Jones'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='dr.jones@clinic.com');

INSERT INTO Doctors (user_id, expertise)
SELECT user_id, 'Neurology'
FROM Users WHERE email='dr.jones@clinic.com'
AND NOT EXISTS (SELECT 1 FROM Doctors WHERE user_id = Users.user_id);

-- Doctor 4
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'dr.wilson@clinic.com', 'doctor_hash',
       (SELECT role_id FROM Roles WHERE role_name='doctor'),
       'Sarah', 'Wilson'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='dr.wilson@clinic.com');

INSERT INTO Doctors (user_id, expertise)
SELECT user_id, 'Orthopedics'
FROM Users WHERE email='dr.wilson@clinic.com'
AND NOT EXISTS (SELECT 1 FROM Doctors WHERE user_id = Users.user_id);

-- Doctor 5
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'dr.taylor@clinic.com', 'doctor_hash',
       (SELECT role_id FROM Roles WHERE role_name='doctor'),
       'David', 'Taylor'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='dr.taylor@clinic.com');

INSERT INTO Doctors (user_id, expertise)
SELECT user_id, 'Pediatrics'
FROM Users WHERE email='dr.taylor@clinic.com'
AND NOT EXISTS (SELECT 1 FROM Doctors WHERE user_id = Users.user_id);

-- Patient 1
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'alice@mail.com', 'patient_hash',
       (SELECT role_id FROM Roles WHERE role_name='patient'),
       'Alice', 'Johnson'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='alice@mail.com');

INSERT INTO Patients (user_id, phone)
SELECT user_id, '555-1001'
FROM Users WHERE email='alice@mail.com'
AND NOT EXISTS (SELECT 1 FROM Patients WHERE user_id = Users.user_id);

-- Patient 2
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'bob@mail.com', 'patient_hash',
       (SELECT role_id FROM Roles WHERE role_name='patient'),
       'Bob', 'Williams'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='bob@mail.com');

INSERT INTO Patients (user_id, phone)
SELECT user_id, '555-1002'
FROM Users WHERE email='bob@mail.com'
AND NOT EXISTS (SELECT 1 FROM Patients WHERE user_id = Users.user_id);

-- Patient 3
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'carol@mail.com', 'patient_hash',
       (SELECT role_id FROM Roles WHERE role_name='patient'),
       'Carol', 'Miller'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='carol@mail.com');

INSERT INTO Patients (user_id, phone)
SELECT user_id, '555-1003'
FROM Users WHERE email='carol@mail.com'
AND NOT EXISTS (SELECT 1 FROM Patients WHERE user_id = Users.user_id);

-- Patient 4
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'dan@mail.com', 'patient_hash',
       (SELECT role_id FROM Roles WHERE role_name='patient'),
       'Daniel', 'Moore'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='dan@mail.com');

INSERT INTO Patients (user_id, phone)
SELECT user_id, '555-1004'
FROM Users WHERE email='dan@mail.com'
AND NOT EXISTS (SELECT 1 FROM Patients WHERE user_id = Users.user_id);

-- Patient 5
INSERT INTO Users (email, password, role_id, first_name, last_name)
SELECT 'eva@mail.com', 'patient_hash',
       (SELECT role_id FROM Roles WHERE role_name='patient'),
       'Eva', 'Anderson'
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE email='eva@mail.com');

INSERT INTO Patients (user_id, phone)
SELECT user_id, '555-1005'
FROM Users WHERE email='eva@mail.com'
AND NOT EXISTS (SELECT 1 FROM Patients WHERE user_id = Users.user_id);

SELECT d.doctor_id, u.first_name, u.last_name, d.expertise
FROM Doctors d JOIN Users u ON d.user_id = u.user_id;

SELECT p.patient_id, u.first_name, u.last_name, p.phone
FROM Patients p JOIN Users u ON p.user_id = u.user_id;


-- Doctor 1 – Cardiology (09:00–12:00)
INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time)
SELECT doctor_id, d.day, '09:00:00', '12:00:00'
FROM Doctors,
     (SELECT 'Mon' AS day UNION ALL SELECT 'Tue' UNION ALL SELECT 'Wed') d
WHERE expertise = 'Cardiology'
ON DUPLICATE KEY UPDATE
    start_time = VALUES(start_time),
    end_time   = VALUES(end_time);

-- Doctor 2 – Dermatology (10:00–13:00)
INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time)
SELECT doctor_id, d.day, '10:00:00', '13:00:00'
FROM Doctors,
     (SELECT 'Mon' AS day UNION ALL SELECT 'Thu' UNION ALL SELECT 'Fri') d
WHERE expertise = 'Dermatology'
ON DUPLICATE KEY UPDATE
    start_time = VALUES(start_time),
    end_time   = VALUES(end_time);

-- Doctor 3 – Neurology (08:30–11:30)
INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time)
SELECT doctor_id, d.day, '08:30:00', '11:30:00'
FROM Doctors,
     (SELECT 'Tue' AS day UNION ALL SELECT 'Wed' UNION ALL SELECT 'Thu') d
WHERE expertise = 'Neurology'
ON DUPLICATE KEY UPDATE
    start_time = VALUES(start_time),
    end_time   = VALUES(end_time);

-- Doctor 4 – Orthopedics (11:00–15:00)
INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time)
SELECT doctor_id, d.day, '11:00:00', '15:00:00'
FROM Doctors,
     (SELECT 'Mon' AS day UNION ALL SELECT 'Wed' UNION ALL SELECT 'Fri') d
WHERE expertise = 'Orthopedics'
ON DUPLICATE KEY UPDATE
    start_time = VALUES(start_time),
    end_time   = VALUES(end_time);

-- Doctor 5 – Pediatrics (09:30–14:00)
INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time)
SELECT doctor_id, d.day, '09:30:00', '14:00:00'
FROM Doctors,
     (SELECT 'Tue' AS day UNION ALL SELECT 'Thu') d
WHERE expertise = 'Pediatrics'
ON DUPLICATE KEY UPDATE
    start_time = VALUES(start_time),
    end_time   = VALUES(end_time);

SELECT
    d.doctor_id,
    u.first_name,
    u.last_name,
    d.expertise,
    w.day_of_week,
    w.start_time,
    w.end_time
FROM Doctor_Working_Hours w
JOIN Doctors d ON w.doctor_id = d.doctor_id
JOIN Users u ON d.user_id = u.user_id
ORDER BY d.doctor_id, w.day_of_week;

CALL sp_get_available_slots(
    (SELECT doctor_id FROM Doctors WHERE expertise='Cardiology' LIMIT 1),
    CURDATE()
);

CALL sp_create_appointment(
    (SELECT patient_id FROM Patients LIMIT 1),
    (SELECT doctor_id FROM Doctors WHERE expertise='Cardiology' LIMIT 1),
    (SELECT slot_id FROM Time_Slots WHERE start_time='09:00:00'),
    CURDATE(),
    (SELECT user_id FROM Users WHERE role_id = (SELECT role_id FROM Roles WHERE role_name='secretary') LIMIT 1)
);

-- Pediatrics doctor should not work at 09:00 → should throw an ERROR
CALL sp_create_appointment(
    (SELECT patient_id FROM Patients LIMIT 1),
    (SELECT doctor_id FROM Doctors WHERE expertise='Pediatrics' LIMIT 1),
    (SELECT slot_id FROM Time_Slots WHERE start_time='09:00:00'),
    CURDATE(),
    (SELECT user_id FROM Users WHERE role_id = (SELECT role_id FROM Roles WHERE role_name='admin') LIMIT 1)
);


