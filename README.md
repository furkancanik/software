<h1 align="center">Klinik Randevu Sistemi</h1>

<p align="center">
  <a href="#-özellikler" style="color: #0366d6">Özellikler</a>
  .
  <a href="#-teknolojiler" style="color: #0366d6">Teknolojiler</a>
  .
  <a href="#-kurulum-ve-çalıştırma" style="color: #0366d6">Kurulum ve Çalıştırma</a>
  .
  <a href="#-örnek-giriş-bilgileri" style="color: #0366d6">Örnek Giriş Bilgileri</a>
  <br>
</p>

Bu proje, bir kliniğin randevu süreçlerini yönetmek için geliştirilmiş web tabanlı bir uygulamadır. Sistem; hastaların randevu almasını, doktorların çalışma saatlerini yönetmesini ve yöneticilerin doktor/kullanıcı hesaplarını kontrol etmesini sağlar.

## 🚀 Özellikler

- **Çoklu Rol Desteği:** Hasta, Doktor, Sekreter ve Admin rolleri mevcuttur.
- **Randevu Yönetimi:** Hastalar aktif doktorlardan uygun saat dilimlerine randevu alabilir.
- **Doktor Paneli:** Doktorlar kendi çalışma saatlerini güncelleyebilir ve randevularını görebilir.
- **Admin Paneli:** Doktor ekleme/silme ve kullanıcı listeleme işlemleri yapılabilir.
- **Çakışma Kontrolü:** Aynı saat dilimine birden fazla randevu verilmesi engellenir.
- **SQLite Veritabanı:** Kurulumu kolay ve hafif bir veritabanı yapısı kullanılmıştır.

## 🛠️ Teknolojiler

- **Backend:** FastAPI (Python)
- **Veritabanı:** SQLite & SQLAlchemy
- **Frontend:** HTML5, CSS3, JavaScript (Vanilla)

## 📦 Kurulum ve Çalıştırma

Projeyi yerel makinenizde çalıştırmak için aşağıdaki adımları takip edebilirsiniz:

### 1. Gereksinimler
Sisteminizde **Python 3.8+** yüklü olmalıdır.

### 2. Sanal Ortam Oluşturun (venv)
Bağımlılıkların izole bir ortamda kurulması için sanal ortam oluşturun ve aktif edin:

**macOS / Linux:**
```bash
python3 -m venv venv
source venv/bin/activate
```

**Windows:**
```bash
python -m venv venv
.\venv\Scripts\activate
```

### 3. Bağımlılıkları Yükleyin
Sanal ortam aktifken gerekli paketleri şu komutla yükleyin:

```bash
pip install fastapi sqlalchemy uvicorn pydantic
```

### 4. Veritabanını Hazırlayın
Veritabanını ve gerekli tabloları oluşturup örnek verileri yüklemek için `init_sqlite.py` dosyasını çalıştırın, (eğer python komutu çalışmaz ise python3 yazınız):

```bash
python init_sqlite.py
```
Bu işlemden sonra klasörde `clinic.db` dosyası oluşacaktır.

### 5. Uygulamayı Başlatın
Uygulamayı uvicorn ile ayağa kaldırın:

```bash
uvicorn main:app --reload
```

Durdurmak için 
`ctrl + C`

### 6. Erişim
Tarayıcınızdan şu adrese giderek uygulamayı kullanmaya başlayabilirsiniz:
- **Uygulama:** [http://127.0.0.1:8000](http://127.0.0.1:8000)
- **API Dokümantasyonu (Swagger):** [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)

## 🔑 Örnek Giriş Bilgileri
Veritabanı ilklendirildiğinde aşağıdaki hesaplar otomatik olarak oluşturulur:

- **Admin:** admin@clinic.com / admin
- **Hasta:** alice@mail.com / 12345
- **Doktor:** dr.smith@clinic.com / 12345
- **Sekreter:** secretary@clinic.com / secretary
