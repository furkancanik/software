from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from typing import Optional, List
from datetime import date, datetime
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os

# ==========================================
# 1. SQLITE BAĞLANTISI (DEĞİŞTİ)
# ==========================================
# MySQL yerine SQLite kullanıyoruz.
SQLALCHEMY_DATABASE_URL = "sqlite:///./clinic.db"

# connect_args={"check_same_thread": False} SQLite için gereklidir
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

app = FastAPI(title="Clinic Appointment System (SQLite Version)")

# 1. Static klasörünü dış dünyaya açıyoruz
app.mount("/static", StaticFiles(directory="static"), name="static")

# Veritabanı Oturumu Aç/Kapat
def get_db():
    db = SessionLocal()
    # SQLite foreign keys desteğini aç
    db.execute(text("PRAGMA foreign_keys=ON"))
    try:
        yield db
    finally:
        db.close()

# ==========================================
# 2. VERİ MODELLERİ (Pydantic)
# ==========================================

class PatientRegister(BaseModel):
    email: str
    password: str
    first_name: str
    last_name: str
    phone: str

class UserLogin(BaseModel):
    email: str
    password: str

class AppointmentCreate(BaseModel):
    patient_id: int
    doctor_id: int
    slot_id: int
    appointment_date: date
    # user_id: int # Güvenlik için bunu login olan kullanıcıdan alacağız ama şimdilik client gönderiyor
    user_id: Optional[int] = None

# ==========================================
# 3. YARDIMCI FONKSİYONLAR (Stored Procedure Mantığı)
# ==========================================
# SQLite'da stored procedure olmadığı için mantığı buraya taşıdık.

def logic_register_patient(db: Session, p: PatientRegister):
    # 1. Email kontrolü
    existing = db.execute(text("SELECT 1 FROM Users WHERE email = :email"), {"email": p.email}).fetchone()
    if existing:
        raise Exception("Bu email adresi zaten kayıtlı.")

    # 2. Role ID bul
    role_row = db.execute(text("SELECT role_id FROM Roles WHERE role_name = 'patient'")).fetchone()
    if not role_row:
        raise Exception("Patient rolü bulunamadı.")
    role_id = role_row[0]

    # 3. User oluştur
    result = db.execute(text("""
        INSERT INTO Users (email, password, role_id, first_name, last_name)
        VALUES (:email, :pass, :role_id, :fname, :lname)
    """), {
        "email": p.email, "pass": p.password, "role_id": role_id,
        "fname": p.first_name, "lname": p.last_name
    })
    user_id = result.lastrowid

    # 4. Patient oluştur
    db.execute(text("""
        INSERT INTO Patients (user_id, phone) VALUES (:uid, :phone)
    """), {"uid": user_id, "phone": p.phone})
    
    db.commit()

def logic_create_appointment(db: Session, appt: AppointmentCreate):
    # Tarih kontrolü
    if appt.appointment_date < date.today():
         raise Exception("Geçmiş bir tarihe randevu alınamaz.")

    # 1. Doktor Aktif mi?
    doc = db.execute(text("SELECT 1 FROM Doctors WHERE doctor_id = :id AND is_active = 1"), {"id": appt.doctor_id}).fetchone()
    if not doc:
        raise Exception("Doktor aktif değil veya bulunamadı.")

    # 2. Hasta Aktif mi? (Basitçe var mı diye bakıyoruz)
    # user_id parametresi aslında hasta kullanıcısının ID'si olmalı
    # Biz patient_id üzerinden gidiyoruz
    pat = db.execute(text("""
        SELECT 1 FROM Patients p JOIN Users u ON p.user_id = u.user_id 
        WHERE p.patient_id = :pid AND u.is_active = 1
    """), {"pid": appt.patient_id}).fetchone()
    if not pat:
        raise Exception("Hasta aktif değil veya bulunamadı.")

    # 3. Çalışma Saati Kontrolü
    # Seçilen gün (Mon, Tue...) ve saat aralığı uyuyor mu?
    # SQLite'da gün ismini almak biraz zor, Python tarafında yapalım.
    day_name = appt.appointment_date.strftime("%a") # Mon, Tue...

    # Slot bilgilerini al
    slot = db.execute(text("SELECT start_time, end_time FROM Time_Slots WHERE slot_id = :sid"), {"sid": appt.slot_id}).fetchone()
    if not slot:
        raise Exception("Geçersiz saat dilimi.")
    
    s_start = slot[0] # "09:00:00" string olarak gelir
    s_end = slot[1]

    # Doktorun o günkü çalışma saatlerini çek
    hours = db.execute(text("""
        SELECT start_time, end_time FROM Doctor_Working_Hours
        WHERE doctor_id = :did AND day_of_week = :day
    """), {"did": appt.doctor_id, "day": day_name}).fetchone()

    if not hours:
        raise Exception(f"Doktor {day_name} günü çalışmıyor.")
    
    # Saat aralığı kontrolü (String karşılaştırma SQLite'da düzgün formatlıysa çalışır: HH:MM:SS)
    if not (s_start >= hours[0] and s_end <= hours[1]):
        raise Exception("Doktor bu saatlerde çalışmıyor.")

    # 4. Çakışma Kontrolü (UNIQUE constraint var ama biz önceden kontrol edelim)
    # Aynı doktora aynı saatte randevu var mı?
    conflict = db.execute(text("""
        SELECT 1 FROM Appointments 
        WHERE doctor_id = :did AND appointment_date = :date AND slot_id = :sid AND status_id != (SELECT status_id FROM Appointment_Status WHERE status_name='cancelled')
    """), {"did": appt.doctor_id, "date": appt.appointment_date, "sid": appt.slot_id}).fetchone()
    
    if conflict:
        raise Exception("Bu saat dolu (Overlap detected!)")

    # 5. Randevu Oluştur
    # Status: scheduled
    status_row = db.execute(text("SELECT status_id FROM Appointment_Status WHERE status_name = 'scheduled'")).fetchone()
    status_id = status_row[0]

    db.execute(text("""
        INSERT INTO Appointments (patient_id, doctor_id, slot_id, appointment_date, status_id)
        VALUES (:pid, :did, :sid, :date, :stat)
    """), {
        "pid": appt.patient_id,
        "did": appt.doctor_id,
        "sid": appt.slot_id,
        "date": appt.appointment_date,
        "stat": status_id
    })
    db.commit()


# ==========================================
# 4. API ENDPOINTLERİ
# ==========================================

@app.get("/")
def read_root():
    return FileResponse('static/ana_sayfa.html')

@app.post("/register")
def register_patient(user: PatientRegister, db: Session = Depends(get_db)):
    try:
        logic_register_patient(db, user)
        return {"message": "Kayıt başarılı", "email": user.email}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/login")
def login(user: UserLogin, db: Session = Depends(get_db)):
    try:
        # User ve Role bilgilerini çek
        row = db.execute(text("""
            SELECT u.user_id, u.role_id, r.role_name, u.first_name, u.last_name, p.patient_id
            FROM Users u
            JOIN Roles r ON u.role_id = r.role_id
            LEFT JOIN Patients p ON u.user_id = p.user_id
            WHERE u.email = :email AND u.password = :pass AND u.is_active = 1
        """), {"email": user.email, "pass": user.password}).fetchone()

        if not row:
            raise HTTPException(status_code=401, detail="Email veya şifre hatalı")

        # Hasta ise patient_id'yi user_id gibi kullanmak isteyebiliriz frontend'de
        # Ama doğrusu user_id dönmek. Frontend'e hem user_id hem patient_id (varsa) dönelim.
        # Bizim frontend user_id olarak patient_id bekliyor olabilir mi? Hayır, user_id generic.
        # Ancak randevu alırken 'patient_id' lazım.
        
        # Eğer hasta ise user_id yerine patient_id'yi 'user_id' alanına koyup hile yapabiliriz 
        # YA DA frontend'i patient_id kullanacak şekilde güncelledik.
        # Frontend 'patient_id: userInfo.user_id' gönderiyor. Bu yüzden patient isek user_id yerine patient_id dönelim.
        
        returned_id = row[0] # Normal user_id
        if row[2] == 'patient' and row[5] is not None:
             returned_id = row[5] # Patient ID

        return {
            "user_id": returned_id, # Frontend bunu patient_id olarak kullanıyor
            "role_id": row[1],
            "role_name": row[2],
            "first_name": row[3],
            "last_name": row[4]
        }
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/doctors")
def get_doctors(db: Session = Depends(get_db)):
    try:
        rows = db.execute(text("""
            SELECT d.doctor_id, u.first_name, u.last_name, d.expertise, u.email
            FROM Doctors d
            JOIN Users u ON d.user_id = u.user_id
            WHERE d.is_active = 1 AND u.is_active = 1
            ORDER BY u.last_name
        """)).fetchall()
        
        doctor_list = []
        for row in rows:
            doctor_list.append({
                "doctor_id": row[0],
                "first_name": row[1],
                "last_name": row[2],
                "expertise": row[3],
                "email": row[4]
            })
        return doctor_list
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
# ==========================================
# 5. ADMIN ENDPOINTLERİ
# ==========================================

class DoctorCreate(BaseModel):
    first_name: str
    last_name: str
    email: str
    password: str
    expertise: str

@app.get("/users")
def get_all_users(db: Session = Depends(get_db)):
    try:
        # Tüm kullanıcıları ve rollerini çek
        rows = db.execute(text("""
            SELECT u.first_name, u.last_name, u.email, r.role_name
            FROM Users u
            JOIN Roles r ON u.role_id = r.role_id
            WHERE u.is_active = 1
            ORDER BY u.created_at DESC
        """)).fetchall()
        
        users = []
        for r in rows:
            users.append({
                "name": f"{r[0]} {r[1]}",
                "email": r[2],
                "role": r[3]
            })
        return users
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/admin/doctors")
def add_doctor(doc: DoctorCreate, db: Session = Depends(get_db)):
    try:
        # 1. Email kontrol
        existing = db.execute(text("SELECT 1 FROM Users WHERE email = :email"), {"email": doc.email}).fetchone()
        if existing:
            raise HTTPException(status_code=400, detail="Bu email zaten kayıtlı.")
            
        # 2. Role ID
        role_row = db.execute(text("SELECT role_id FROM Roles WHERE role_name = 'doctor'")).fetchone()
        if not role_row:
             raise HTTPException(status_code=500, detail="Doctor rolü sistemde yok.")
        role_id = role_row[0]
        
        # 3. User Ekle
        res_user = db.execute(text("""
            INSERT INTO Users (email, password, role_id, first_name, last_name)
            VALUES (:email, :pass, :rid, :fname, :lname)
        """), {
            "email": doc.email,
            "pass": doc.password,
            "rid": role_id,
            "fname": doc.first_name,
            "lname": doc.last_name
        })
        user_id = res_user.lastrowid
        
        # 4. Doctor Tablosuna Ekle
        db.execute(text("""
            INSERT INTO Doctors (user_id, expertise) VALUES (:uid, :exp)
        """), {"uid": user_id, "exp": doc.expertise})

        # 5. Varsayılan Çalışma Saatleri (Örn: Mon-Fri 09:00-17:00)
        # İsteğe bağlı, şimdilik boş bırakıyoruz, doktor kendisi eklesin.
        
        db.commit()
        return {"message": "Doktor başarıyla eklendi."}

    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/doctors/{doctor_email}")
def delete_doctor(doctor_email: str, db: Session = Depends(get_db)):
    try:
        # Önce bu email'e sahip user'ı bul
        user = db.execute(text("SELECT user_id, role_id FROM Users WHERE email = :email"), {"email": doctor_email}).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
            
        user_id = user[0]
        role_id = user[1]
        
        # Role kontrol (Sadece doktorları siliyoruz buradan)
        role = db.execute(text("SELECT role_name FROM Roles WHERE role_id = :rid"), {"rid": role_id}).fetchone()
        if role and role[0] != 'doctor':
             raise HTTPException(status_code=400, detail="Sadece doktorları silebilirsiniz.")

        # Doktorun ID'sini al
        doctor = db.execute(text("SELECT doctor_id FROM Doctors WHERE user_id = :uid"), {"uid": user_id}).fetchone()
        if doctor:
            doctor_id = doctor[0]
            
            # Foreign key kontrolünü geçici olarak kapat
            db.execute(text("PRAGMA foreign_keys=OFF"))
            
            try:
                # İlişkili kayıtları sil (eğer varsa)
                # 1. Doctor_Working_Hours
                db.execute(text("DELETE FROM Doctor_Working_Hours WHERE doctor_id = :did"), {"did": doctor_id})
                
                # 2. Appointments
                db.execute(text("DELETE FROM Appointments WHERE doctor_id = :did"), {"did": doctor_id})
                
                # 3. Doctors tablosundan sil
                db.execute(text("DELETE FROM Doctors WHERE doctor_id = :did"), {"did": doctor_id})
                
                # 4. User tablosundan sil
                db.execute(text("DELETE FROM Users WHERE user_id = :uid"), {"uid": user_id})
                
                db.commit()
                
            finally:
                # Foreign key kontrolünü tekrar aç
                db.execute(text("PRAGMA foreign_keys=ON"))
        else:
            raise HTTPException(status_code=404, detail="Doktor kaydı bulunamadı.")
        
        return {"message": "Doktor tamamen silindi."}
        
    except HTTPException as he:
        raise he
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/admin/users/{email}")
def delete_user(email: str, db: Session = Depends(get_db)):
    try:
        # User bul
        user = db.execute(text("SELECT user_id, role_id FROM Users WHERE email = :email"), {"email": email}).fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
        
        user_id = user[0]
        role_id = user[1]
        
        # Rolü kontrol et
        role = db.execute(text("SELECT role_name FROM Roles WHERE role_id = :rid"), {"rid": role_id}).fetchone()
        if not role:
             raise HTTPException(status_code=404, detail="Rol bulunamadı.")
        
        role_name = role[0]

        # Admin silinemez
        if role_name == 'admin':
            raise HTTPException(status_code=400, detail="Admin kullanıcıları silinemez.")

        # Silelim (Soft delete yerine hard delete yapalım veya soft delete)
        # Kullanıcının bağlı kayıtlarını da temizlemek gerekebilir veya is_active=0 yaparız.
        # İsteğine Soft Delete (Pasif yapma) ile devam edelim, böylece veri kaybı olmaz.
        
        db.execute(text("UPDATE Users SET is_active = 0 WHERE user_id = :uid"), {"uid": user_id})
        
        # Eğer doktorsa doktor tablosunu da pasif yap
        if role_name == 'doctor':
             db.execute(text("UPDATE Doctors SET is_active = 0 WHERE user_id = :uid"), {"uid": user_id})
             
        db.commit()
        return {"message": f"{role_name} kullanıcısı silindi (pasif yapıldı)."}

    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/appointments")
def create_appointment_endpoint(appt: AppointmentCreate, db: Session = Depends(get_db)):
    try:
        logic_create_appointment(db, appt)
        return {"message": "Randevu başarıyla oluşturuldu!", "status": "success"}
    except Exception as e:
        error_msg = str(e)
        if "Overlap" in error_msg:
             raise HTTPException(status_code=400, detail=error_msg)
        elif "çalışmıyor" in error_msg:
             raise HTTPException(status_code=400, detail=error_msg)
        else:
             raise HTTPException(status_code=400, detail=f"İşlem başarısız: {error_msg}")

@app.get("/available-slots/")
def get_slots(doctor_id: int, date: str, db: Session = Depends(get_db)):
    try:
        # Tarih string geliyor "YYYY-MM-DD"
        # Hangi gün olduğunu bul
        date_obj = datetime.strptime(date, "%Y-%m-%d").date()
        day_name = date_obj.strftime("%a") # Mon, Tue...

        # Doktorun çalışma saatleri
        wh = db.execute(text("""
            SELECT start_time, end_time FROM Doctor_Working_Hours
            WHERE doctor_id = :did AND day_of_week = :day
        """), {"did": doctor_id, "day": day_name}).fetchone()

        if not wh:
            return [] # O gün çalışmıyor

        doc_start, doc_end = wh[0], wh[1]

        # Tüm slotları çek ve aralığa uyanları filtrele
        all_slots = db.execute(text("SELECT slot_id, start_time, end_time FROM Time_Slots ORDER BY start_time")).fetchall()
        
        valid_slots = []
        for s in all_slots:
            s_id, s_start, s_end = s
            # Aralık içinde mi?
            if s_start >= doc_start and s_end <= doc_end:
                # Dolu mu?
                is_taken = db.execute(text("""
                    SELECT 1 FROM Appointments 
                    WHERE doctor_id = :did AND appointment_date = :date AND slot_id = :sid AND status_id != (SELECT status_id FROM Appointment_Status WHERE status_name='cancelled')
                """), {"did": doctor_id, "date": date, "sid": s_id}).fetchone()
                
                if not is_taken:
                    valid_slots.append({
                        "slot_id": s_id,
                        "start_time": s_start,
                        "end_time": s_end
                    })
        
        return valid_slots

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))