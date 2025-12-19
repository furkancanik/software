import sqlite3
import os

DB_NAME = "clinic.db"

if os.path.exists(DB_NAME):
    os.remove(DB_NAME)

conn = sqlite3.connect(DB_NAME)
cursor = conn.cursor()

# Enable Foreign Keys
cursor.execute("PRAGMA foreign_keys = ON;")

# --- TABLES ---

cursor.execute("""
CREATE TABLE Roles (
    role_id INTEGER PRIMARY KEY AUTOINCREMENT,
    role_name TEXT NOT NULL UNIQUE
);
""")

cursor.execute("""
CREATE TABLE Users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    role_id INTEGER NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    is_active BOOLEAN DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES Roles(role_id)
);
""")

cursor.execute("""
CREATE TABLE Patients (
    patient_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    phone TEXT,
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
);
""")

cursor.execute("""
CREATE TABLE Doctors (
    doctor_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    expertise TEXT NOT NULL,
    is_active BOOLEAN DEFAULT 1,
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
);
""")

cursor.execute("""
CREATE TABLE Doctor_Working_Hours (
    working_hour_id INTEGER PRIMARY KEY AUTOINCREMENT,
    doctor_id INTEGER NOT NULL,
    day_of_week TEXT NOT NULL, -- 'Mon','Tue'...
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    FOREIGN KEY (doctor_id) REFERENCES Doctors(doctor_id),
    UNIQUE (doctor_id, day_of_week)
);
""")

cursor.execute("""
CREATE TABLE Appointment_Status (
    status_id INTEGER PRIMARY KEY AUTOINCREMENT,
    status_name TEXT NOT NULL UNIQUE
);
""")

cursor.execute("""
CREATE TABLE Time_Slots (
    slot_id INTEGER PRIMARY KEY AUTOINCREMENT,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL
);
""")

cursor.execute("""
CREATE TABLE Appointments (
    appointment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id INTEGER NOT NULL,
    doctor_id INTEGER NOT NULL,
    slot_id INTEGER NOT NULL,
    appointment_date DATE NOT NULL,
    status_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES Patients(patient_id),
    FOREIGN KEY (doctor_id) REFERENCES Doctors(doctor_id),
    FOREIGN KEY (slot_id) REFERENCES Time_Slots(slot_id),
    FOREIGN KEY (status_id) REFERENCES Appointment_Status(status_id),
    UNIQUE (doctor_id, appointment_date, slot_id),
    UNIQUE (patient_id, appointment_date, slot_id)
);
""")

# --- INSERT DATA ---

# Roles
cursor.executemany("INSERT INTO Roles (role_name) VALUES (?)", [
    ('patient',), ('doctor',), ('secretary',), ('admin',)
])

# Status
cursor.executemany("INSERT INTO Appointment_Status (status_name) VALUES (?)", [
    ('scheduled',), ('cancelled',), ('completed',)
])

# Time Slots
cursor.executemany("INSERT INTO Time_Slots (start_time, end_time) VALUES (?, ?)", [
    ('09:00:00','09:30:00'),
    ('09:30:00','10:00:00'),
    ('10:00:00','10:30:00'),
    ('10:30:00','11:00:00'),
    ('11:00:00','11:30:00'),
    ('11:30:00','12:00:00'),
    ('13:00:00','13:30:00'),
    ('13:30:00','14:00:00'),
    ('14:00:00','14:30:00'),
    ('14:30:00','15:00:00')
])

# Admin
cursor.execute("""
INSERT INTO Users (email, password, role_id, first_name, last_name)
VALUES ('admin@clinic.com', 'admin', 
        (SELECT role_id FROM Roles WHERE role_name='admin'), 'System', 'Admin')
""")

# Secretary
cursor.execute("""
INSERT INTO Users (email, password, role_id, first_name, last_name)
VALUES ('secretary@clinic.com', 'secretary', 
        (SELECT role_id FROM Roles WHERE role_name='secretary'), 'Clinic', 'Secretary')
""")

# Doctors Setup Helper
doctors = [
    ('dr.smith@clinic.com', '12345', 'John', 'Smith', 'Cardiology', 
     [('Mon','09:00:00','12:00:00'), ('Tue','09:00:00','12:00:00'), ('Wed','09:00:00','12:00:00')]),
     
    ('dr.brown@clinic.com', '12345', 'Emily', 'Brown', 'Dermatology',
     [('Mon','10:00:00','13:00:00'), ('Thu','10:00:00','13:00:00'), ('Fri','10:00:00','13:00:00')]),
     
    ('dr.jones@clinic.com', '12345', 'Michael', 'Jones', 'Neurology',
     [('Tue','08:30:00','11:30:00'), ('Wed','08:30:00','11:30:00'), ('Thu','08:30:00','11:30:00')]),
     
    ('dr.wilson@clinic.com', '12345', 'Sarah', 'Wilson', 'Orthopedics',
     [('Mon','11:00:00','15:00:00'), ('Wed','11:00:00','15:00:00'), ('Fri','11:00:00','15:00:00')]),
]

for email, pwd, fname, lname, expert, hours in doctors:
    # User
    cursor.execute("INSERT INTO Users (email, password, role_id, first_name, last_name) VALUES (?, ?, (SELECT role_id FROM Roles WHERE role_name='doctor'), ?, ?)", 
                   (email, pwd, fname, lname))
    user_id = cursor.lastrowid
    
    # Doctor
    cursor.execute("INSERT INTO Doctors (user_id, expertise) VALUES (?, ?)", (user_id, expert))
    doc_id = cursor.lastrowid
    
    # Hours
    for day, start, end in hours:
        cursor.execute("INSERT INTO Doctor_Working_Hours (doctor_id, day_of_week, start_time, end_time) VALUES (?, ?, ?, ?)",
                       (doc_id, day, start, end))

# Patients
patients = [
    ('alice@mail.com', '12345', 'Alice', 'Johnson', '555-1001'),
    ('bob@mail.com', '12345', 'Bob', 'Williams', '555-1002'),
]

for email, pwd, fname, lname, phone in patients:
    cursor.execute("INSERT INTO Users (email, password, role_id, first_name, last_name) VALUES (?, ?, (SELECT role_id FROM Roles WHERE role_name='patient'), ?, ?)",
                   (email, pwd, fname, lname))
    user_id = cursor.lastrowid
    cursor.execute("INSERT INTO Patients (user_id, phone) VALUES (?, ?)", (user_id, phone))

conn.commit()
conn.close()
print("SQLite database 'clinic.db' created successfully.")
